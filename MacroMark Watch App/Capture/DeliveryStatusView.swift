import SwiftUI
import MacroMarkKit

struct DeliveryStatusView: View {
    var body: some View {
        List {
            if let error = LocalStore.shared.captureError ?? LocalStore.shared.deliveryError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if LocalStore.shared.textQueue == nil {
                Text("Saved note queue unavailable")
            } else if LocalStore.shared.pendingCount == 0 {
                Text("All notes delivered")
            } else {
                Text("\(LocalStore.shared.pendingCount) pending")
                ForEach(LocalStore.shared.pendingNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.text).lineLimit(3)
                        Text(note.captureDay).font(.caption2).foregroundStyle(.secondary)
                        Text(routeDescription(note)).font(.caption2)
                    }
                }
                if !LocalStore.shared.pendingAudio.isEmpty {
                    Text("\(LocalStore.shared.pendingAudio.count) audio recordings waiting for phone confirmation")
                        .font(.caption)
                }
                Button("Check deliveries") {
                    LocalStore.shared.syncPendingNotes()
                    LocalStore.shared.syncPendingAudio()
                }
            }
        }
        .navigationTitle("Deliveries")
    }

    private func routeDescription(_ note: CapturedNote) -> String {
        switch note.route {
        case .phone: "Waiting for phone confirmation"
        case .direct:
            "Waiting for " + note.pendingDestinations.sorted { $0.rawValue < $1.rawValue }
                .map { $0 == .github ? "GitHub" : "webhook" }.joined(separator: " and ")
        }
    }
}
