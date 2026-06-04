import Foundation
@preconcurrency import WatchConnectivity
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
    var onNoteReceived: ((String, Date) -> Void)?
    var onFileReceived: ((URL, Date) -> Void)?

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
        #if DEBUG
        print("WCSession activation completed: \(activationState.rawValue), error: \(String(describing: error))")
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    // Send a note from Watch to iOS
    func sendNote(_ noteId: UUID, text: String, timestamp: Date) {
        let userInfo: [String: Any] = [
            "id": noteId.uuidString,
            "text": text,
            "timestamp": timestamp.timeIntervalSince1970
        ]

        guard let session = session else { return }
        session.transferUserInfo(userInfo)
    }

    // Send a file from Watch to iOS
    func sendFile(_ url: URL, id: UUID, timestamp: Date) {
        let metadata: [String: Any] = [
            "id": id.uuidString,
            "timestamp": timestamp.timeIntervalSince1970
        ]

        guard let session = session else { return }
        session.transferFile(url, metadata: metadata)
    }

    // Update Application Context (Settings Sync)
    func updateSettings(captureMode: String) {
        guard let session = session, session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext(["captureMode": captureMode])
        } catch {
            #if DEBUG
            print("Failed to update application context: \(error)")
            #endif
        }
    }

    // Receive UserInfo
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let text = userInfo["text"] as? String {
            let timestampInterval = userInfo["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
            let timestamp = Date(timeIntervalSince1970: timestampInterval)
            Task { @MainActor in
                onNoteReceived?(text, timestamp)
            }
        }
    }

    // Receive File (for audio files from InstantCaptureView)
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Move the file to a permanent location before this method returns
        let tempURL = file.fileURL
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempURL.lastPathComponent)

        let timestampInterval = file.metadata?["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let timestamp = Date(timeIntervalSince1970: timestampInterval)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destURL)

            Task { @MainActor in
                #if os(iOS)
                #if DEBUG
                print("Received audio file from watch")
                #endif
                onFileReceived?(destURL, timestamp)
                #endif
            }
        } catch {
            #if DEBUG
            print("Failed to copy received file: \(error)")
            #endif
        }
    }

    // Called when the user info finishes transferring.
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            #if os(watchOS)
            if error == nil {
                if let idString = userInfoTransfer.userInfo["id"] as? String, let id = UUID(uuidString: idString) {
                    NotificationCenter.default.post(name: .noteTransferDidComplete, object: nil, userInfo: ["id": id])
                }
            } else {
                #if DEBUG
                print("Transfer failed with error: \(String(describing: error))")
                #endif
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
        guard let session = session else {
            return UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
        }

        // Wait up to 1 second for session activation if needed
        for _ in 0..<10 {
            if session.activationState == .activated { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard session.activationState == .activated else {
            return UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
        }

        do {
            // Race sendMessage against a 10-second timeout to avoid hanging
            // if the watch becomes unreachable mid-request.
            let content: String = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
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
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    throw NSError(domain: "WatchConnectivity", code: 3, userInfo: [NSLocalizedDescriptionKey: "Request timed out."])
                }

                guard let result = try await group.next() else {
                    throw NSError(domain: "WatchConnectivity", code: 4, userInfo: [NSLocalizedDescriptionKey: "No result."])
                }
                group.cancelAll()
                return result
            }
            UserDefaults.standard.set(content, forKey: "cachedDailyLog")
            return content
        } catch {
            #if DEBUG
            print("Failed to fetch daily file: \(error). Falling back to cache.")
            #endif
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
