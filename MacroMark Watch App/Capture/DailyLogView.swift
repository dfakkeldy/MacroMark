import SwiftUI

struct DailyLogView: View {
    @State private var logContent: String?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    ProgressView("Fetching from iPhone...")
                        .padding()
                } else if let logContent = logContent {
                    Text(logContent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    Text("No content found.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .navigationTitle("Today's Log")
        .task {
            await loadLog()
        }
    }
    
    private func loadLog() async {
        var content = await WatchConnectivityProvider.shared.fetchDailyFile()
        
        let pending = LocalStore.shared.pendingNotes
        if !pending.isEmpty {
            content += "\n\n**Pending Offline Notes:**\n"
            for note in pending {
                let timeString = note.timestamp.formatted(date: .omitted, time: .shortened)
                content += "\n\n\(timeString)\n\n\(note.text)\n\n"
            }
        }
        
        logContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content
        isLoading = false
    }
}

#Preview {
    DailyLogView()
}
