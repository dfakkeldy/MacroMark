import Foundation
import WatchConnectivity
import Observation
#if os(iOS)
import MacroMarkKit
#endif

@MainActor
@Observable
final class WatchConnectivityProvider: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityProvider()
    
    private let session: WCSession?
    
    // For iOS to process received notes
    var onNoteReceived: ((String, Double?, Double?) -> Void)?
    var onFileReceived: ((URL, Double?, Double?) -> Void)?
    
    private var pendingUserInfo: [[String: Any]] = []
    private var pendingFiles: [(url: URL, metadata: [String: Any])] = []
    
    private override init() {
        if WCSession.isSupported() {
            session = WCSession.default
        } else {
            session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("WCSession activation completed: \(activationState.rawValue), error: \(String(describing: error))")
        if activationState == .activated {
            for userInfo in pendingUserInfo {
                session.transferUserInfo(userInfo)
            }
            pendingUserInfo.removeAll()
            
            for file in pendingFiles {
                session.transferFile(file.url, metadata: file.metadata)
            }
            pendingFiles.removeAll()
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
    
    // Send a note from Watch to iOS
    func sendNote(_ noteId: UUID, text: String, timestamp: Date, latitude: Double? = nil, longitude: Double? = nil) {
        var userInfo: [String: Any] = [
            "id": noteId.uuidString,
            "text": text,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        if let lat = latitude, let lon = longitude {
            userInfo["latitude"] = lat
            userInfo["longitude"] = lon
        }
        
        guard let session = session else { return }
        
        if session.activationState == .activated {
            session.transferUserInfo(userInfo)
        } else {
            pendingUserInfo.append(userInfo)
            print("WCSession not activated, queued note: \(noteId)")
        }
    }
    
    // Send a file from Watch to iOS
    func sendFile(_ url: URL, id: UUID, latitude: Double? = nil, longitude: Double? = nil) {
        var metadata: [String: Any] = [
            "id": id.uuidString
        ]
        if let lat = latitude, let lon = longitude {
            metadata["latitude"] = lat
            metadata["longitude"] = lon
        }
        
        guard let session = session else { return }
        
        if session.activationState == .activated {
            session.transferFile(url, metadata: metadata)
        } else {
            pendingFiles.append((url: url, metadata: metadata))
            print("WCSession not activated, queued file: \(id)")
        }
    }
    
    // Update Application Context (Settings Sync)
    func updateSettings(captureMode: String) {
        guard let session = session, session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext(["captureMode": captureMode])
        } catch {
            print("Failed to update application context: \(error)")
        }
    }
    
    // Receive UserInfo
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            #if os(iOS)
            if let text = userInfo["text"] as? String {
                let latitude = userInfo["latitude"] as? Double
                let longitude = userInfo["longitude"] as? Double
                print("Received text from watch: \(text)")
                onNoteReceived?(text, latitude, longitude)
            }
            #endif
        }
    }
    
    // Receive File (for audio files from InstantCaptureView)
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let latitude = metadata["latitude"] as? Double
        let longitude = metadata["longitude"] as? Double
        
        // Move the file to a permanent location before this method returns
        let tempURL = file.fileURL
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempURL.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destURL)
            
            Task { @MainActor in
                #if os(iOS)
                print("Received audio file from watch")
                onFileReceived?(destURL, latitude, longitude)
                #endif
            }
        } catch {
            print("Failed to copy received file: \(error)")
        }
    }
    
    // Called when the user info finishes transferring. Watch uses this to know it was received and delete local cache.
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            #if os(watchOS)
            if error == nil {
                if let idString = userInfoTransfer.userInfo["id"] as? String, let id = UUID(uuidString: idString) {
                    NotificationCenter.default.post(name: .noteTransferDidComplete, object: nil, userInfo: ["id": id])
                }
            } else {
                print("Transfer failed with error: \(String(describing: error))")
            }
            #endif
        }
    }
    
    // Receive Application Context (Settings Sync)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            if let captureMode = applicationContext["captureMode"] as? String {
                UserDefaults.standard.set(captureMode, forKey: "captureMode")
            }
        }
    }
    
    func fetchDailyFile() async -> String {
        guard let session = session, session.activationState == .activated else {
            return UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
        }
        
        do {
            let content: String = try await withCheckedThrowingContinuation { continuation in
                session.sendMessage(["request": "dailyFile"], replyHandler: { reply in
                    if let content = reply["content"] as? String {
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(throwing: NSError(domain: "WatchConnectivity", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid reply content."]))
                    }
                }, errorHandler: { error in
                    continuation.resume(throwing: error)
                })
            }
            UserDefaults.standard.set(content, forKey: "cachedDailyLog")
            return content
        } catch {
            print("Failed to fetch daily file: \(error). Falling back to cache.")
            return UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
        }
    }
    
    // Handle message requests (e.g., from Watch)
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        #if os(iOS)
        if let request = message["request"] as? String, request == "dailyFile" {
            let content = iCloudStorageManager.shared.readText() ?? ""
            replyHandler(["content": content])
        }
        #endif
    }
}

extension Notification.Name {
    static let noteTransferDidComplete = Notification.Name("noteTransferDidComplete")
}
