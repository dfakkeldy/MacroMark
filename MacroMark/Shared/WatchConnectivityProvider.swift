import Foundation
@preconcurrency import WatchConnectivity
import Observation
import MacroMarkKit

@MainActor
@Observable
final class WatchConnectivityProvider: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityProvider()

    private let session: WCSession?
    private var pendingCaptureMode: String?

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

    // MARK: - WCSessionDelegate
    //
    // WCSession invokes these delegate callbacks on its own background queue, NOT
    // the main actor. They MUST be `nonisolated`: a MainActor-isolated delegate
    // method called off-main traps at runtime under Swift 6 (the executor check
    // fires `dispatch_assert_queue_fail`). Each method snapshots the Sendable
    // values it needs and hops to the main actor only for work that touches
    // MainActor state (LocalStore, the received-handlers, the pending buffers).

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
#if DEBUG
        print("WCSession activation completed: \(activationState.rawValue), error: \(String(describing: error))")
#endif
#if os(watchOS)
        if activationState == .activated {
            Task { @MainActor in
                LocalStore.shared.syncPendingNotes()
                LocalStore.shared.syncPendingAudio()
            }
        }
#elseif os(iOS)
        if activationState == .activated {
            Task { @MainActor in
                flushPendingSettings()
            }
        }
#endif
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
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

#if os(watchOS)
    func queryProcessed(id: UUID) {
        guard let session = session, session.activationState == .activated else { return }

        session.sendMessage(["queryProcessed": id.uuidString], replyHandler: { @Sendable reply in
            let processed = (reply["processed"] as? Bool) == true
            guard processed else { return }

            Task { @MainActor in
                LocalStore.shared.removeNote(withId: id)
                LocalStore.shared.removeAudio(withId: id)
            }
        }, errorHandler: { @Sendable _ in })
    }
#endif

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
        pendingCaptureMode = captureMode
        guard sendCaptureModeContext(captureMode) else { return }
        pendingCaptureMode = nil
    }

    private func flushPendingSettings() {
        let captureMode = pendingCaptureMode
            ?? UserDefaults.standard.string(forKey: UserDefaultsKey.captureMode.rawValue)
            ?? "audio"
        guard sendCaptureModeContext(captureMode) else {
            pendingCaptureMode = captureMode
            return
        }
        pendingCaptureMode = nil
    }

    private func sendCaptureModeContext(_ captureMode: String) -> Bool {
        guard let session = session, session.activationState == .activated else { return false }
        do {
            try session.updateApplicationContext(["captureMode": captureMode])
            return true
        } catch {
#if DEBUG
            print("Failed to update application context: \(error)")
#endif
            return false
        }
    }

    // MARK: - Receiving

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        // --- Watch side: handle acknowledgements from phone ---
#if os(watchOS)
        if let ackId = userInfo["ack"] as? String, let id = UUID(uuidString: ackId) {
            Task { @MainActor in LocalStore.shared.removeNote(withId: id) }
            return
        }
        if let ackId = userInfo["ackFile"] as? String, let id = UUID(uuidString: ackId) {
            Task { @MainActor in LocalStore.shared.removeAudio(withId: id) }
            return
        }
#endif

        // --- Phone side: handle incoming notes from watch ---
        if let text = userInfo["text"] as? String {
            guard let idString = userInfo["id"] as? String,
                  let id = UUID(uuidString: idString) else {
#if DEBUG
                print("Ignoring received note with missing or invalid id")
#endif
                return
            }
            let timestampInterval = userInfo["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
            let timestamp = Date(timeIntervalSince1970: timestampInterval)
            // Snapshot the Sendable values above, then touch MainActor state on-actor.
            Task { @MainActor in
                if let handler = onNoteReceived {
                    handler(id, text, timestamp)
                } else {
                    // Handler not set yet — buffer for replay when set
                    pendingReceivedNotes.append((id, text, timestamp))
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let tempURL = file.fileURL
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempURL.lastPathComponent)

        let timestampInterval = file.metadata?["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let timestamp = Date(timeIntervalSince1970: timestampInterval)
        guard let idString = file.metadata?["id"] as? String,
              let id = UUID(uuidString: idString) else {
#if DEBUG
            print("Ignoring received file with missing or invalid id")
#endif
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            // The copy MUST run synchronously here: WCSession deletes the inbox file
            // as soon as this delegate method returns, so deferring it into a Task
            // would lose the audio. Only the MainActor handoff below is deferred.
            try FileManager.default.copyItem(at: tempURL, to: destURL)

#if os(iOS)
#if DEBUG
            print("Received audio file from watch")
#endif
            Task { @MainActor in
                if let handler = onFileReceived {
                    handler(id, destURL, timestamp)
                } else {
                    pendingReceivedFiles.append((id, destURL, timestamp))
                }
            }
#endif
        } catch {
#if DEBUG
            print("Failed to copy received file: \(error)")
#endif
        }
    }

    // MARK: - Transfer Completion

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
#if os(watchOS)
        if let error = error {
#if DEBUG
            print("Transfer failed with error: \(String(describing: error))")
#endif
            // Un-queue the note so the next sync actually re-sends it. Without this,
            // queuedNoteIDs still contains the id and syncPendingNotes would skip it.
            if let idString = userInfoTransfer.userInfo["id"] as? String,
               let id = UUID(uuidString: idString) {
                Task { @MainActor in
                    LocalStore.shared.markNoteUnqueued(id)
                    LocalStore.shared.syncPendingNotes()
                }
            }
        }
        // Success case: note is NOT removed here. We wait for the phone's ACK
        // (via didReceiveUserInfo with "ack" key) before deleting from LocalStore.
#endif
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
#if os(watchOS)
        if let error = error {
#if DEBUG
            print("File transfer failed with error: \(String(describing: error))")
#endif
            // Un-queue so the audio note is re-sent on the next sync. The file
            // stays in LocalStore's durable audio dir until the phone ACKs it.
            if let idString = fileTransfer.file.metadata?["id"] as? String,
               let id = UUID(uuidString: idString) {
                Task { @MainActor in
                    LocalStore.shared.markAudioUnqueued(id)
                }
            }
        }
        // Success case: audio is NOT removed here. We wait for the phone's ACK
        // (via didReceiveUserInfo with "ackFile" key) before deleting it.
#endif
    }

    // MARK: - Settings Sync

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        // Only touches UserDefaults (thread-safe), so no main-actor hop is needed.
        if let captureMode = applicationContext["captureMode"] as? String {
            UserDefaults.standard.set(captureMode, forKey: UserDefaultsKey.captureMode.rawValue)
        }
    }

    // MARK: - Daily File Fetch

    /// Routes the legacy date‑based request through the bounded file protocol.
    func fetchDailyFile(for date: Date = Date()) async -> String {
#if os(watchOS)
        let path = iCloudStorageManager.shared.dailyLogRelativePath(for: date)
        guard DailyLogFilePath.isSafeRelativeMarkdownPath(path) else { return "" }
        return (try? await fetchDailyFile(relativePath: path)) ?? ""
#else
        // iOS: read directly from the phone's storage.
        let path = iCloudStorageManager.shared.dailyLogRelativePath(for: date)
        guard DailyLogFilePath.isSafeRelativeMarkdownPath(path),
              let data = iCloudStorageManager.shared.readData(relativePath: path),
              data.count <= DailyLogTransfer.maximumFileByteCount,
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
#endif
    }

#if os(watchOS)
    func fetchDailyLogFileIndex() async throws -> DailyLogFileIndex {
        var paths: [String] = []
        var offset = 0
        var todayPath: String?

        for _ in 0..<DailyLogTransfer.maximumIndexPageCount {
            try Task.checkCancellation()
            let page = try await fetchDailyLogFileIndexPage(offset: offset)
            if todayPath == nil {
                todayPath = page.todayPath
            }

            guard page.paths.allSatisfy(DailyLogFilePath.isSafeRelativeMarkdownPath),
                  !page.paths.contains(where: paths.contains)
            else {
                throw DailyLogFetchError.invalidResponse
            }
            if page.isTruncated {
                throw DailyLogFetchError.indexTruncated
            }

            paths.append(contentsOf: page.paths)
            guard paths.count <= DailyLogTransfer.maximumIndexPathCount else {
                throw DailyLogFetchError.indexTruncated
            }

            guard let nextOffset = page.nextOffset else {
                return DailyLogFileIndex(paths: paths, todayPath: todayPath)
            }
            guard nextOffset > offset, !page.paths.isEmpty else {
                throw DailyLogFetchError.invalidResponse
            }
            offset = nextOffset
        }

        throw DailyLogFetchError.indexTruncated
    }

    func fetchDailyFile(relativePath: String) async throws -> String {
        guard DailyLogFilePath.isSafeRelativeMarkdownPath(relativePath) else {
            throw DailyLogFetchError.invalidResponse
        }

        var content = Data()
        var offset = 0
        var expectedTotalBytes: Int?

        while true {
            try Task.checkCancellation()
            let chunk = try await fetchDailyLogFileChunk(path: relativePath, offset: offset)

            if let expectedTotalBytes, expectedTotalBytes != chunk.totalBytes {
                throw DailyLogFetchError.invalidResponse
            }
            expectedTotalBytes = chunk.totalBytes

            guard chunk.totalBytes <= DailyLogTransfer.maximumFileByteCount,
                  chunk.data.count <= DailyLogTransfer.maximumChunkByteCount,
                  content.count + chunk.data.count <= DailyLogTransfer.maximumFileByteCount
            else {
                throw DailyLogFetchError.tooLarge
            }
            content.append(chunk.data)

            guard let nextOffset = chunk.nextOffset else {
                guard content.count == chunk.totalBytes else {
                    throw DailyLogFetchError.invalidResponse
                }
                guard let text = String(data: content, encoding: .utf8) else {
                    throw DailyLogFetchError.invalidUTF8
                }
                return text
            }
            guard nextOffset > offset, nextOffset == content.count else {
                throw DailyLogFetchError.invalidResponse
            }
            offset = nextOffset
        }
    }

    private func fetchDailyLogFileIndexPage(
        offset: Int
    ) async throws -> DailyLogFileIndexPage {
        guard let session = try await activatedSession() else {
            throw DailyLogFetchError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let timeout = ContinuationTimeout()
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(15))
                if await timeout.complete() {
                    continuation.resume(throwing: DailyLogFetchError.transportFailure)
                }
            }

            session.sendMessage([
                "request": "dailyLogFileIndexPage",
                "offset": offset,
                "limit": DailyLogTransfer.defaultPathPageLimit,
            ], replyHandler: { @Sendable reply in
                let error = reply["error"] as? String
                let paths = reply["paths"] as? [String]
                let nextOffset = reply["nextOffset"] as? Int
                let todayPath = reply["todayPath"] as? String
                let isTruncated = reply["isTruncated"] as? Bool
                Task {
                    guard await timeout.complete() else { return }
                    timeoutTask.cancel()
                    if let error {
                        continuation.resume(throwing: self.dailyLogFetchError(from: error))
                        return
                    }
                    guard let paths,
                          let isTruncated,
                          nextOffset.map({ $0 >= 0 }) ?? true,
                          todayPath.map(DailyLogFilePath.isSafeRelativeMarkdownPath) ?? true
                    else {
                        continuation.resume(throwing: DailyLogFetchError.invalidResponse)
                        return
                    }
                    continuation.resume(returning: DailyLogFileIndexPage(
                        paths: paths,
                        nextOffset: nextOffset,
                        todayPath: todayPath,
                        isTruncated: isTruncated
                    ))
                }
            }, errorHandler: { @Sendable _ in
                Task {
                    guard await timeout.complete() else { return }
                    timeoutTask.cancel()
                    continuation.resume(throwing: DailyLogFetchError.transportFailure)
                }
            })
        }
    }

    private func fetchDailyLogFileChunk(
        path: String,
        offset: Int
    ) async throws -> (data: Data, nextOffset: Int?, totalBytes: Int) {
        guard let session = try await activatedSession() else {
            throw DailyLogFetchError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let timeout = ContinuationTimeout()
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(15))
                if await timeout.complete() {
                    continuation.resume(throwing: DailyLogFetchError.transportFailure)
                }
            }

            session.sendMessage([
                "request": "dailyLogFileChunk",
                "path": path,
                "offset": offset,
                "maximumByteCount": DailyLogTransfer.defaultChunkByteCount,
            ], replyHandler: { @Sendable reply in
                let error = reply["error"] as? String
                let data = reply["data"] as? Data
                let nextOffset = reply["nextOffset"] as? Int
                let totalBytes = reply["totalBytes"] as? Int
                Task {
                    guard await timeout.complete() else { return }
                    timeoutTask.cancel()
                    if let error {
                        continuation.resume(throwing: self.dailyLogFetchError(from: error))
                        return
                    }
                    guard let data, let totalBytes else {
                        continuation.resume(throwing: DailyLogFetchError.invalidResponse)
                        return
                    }
                    continuation.resume(returning: (data, nextOffset, totalBytes))
                }
            }, errorHandler: { @Sendable _ in
                Task {
                    guard await timeout.complete() else { return }
                    timeoutTask.cancel()
                    continuation.resume(throwing: DailyLogFetchError.transportFailure)
                }
            })
        }
    }

    nonisolated private func dailyLogFetchError(from replyError: String) -> DailyLogFetchError {
        switch replyError {
        case "unavailable": .unavailable
        case "tooLarge": .tooLarge
        default: .invalidResponse
        }
    }

    private func activatedSession() async throws -> WCSession? {
        guard let session else { return nil }
        for _ in 0..<10 {
            if session.activationState == .activated { return session }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return session.activationState == .activated ? session : nil
    }
#endif

    // MARK: - Message Handler

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
#if os(iOS)
        if let idString = message["queryProcessed"] as? String,
           let id = UUID(uuidString: idString) {
            let processed = UserDefaults.standard
                .stringArray(forKey: UserDefaultsKey.processedNoteIDs.rawValue)?
                .contains(id.uuidString) ?? false
            replyHandler(["processed": processed])
            return
        }

        if let request = message["request"] as? String {
            switch request {
            case "dailyLogFileIndexPage":
                let offset = message["offset"] as? Int ?? -1
                let limit = message["limit"] as? Int ?? DailyLogTransfer.defaultPathPageLimit
                guard let paths = iCloudStorageManager.shared.dailyLogFilePaths() else {
                    replyHandler(["error": "unavailable"])
                    return
                }
                let boundedPaths = DailyLogTransfer.boundedPaths(paths)
                let page = DailyLogTransfer.page(boundedPaths.paths, offset: offset, limit: limit)
                let todayPath = iCloudStorageManager.shared.dailyLogRelativePath()

                var reply: [String: Any] = [
                    "paths": page.paths,
                    "isTruncated": boundedPaths.isTruncated,
                ]
                if let nextOffset = page.nextOffset {
                    reply["nextOffset"] = nextOffset
                }
                if DailyLogFilePath.isSafeRelativeMarkdownPath(todayPath) {
                    reply["todayPath"] = todayPath
                }
                replyHandler(reply)
                return

            case "dailyLogFileChunk":
                guard let path = message["path"] as? String,
                      DailyLogFilePath.isSafeRelativeMarkdownPath(path),
                      let offset = message["offset"] as? Int,
                      let maximumByteCount = message["maximumByteCount"] as? Int,
                      let fileData = iCloudStorageManager.shared.readData(relativePath: path)
                else {
                    replyHandler(["error": "unavailable"])
                    return
                }

                guard fileData.count <= DailyLogTransfer.maximumFileByteCount else {
                    replyHandler(["error": "tooLarge"])
                    return
                }

                let chunk = DailyLogTransfer.chunk(
                    fileData,
                    offset: offset,
                    maximumByteCount: maximumByteCount
                )
                var reply: [String: Any] = [
                    "data": chunk.data,
                    "totalBytes": fileData.count,
                ]
                if let nextOffset = chunk.nextOffset {
                    reply["nextOffset"] = nextOffset
                }
                replyHandler(reply)
                return

            case "dailyFile":
                let timestamp = message["date"] as? TimeInterval ?? Date().timeIntervalSince1970
                let date = Date(timeIntervalSince1970: timestamp)
                // readText is nonisolated, so we read and reply synchronously in this
                // delegate's own isolation region — no need to send the non-Sendable
                // replyHandler across an actor boundary.
                // Route through the same bounded file protocol for consistency.
                let path = iCloudStorageManager.shared.dailyLogRelativePath(for: date)
                guard DailyLogFilePath.isSafeRelativeMarkdownPath(path),
                      let fileData = iCloudStorageManager.shared.readData(relativePath: path),
                      fileData.count <= DailyLogTransfer.maximumFileByteCount
                else {
                    replyHandler(["available": false])
                    return
                }
                guard let content = String(data: fileData, encoding: .utf8) else {
                    replyHandler(["available": false])
                    return
                }
                replyHandler(["content": content, "available": true])
                return

            default:
                break
            }
        }
#endif
    }
}
