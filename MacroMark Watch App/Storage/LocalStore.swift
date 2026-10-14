import Foundation
import Observation

struct CapturedNote: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var timestamp: Date
}

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

    var pendingNotes: [CapturedNote] = [] {
        didSet {
            if !isLoading {
                save()
            }
        }
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
        syncPendingNotes()
        syncPendingAudio()
    }

    // MARK: - Text Notes

    func addNote(_ text: String, timestamp: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = CapturedNote(text: trimmed, timestamp: timestamp)
        pendingNotes.append(note)
        syncPendingNotes()
    }

    func syncPendingNotes() {
        let now = Date()
        for note in pendingNotes {
            if queuedNoteIDs.contains(note.id) {
                if let queuedDate = queuedNoteDates[note.id],
                   now.timeIntervalSince(queuedDate) > Self.reconciliationInterval {
                    WatchConnectivityProvider.shared.queryProcessed(id: note.id)
                    queuedNoteDates[note.id] = now
                }
                continue
            }

            if WatchConnectivityProvider.shared.sendNote(note.id, text: note.text, timestamp: note.timestamp) {
                queuedNoteIDs.insert(note.id)
                queuedNoteDates[note.id] = now
            }
        }
        save()
    }

    func removeNote(withId id: UUID) {
        pendingNotes.removeAll { $0.id == id }
        queuedNoteIDs.remove(id)
        queuedNoteDates.removeValue(forKey: id)
        save()
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
            let data = try encoder.encode(pendingNotes)
            UserDefaults.standard.set(data, forKey: defaultsKey)
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

        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            do {
                pendingNotes = try decoder.decode([CapturedNote].self, from: data)
            } catch {
                #if DEBUG
                print("Failed to load pending notes: \(error)")
                #endif
            }
        }
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
        pendingNotes = []
        pendingAudio = []
        queuedNoteIDs = []
        queuedNoteDates = [:]
        queuedAudioIDs = []
        queuedAudioDates = [:]
        isLoading = false
        load()
    }

    func debugReset() {
        for item in pendingAudio {
            let url = audioDirectory.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: url)
        }
        pendingNotes = []
        pendingAudio = []
        queuedNoteIDs = []
        queuedNoteDates = [:]
        queuedAudioIDs = []
        queuedAudioDates = [:]
        save()
    }
    #endif
}
