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

    /// Pending text notes awaiting transfer. Every mutation site (`addNote`,
    /// `syncPendingNotes`, `removeNote`) calls `save()` explicitly, so there is no
    /// `didSet { save() }` — that re-encoded both arrays on every single write.
    var pendingNotes: [CapturedNote] = []

    /// Audio notes awaiting transfer. Persisted to disk + UserDefaults so they
    /// survive cold launch and are retried until the phone ACKs them.
    private(set) var pendingAudio: [PendingAudio] = []

    /// Track note IDs that have already been queued for transfer.
    /// Prevents duplicate entries on iOS when syncPendingNotes is re-triggered.
    private var queuedNoteIDs: Set<UUID> = []

    /// Track audio IDs already handed to the connectivity provider for transfer.
    private var queuedAudioIDs: Set<UUID> = []

    private let defaultsKey = "MacroMark_PendingNotes"
    private let queuedKey = "MacroMark_QueuedNoteIDs"
    private let pendingAudioKey = "MacroMark_PendingAudio"
    private let queuedAudioKey = "MacroMark_QueuedAudioIDs"

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
        for note in pendingNotes where !queuedNoteIDs.contains(note.id) {
            if WatchConnectivityProvider.shared.sendNote(note.id, text: note.text, timestamp: note.timestamp) {
                queuedNoteIDs.insert(note.id)
            }
        }
        save()
    }

    func removeNote(withId id: UUID) {
        pendingNotes.removeAll { $0.id == id }
        queuedNoteIDs.remove(id)
        save()
    }

    /// Allow a note to be re-sent (e.g. after a failed transfer).
    func markNoteUnqueued(_ id: UUID) {
        queuedNoteIDs.remove(id)
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
            #if DEBUG
            print("Failed to persist audio note \(id) — not enqueued")
            #endif
            return
        }

        pendingAudio.append(PendingAudio(id: id, filename: destURL.lastPathComponent, timestamp: timestamp))
        save()
        syncPendingAudio()
    }

    func syncPendingAudio() {
        for item in pendingAudio where !queuedAudioIDs.contains(item.id) {
            let url = audioDirectory.appendingPathComponent(item.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if WatchConnectivityProvider.shared.sendFile(url, id: item.id, timestamp: item.timestamp) {
                queuedAudioIDs.insert(item.id)
            }
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
        save()
    }

    /// Allow an audio note to be re-sent (e.g. after a failed transfer).
    func markAudioUnqueued(_ id: UUID) {
        queuedAudioIDs.remove(id)
        syncPendingAudio()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(pendingNotes)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            // Persist queuedNoteIDs so we don't re-send on cold launch
            UserDefaults.standard.set(queuedNoteIDs.map { $0.uuidString }, forKey: queuedKey)

            let audioData = try JSONEncoder().encode(pendingAudio)
            UserDefaults.standard.set(audioData, forKey: pendingAudioKey)
            UserDefaults.standard.set(queuedAudioIDs.map { $0.uuidString }, forKey: queuedAudioKey)
        } catch {
            #if DEBUG
            print("Failed to save pending notes: \(error)")
            #endif
        }
    }

    /// Rebuild state from persisted data on cold launch.
    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            do {
                pendingNotes = try JSONDecoder().decode([CapturedNote].self, from: data)
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

        if let audioData = UserDefaults.standard.data(forKey: pendingAudioKey) {
            do {
                pendingAudio = try JSONDecoder().decode([PendingAudio].self, from: audioData)
            } catch {
                #if DEBUG
                print("Failed to load pending audio: \(error)")
                #endif
            }
        }
        if let queuedAudioArray = UserDefaults.standard.stringArray(forKey: queuedAudioKey) {
            queuedAudioIDs = Set(queuedAudioArray.compactMap { UUID(uuidString: $0) })
        }
    }
}
