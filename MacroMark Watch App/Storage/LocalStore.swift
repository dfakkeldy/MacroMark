import Foundation
import Observation
import MacroMarkKit
import WidgetKit
import os

/// Metadata for an audio note awaiting transfer to the phone.
/// The audio bytes live on disk in `audioDirectory`; this only tracks the queue.
struct PendingAudio: Identifiable, Codable {
    var id: UUID = UUID()
    var filename: String
    var timestamp: Date
}

@MainActor
@Observable
final class LocalStore {
    static let shared = LocalStore()

    var pendingNotes: [CapturedNote] { textQueue?.notes ?? [] }
    private(set) var captureError: String?
    var deliveryError: String?
    private(set) var textQueue: TextDeliveryQueue?
    var pendingCount: Int { pendingNotes.count + pendingAudio.count }
    @ObservationIgnored lazy var directDelivery = DirectSendCoordinator(store: self)
    private let phoneRoute = PhoneRoute()
    private let logger = Logger(subsystem: "com.macromark", category: "watch-delivery")

    private var textQueueURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TextDelivery/queue.json")
    }

    /// Audio notes awaiting transfer. Persisted to disk + UserDefaults so they
    /// survive cold launch and are retried until the phone ACKs them.
    private(set) var pendingAudio: [PendingAudio] = []

    /// Track note IDs that have already been queued for transfer.
    /// Prevents duplicate entries on iOS when syncPendingNotes is re-triggered.
    private var queuedNoteIDs: Set<UUID> = []
    private var queuedNoteDates: [UUID: Date] = [:]

    /// Track audio IDs already handed to the connectivity provider for transfer.
    private var queuedAudioIDs: Set<UUID> = []
    private var queuedAudioDates: [UUID: Date] = [:]

    private let defaultsKey = "MacroMark_PendingNotes"
    private let queuedKey = "MacroMark_QueuedNoteIDs"
    private let queuedNoteDatesKey = "MacroMark_QueuedNoteDates"
    private let pendingAudioKey = "MacroMark_PendingAudio"
    private let queuedAudioKey = "MacroMark_QueuedAudioIDs"
    private let queuedAudioDatesKey = "MacroMark_QueuedAudioDates"
    private static let reconciliationInterval: TimeInterval = 24 * 60 * 60
    private var isLoading = false

    /// Durable on-disk location for queued audio (NOT the system temp dir, which
    /// the OS can purge). Audio bytes live here until the phone confirms receipt.
    private let audioDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PendingAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        load()
        loadTextQueue()
        syncPendingNotes()
        syncPendingAudio()
    }

    // MARK: - Text Notes

    @discardableResult
    func addNote(_ text: String, timestamp: Date = Date()) -> Bool {
        guard let note = prepareCapturedNote(text, timestamp: timestamp) else { return false }
        return saveNote(note)
    }

    func prepareCapturedNote(_ text: String, timestamp: Date, timeZone: TimeZone = .current) -> CapturedNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let configuration = try DirectSendSettingsStore().current()
            if configuration == nil, UserDefaults.standard.string(forKey: "directSend.selectedMode") == "direct" {
                throw DirectSendError.credentialsUnavailable
            }
            return CapturedNote(text: trimmed, timestamp: timestamp, timeZone: timeZone, route: configuration?.route ?? .phone)
        } catch {
            captureError = "Your delivery setup could not be read. Keep this text and try again after unlocking the watch."
            return nil
        }
    }

    @discardableResult
    func saveNote(_ note: CapturedNote) -> Bool {
        if textQueue == nil { loadTextQueue() }
        do {
            guard let textQueue else { throw CocoaError(.fileWriteUnknown) }
            try textQueue.enqueue(note)
            captureError = nil
            updatePendingCount()
            syncPendingNotes()
            return true
        } catch {
            captureError = "Your note could not be saved. Keep this text and try again after unlocking the watch."
            logger.error("Text capture persistence or secure setup access failed")
            return false
        }
    }

    func syncPendingNotes() {
        if textQueue == nil { loadTextQueue() }
        let now = Date()
        for note in pendingNotes where note.route == .phone {
            if queuedNoteIDs.contains(note.id) {
                if let queuedDate = queuedNoteDates[note.id],
                   now.timeIntervalSince(queuedDate) > Self.reconciliationInterval {
                    phoneRoute.queryProcessed(id: note.id)
                    queuedNoteDates[note.id] = now
                }
                continue
            }

            if phoneRoute.send(note) {
                queuedNoteIDs.insert(note.id)
                queuedNoteDates[note.id] = now
            }
        }
        save()
        directDelivery.retry()
    }

    func removeNote(withId id: UUID) {
        do {
            try textQueue?.acknowledgePhone(id)
        } catch {
            deliveryError = "Could not save the delivery confirmation. Your note is still queued."
            logger.error("Phone acknowledgment persistence failed")
            return
        }
        queuedNoteIDs.remove(id)
        queuedNoteDates.removeValue(forKey: id)
        save()
        updatePendingCount()
    }

    @discardableResult
    func completeDirect(_ id: UUID, destination: DirectDestination) -> Bool {
        do {
            guard let textQueue else { return false }
            try textQueue.complete(id, destination: destination)
            deliveryError = nil
            updatePendingCount()
            return true
        } catch {
            deliveryError = "Could not save the delivery confirmation. Your note is still queued."
            logger.error("Direct delivery confirmation persistence failed")
            return false
        }
    }

    func failDirect(_ id: UUID, destination: DirectDestination, error: (any Error)? = nil, retryAfter: TimeInterval? = nil) {
        do {
            try textQueue?.recordFailure(id, destination: destination, retryAfter: retryAfter ?? (error as? DirectSendError)?.retryAfter)
        } catch {
            logger.error("Direct retry state persistence failed")
        }
        deliveryError = (error as? DirectSendError)?.errorDescription ?? "Delivery was not confirmed. Your note is still queued."
    }

    func updatePendingCount() {
        UserDefaults(suiteName: DirectSendSharedState.appGroup)?.set(textQueue == nil ? -1 : pendingCount,
            forKey: DirectSendSharedState.pendingCountKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "DirectSendWidget")
    }

    private func loadTextQueue() {
        do {
            textQueue = try TextDeliveryQueue(fileURL: textQueueURL,
                legacyNotesData: UserDefaults.standard.data(forKey: defaultsKey))
            captureError = nil
            // Keep the original legacy data as recovery; the atomic file is authoritative.
        } catch {
            textQueue = nil
            captureError = "The saved note queue could not be opened. Existing notes have been kept on disk."
            logger.error("Text queue could not be loaded; capture disabled")
        }
        updatePendingCount()
    }

    /// Allow a note to be re-sent (e.g. after a failed transfer).
    func markNoteUnqueued(_ id: UUID) {
        queuedNoteIDs.remove(id)
        queuedNoteDates.removeValue(forKey: id)
        save()
    }

    // MARK: - Audio Notes

    /// Move a freshly recorded audio file into durable storage and queue it for
    /// transfer. The file survives app termination and is retried until ACK'd.
    func enqueueAudio(from sourceURL: URL, id: UUID, timestamp: Date) {
        let destURL = audioDirectory.appendingPathComponent("\(id.uuidString).m4a")

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
        } catch {
            // Move can fail across volumes — fall back to copy.
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        }

        // Only enqueue if the audio actually made it to durable storage.
        guard FileManager.default.fileExists(atPath: destURL.path) else {
            pendingAudio.removeAll { $0.id == id }
            queuedAudioIDs.remove(id)
            queuedAudioDates.removeValue(forKey: id)
            save()
            #if DEBUG
            print("Failed to persist audio note \(id) — not enqueued")
            #endif
            return
        }

        pendingAudio.removeAll { $0.id == id }
        queuedAudioIDs.remove(id)
        queuedAudioDates.removeValue(forKey: id)
        pendingAudio.append(PendingAudio(id: id, filename: destURL.lastPathComponent, timestamp: timestamp))
        save()
        updatePendingCount()
        syncPendingAudio()
    }

    func syncPendingAudio() {
        let now = Date()
        var missingAudioIDs: [UUID] = []
        for item in pendingAudio {
            if queuedAudioIDs.contains(item.id) {
                if let queuedDate = queuedAudioDates[item.id],
                   now.timeIntervalSince(queuedDate) > Self.reconciliationInterval {
                    WatchConnectivityProvider.shared.queryProcessed(id: item.id)
                    queuedAudioDates[item.id] = now
                }
                continue
            }

            let url = audioDirectory.appendingPathComponent(item.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                missingAudioIDs.append(item.id)
                continue
            }
            if WatchConnectivityProvider.shared.sendFile(url, id: item.id, timestamp: item.timestamp) {
                queuedAudioIDs.insert(item.id)
                queuedAudioDates[item.id] = now
            }
        }
        for id in missingAudioIDs {
            pendingAudio.removeAll { $0.id == id }
            queuedAudioIDs.remove(id)
            queuedAudioDates.removeValue(forKey: id)
        }
        save()
        updatePendingCount()
    }

    func removeAudio(withId id: UUID) {
        if let item = pendingAudio.first(where: { $0.id == id }) {
            let url = audioDirectory.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: url)
        }
        pendingAudio.removeAll { $0.id == id }
        queuedAudioIDs.remove(id)
        queuedAudioDates.removeValue(forKey: id)
        save()
        updatePendingCount()
    }

    /// Allow an audio note to be re-sent (e.g. after a failed transfer).
    func markAudioUnqueued(_ id: UUID) {
        queuedAudioIDs.remove(id)
        queuedAudioDates.removeValue(forKey: id)
        syncPendingAudio()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let encoder = JSONEncoder()
            // Persist queuedNoteIDs so we don't re-send on cold launch
            UserDefaults.standard.set(queuedNoteIDs.map { $0.uuidString }, forKey: queuedKey)
            let noteDateData = try encoder.encode(Self.stringKeyedDates(queuedNoteDates))
            UserDefaults.standard.set(noteDateData, forKey: queuedNoteDatesKey)

            let audioData = try encoder.encode(pendingAudio)
            UserDefaults.standard.set(audioData, forKey: pendingAudioKey)
            UserDefaults.standard.set(queuedAudioIDs.map { $0.uuidString }, forKey: queuedAudioKey)
            let audioDateData = try encoder.encode(Self.stringKeyedDates(queuedAudioDates))
            UserDefaults.standard.set(audioDateData, forKey: queuedAudioDatesKey)
        } catch {
            #if DEBUG
            print("Failed to save pending notes: \(error)")
            #endif
        }
    }

    /// Rebuild state from persisted data on cold launch.
    private func load() {
        isLoading = true
        defer { isLoading = false }

        let decoder = JSONDecoder()

        // Restore queuedNoteIDs so we don't re-send notes that were already
        // transferred (but not yet ACK'd) before termination.
        if let queuedArray = UserDefaults.standard.stringArray(forKey: queuedKey) {
            queuedNoteIDs = Set(queuedArray.compactMap { UUID(uuidString: $0) })
        }
        queuedNoteDates = Self.decodeQueuedDates(
            from: UserDefaults.standard.data(forKey: queuedNoteDatesKey),
            using: decoder
        ).filter { queuedNoteIDs.contains($0.key) }
        let migrationDate = Date()
        for id in queuedNoteIDs where queuedNoteDates[id] == nil {
            queuedNoteDates[id] = migrationDate
        }

        if let audioData = UserDefaults.standard.data(forKey: pendingAudioKey) {
            do {
                pendingAudio = try decoder.decode([PendingAudio].self, from: audioData)
            } catch {
                #if DEBUG
                print("Failed to load pending audio: \(error)")
                #endif
            }
        }
        if let queuedAudioArray = UserDefaults.standard.stringArray(forKey: queuedAudioKey) {
            queuedAudioIDs = Set(queuedAudioArray.compactMap { UUID(uuidString: $0) })
        }
        queuedAudioDates = Self.decodeQueuedDates(
            from: UserDefaults.standard.data(forKey: queuedAudioDatesKey),
            using: decoder
        ).filter { queuedAudioIDs.contains($0.key) }
        for id in queuedAudioIDs where queuedAudioDates[id] == nil {
            queuedAudioDates[id] = migrationDate
        }
    }

    private static func stringKeyedDates(_ dates: [UUID: Date]) -> [String: Date] {
        dates.reduce(into: [String: Date]()) { result, entry in
            result[entry.key.uuidString] = entry.value
        }
    }

    private static func decodeQueuedDates(from data: Data?, using decoder: JSONDecoder) -> [UUID: Date] {
        guard let data,
              let dateDict = try? decoder.decode([String: Date].self, from: data) else {
            return [:]
        }

        return dateDict.reduce(into: [UUID: Date]()) { result, entry in
            if let id = UUID(uuidString: entry.key) {
                result[id] = entry.value
            }
        }
    }

    #if DEBUG
    func debugEnqueueNote(_ note: CapturedNote) throws {
        try textQueue?.enqueue(note)
    }

    func debugMarkNoteQueued(_ id: UUID, at date: Date) {
        queuedNoteIDs.insert(id)
        queuedNoteDates[id] = date
        save()
    }

    func debugQueuedDate(for id: UUID) -> Date? {
        queuedNoteDates[id]
    }

    func debugMarkAudioQueued(_ id: UUID, at date: Date) {
        queuedAudioIDs.insert(id)
        queuedAudioDates[id] = date
        save()
    }

    func debugQueuedAudioDate(for id: UUID) -> Date? {
        queuedAudioDates[id]
    }

    func debugAudioURL(for id: UUID) -> URL {
        audioDirectory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func debugInsertPendingAudio(id: UUID, filename: String, timestamp: Date) {
        pendingAudio.removeAll { $0.id == id }
        pendingAudio.append(PendingAudio(id: id, filename: filename, timestamp: timestamp))
        save()
    }

    func debugReloadFromDisk() {
        isLoading = true
        textQueue = nil
        pendingAudio = []
        queuedNoteIDs = []
        queuedNoteDates = [:]
        queuedAudioIDs = []
        queuedAudioDates = [:]
        isLoading = false
        load()
        loadTextQueue()
    }

    func debugReset() {
        for item in pendingAudio {
            let url = audioDirectory.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: url)
        }
        try? textQueue?.removeAllForTesting()
        pendingAudio = []
        queuedNoteIDs = []
        queuedNoteDates = [:]
        queuedAudioIDs = []
        queuedAudioDates = [:]
        save()
        updatePendingCount()
    }
    #endif
}
