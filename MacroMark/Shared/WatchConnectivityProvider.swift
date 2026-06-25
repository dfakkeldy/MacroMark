import Foundation
@preconcurrency import WatchConnectivity
import Observation
import MacroMarkKit

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
    var onFileReceived: ((UUID, URL, Date) -> Void)? {
        didSet {
            if let handler = onFileReceived, !pendingReceivedFiles.isEmpty {
                let files = pendingReceivedFiles
                pendingReceivedFiles.removeAll()
                for (id, url, timestamp) in files {
                    handler(id, url, timestamp)
                }
            }
        }
    }

    /// Buffers for data received before the handlers are set (race condition on app launch).
    private var pendingReceivedNotes: [(UUID, String, Date)] = []
    private var pendingReceivedFiles: [(UUID, URL, Date)] = []

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
            LocalStore.shared.syncPendingAudio()
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
            LocalStore.shared.removeAudio(withId: id)
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
        let idString = file.metadata?["id"] as? String ?? UUID().uuidString
        let id = UUID(uuidString: idString) ?? UUID()

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
                handler(id, destURL, timestamp)
            } else {
                pendingReceivedFiles.append((id, destURL, timestamp))
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
            // Un-queue the note so the next sync actually re-sends it. Without this,
            // queuedNoteIDs still contains the id and syncPendingNotes would skip it.
            if let idString = userInfoTransfer.userInfo["id"] as? String,
               let id = UUID(uuidString: idString) {
                LocalStore.shared.markNoteUnqueued(id)
                LocalStore.shared.syncPendingNotes()
            }
        }
        // Success case: note is NOT removed here. We wait for the phone's ACK
        // (via didReceiveUserInfo with "ack" key) before deleting from LocalStore.
#endif
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
#if os(watchOS)
        if let error = error {
#if DEBUG
            print("File transfer failed with error: \(String(describing: error))")
#endif
            // Un-queue so the audio note is re-sent on the next sync. The file
            // stays in LocalStore's durable audio dir until the phone ACKs it.
            if let idString = fileTransfer.file.metadata?["id"] as? String,
               let id = UUID(uuidString: idString) {
                LocalStore.shared.markAudioUnqueued(id)
            }
        }
        // Success case: audio is NOT removed here. We wait for the phone's ACK
        // (via didReceiveUserInfo with "ackFile" key) before deleting it.
#endif
    }

    // MARK: - Settings Sync

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let captureMode = applicationContext["captureMode"] as? String {
            UserDefaults.standard.set(captureMode, forKey: UserDefaultsKey.captureMode.rawValue)
        }
    }

    // MARK: - Daily File Fetch

    private func dailyLogCacheKey(for date: Date) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        return "\(UserDefaultsKey.cachedDailyLog.rawValue)-\(day)"
    }

    func fetchDailyFile(for date: Date = Date()) async -> String {
        let cacheKey = dailyLogCacheKey(for: date)

        guard let session = session else {
            return UserDefaults.standard.string(forKey: cacheKey) ?? ""
        }

        for _ in 0..<10 {
            if session.activationState == .activated { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard session.activationState == .activated else {
            return UserDefaults.standard.string(forKey: cacheKey) ?? ""
        }

        return await withCheckedContinuation { continuation in
            let timeout = ContinuationTimeout()
            
            Task {
                try? await Task.sleep(for: .seconds(15))
                if await timeout.complete() {
                    let cached = UserDefaults.standard.string(forKey: cacheKey) ?? ""
                    continuation.resume(returning: cached)
                }
            }
            
            session.sendMessage(["request": "dailyFile", "date": date.timeIntervalSince1970], replyHandler: { reply in
                Task {
                    if await timeout.complete() {
                        let content = reply["content"] as? String ?? ""
                        UserDefaults.standard.set(content, forKey: cacheKey)
                        continuation.resume(returning: content)
                    }
                }
            }, errorHandler: { error in
                Task {
                    if await timeout.complete() {
                        let cached = UserDefaults.standard.string(forKey: cacheKey) ?? ""
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
            let timestamp = message["date"] as? TimeInterval ?? Date().timeIntervalSince1970
            let date = Date(timeIntervalSince1970: timestamp)
            let content = iCloudStorageManager.shared.readText(for: date) ?? ""
            replyHandler(["content": content])
        }
#endif
    }
}
