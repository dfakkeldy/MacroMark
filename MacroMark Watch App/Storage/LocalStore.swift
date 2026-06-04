import Foundation
import Observation

struct CapturedNote: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var timestamp: Date
    var latitude: Double?
    var longitude: Double?
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
    
    private let defaultsKey = "MacroMark_PendingNotes"
    
    private init() {
        load()
        syncPendingNotes()
        NotificationCenter.default.addObserver(forName: .noteTransferDidComplete, object: nil, queue: .main) { [weak self] notification in
            guard let self, let id = notification.userInfo?["id"] as? UUID else { return }
            MainActor.assumeIsolated {
                self.removeNote(withId: id)
            }
        }
    }
    
    func addNote(_ text: String, latitude: Double? = nil, longitude: Double? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let note = CapturedNote(text: trimmed, timestamp: Date(), latitude: latitude, longitude: longitude)
        pendingNotes.append(note)
        syncPendingNotes()
    }
    
    private func syncPendingNotes() {
        for note in pendingNotes {
            WatchConnectivityProvider.shared.sendNote(note.id, text: note.text, timestamp: note.timestamp, latitude: note.latitude, longitude: note.longitude)
        }
    }
    
    func removeNote(withId id: UUID) {
        pendingNotes.removeAll { $0.id == id }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(pendingNotes)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("Failed to save pending notes: \(error)")
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            pendingNotes = try JSONDecoder().decode([CapturedNote].self, from: data)
        } catch {
            print("Failed to load pending notes: \(error)")
        }
    }
}
