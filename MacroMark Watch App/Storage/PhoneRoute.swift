import MacroMarkKit
import Foundation

/// WatchConnectivity owns transport; only the phone's durable ACK removes a note.
struct PhoneRoute {
    func send(_ note: CapturedNote) -> Bool {
        guard note.route == .phone else { return false }
        return WatchConnectivityProvider.shared.sendNote(note.id, text: note.text, timestamp: note.timestamp)
    }

    func queryProcessed(id: UUID) {
        WatchConnectivityProvider.shared.queryProcessed(id: id)
    }
}
