import Foundation
import Observation

struct CapturedNote: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var timestamp: Date
}

@MainActor
@Observable
final class LocalStore {
    static let shared = LocalStore()

    var pendingNotes: [CapturedNote] = [] {
        didSet {
            save()
        }
    }

    /// Track note IDs that have already been queued for transfer.
    /// Prevents duplicate entries on iOS when syncPendingNotes is re-triggered.
    private var queuedNoteIDs: Set<UUID> = []

    private let defaultsKey = "MacroMark_PendingNotes"

    private init() {
        load()
        syncPendingNotes()
    }

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = CapturedNote(text: trimmed, timestamp: Date())
        pendingNotes.append(note)
        syncPendingNotes()
    }

    private func syncPendingNotes() {
        for note in pendingNotes where !queuedNoteIDs.contains(note.id) {
            WatchConnectivityProvider.shared.sendNote(note.id, text: note.text, timestamp: note.timestamp)
            queuedNoteIDs.insert(note.id)
        }
    }

    func removeNote(withId id: UUID) {
        pendingNotes.removeAll { $0.id == id }
        queuedNoteIDs.remove(id)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(pendingNotes)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("Failed to save pending notes: \(error)")
        }
    }

    /// Rebuild the queued set from persisted notes (on cold launch, re-queue all).
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            pendingNotes = try JSONDecoder().decode([CapturedNote].self, from: data)
            // On cold launch, we re-sync everything, so clear the queued set
            queuedNoteIDs.removeAll()
        } catch {
            print("Failed to load pending notes: \(error)")
        }
    }
}
