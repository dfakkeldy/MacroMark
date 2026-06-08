import Foundation
@preconcurrency import WatchConnectivity
import Observation
#if os(iOS)
import MacroMarkKit
#endif

actor ContinuationTimeout {
    var hasCompleted = false
    func complete() -> Bool {
        if hasCompleted { return false }
        hasCompleted = true
        return true
    }
}

@MainActor
@Observable
final class WatchConnectivityProvider: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityProvider()

    private let session: WCSession?

    // For iOS to process received notes
    var onNoteReceived: ((UUID, String, Date) -> Void)? {
        didSet {
            // Replay any notes that arrived before the handler was set
            if let handler = onNoteReceived, !pendingReceivedNotes.isEmpty {
                let notes = pendingReceivedNotes
                pendingReceivedNotes.removeAll()
                for (id, text, timestamp) in notes {
                    handler(id, text, timestamp)
                }
            }
        }
    }
    var onFileReceived: ((URL, Date) -> Void)? {
        didSet {
            if let handler = onFileReceived, !pendingReceivedFiles.isEmpty {
                let files = pendingReceivedFiles
                pendingReceivedFiles.removeAll()
                for (url, timestamp) in files {
                    handler(url, timestamp)
                }
            }
        }
    }

    /// Buffers for data received before the handlers are set (race condition on app launch).
    private var pendingReceivedNotes: [(UUID, String, Date)] = []
    private var pendingReceivedFiles: [(URL, Date)] = []

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

    // MARK: - WCSessionDelegate (all methods already @MainActor via class annotation)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
#if DEBUG
        print("WCSession activation completed: \(activationState.rawValue), error: \(String(describing: error))")
#endif
#if os(watchOS)
        if activationState == .activated {
            LocalStore.shared.syncPendingNotes()
        }
#endif
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif

    // MARK: - Sending

    @discardableResult
    func sendNote(_ noteId: UUID, text: String, timestamp: Date) -> Bool {
        guard let session = session, session.activationState == .activated else { return false }
        let userInfo: [String: Any] = [
            "id": noteId.uuidString,
            "text": text,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        session.transferUserInfo(userInfo)
        return true
    }

    @discardableResult
    func sendFile(_ url: URL, id: UUID, timestamp: Date) -> Bool {
        guard let session = session, session.activationState == .activated else { return false }
        let metadata: [String: Any] = [
            "id": id.uuidString,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        session.transferFile(url, metadata: metadata)
        return true
    }

#if os(iOS)
    /// Send an acknowledgement back to the watch confirming the note was durably saved.
    /// The watch should only delete a note from its LocalStore after receiving this ACK.
    func acknowledgeNote(id: UUID) {
        guard let session = session else { return }
        session.transferUserInfo(["ack": id.uuidString])
    }

    /// Send an acknowledgement for a received file.
    func acknowledgeFile(id: UUID) {
        guard let session = session else { return }
        session.transferUserInfo(["ackFile": id.uuidString])
    }
#endif

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

    // MARK: - Receiving

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        // --- Watch side: handle acknowledgements from phone ---
#if os(watchOS)
        if let ackId = userInfo["ack"] as? String, let id = UUID(uuidString: ackId) {
            LocalStore.shared.removeNote(withId: id)
            return
        }
        if let ackId = userInfo["ackFile"] as? String, let id = UUID(uuidString: ackId) {
            LocalStore.shared.removeNote(withId: id)
            return
        }
#endif

        // --- Phone side: handle incoming notes from watch ---
        if let text = userInfo["text"] as? String {
            let idString = userInfo["id"] as? String ?? UUID().uuidString
            let id = UUID(uuidString: idString) ?? UUID()
            let timestampInterval = userInfo["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
            let timestamp = Date(timeIntervalSince1970: timestampInterval)
            if let handler = onNoteReceived {
                handler(id, text, timestamp)
            } else {
                // Handler not set yet — buffer for replay when set
                pendingReceivedNotes.append((id, text, timestamp))
            }
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let tempURL = file.fileURL
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempURL.lastPathComponent)

        let timestampInterval = file.metadata?["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let timestamp = Date(timeIntervalSince1970: timestampInterval)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destURL)

#if os(iOS)
#if DEBUG
            print("Received audio file from watch")
#endif
            if let handler = onFileReceived {
                handler(destURL, timestamp)
            } else {
                pendingReceivedFiles.append((destURL, timestamp))
            }
#endif
        } catch {
#if DEBUG
            print("Failed to copy received file: \(error)")
#endif
        }
    }

    // MARK: - Transfer Completion

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
#if os(watchOS)
        if let error = error {
#if DEBUG
            print("Transfer failed with error: \(String(describing: error))")
#endif
            // Note stays in LocalStore — will be re-sent on next syncPendingNotes call
        }
        // Success case: note is NOT removed here. We wait for the phone's ACK
        // (via didReceiveUserInfo with "ack" key) before deleting from LocalStore.
#endif
    }

    // MARK: - Settings Sync

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let captureMode = applicationContext["captureMode"] as? String {
            UserDefaults.standard.set(captureMode, forKey: "captureMode")
        }
    }

    // MARK: - Daily File Fetch

    func fetchDailyFile() async -> String {
        guard let session = session else {
            return UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
        }

        for _ in 0..<10 {
            if session.activationState == .activated { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard session.activationState == .activated else {
            return UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
        }

        return await withCheckedContinuation { continuation in
            let timeout = ContinuationTimeout()
            
            Task {
                try? await Task.sleep(for: .seconds(15))
                if await timeout.complete() {
                    let cached = UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
                    continuation.resume(returning: cached)
                }
            }
            
            session.sendMessage(["request": "dailyFile"], replyHandler: { reply in
                Task {
                    if await timeout.complete() {
                        let content = reply["content"] as? String ?? ""
                        UserDefaults.standard.set(content, forKey: "cachedDailyLog")
                        continuation.resume(returning: content)
                    }
                }
            }, errorHandler: { error in
                Task {
                    if await timeout.complete() {
                        let cached = UserDefaults.standard.string(forKey: "cachedDailyLog") ?? ""
                        continuation.resume(returning: cached)
                    }
                }
            })
        }
    }

    // MARK: - Message Handler

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
#if os(iOS)
        if let request = message["request"] as? String, request == "dailyFile" {
            let content = iCloudStorageManager.shared.readText() ?? ""
            replyHandler(["content": content])
        }
#endif
    }
}
