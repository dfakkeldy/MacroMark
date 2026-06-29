import SwiftUI
import MacroMarkKit

struct DailyLogView: View {
    @Binding var selectedDate: Date
    @State private var logContent: String?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()

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
        .navigationTitle("Daily Log")
        .task(id: selectedDate) {
            await loadLog()
        }
    }
    
    private func loadLog() async {
        isLoading = true
        var content = await WatchConnectivityProvider.shared.fetchDailyFile(for: selectedDate)
        
        let pending = LocalStore.shared.pendingNotes.filter { note in
            DaySelection.contains(note.timestamp, inSelectedDay: selectedDate)
        }
        if !pending.isEmpty {
            content += "\n\n**Pending Offline Notes:**\n"
            for note in pending {
                let timeString = note.timestamp.formatted(date: .omitted, time: .shortened)
                content += "\n\n\(timeString)\n\n\(note.text)\n\n"
            }
        }

        let pendingAudio = LocalStore.shared.pendingAudio.filter { audio in
            DaySelection.contains(audio.timestamp, inSelectedDay: selectedDate)
        }
        if !pendingAudio.isEmpty {
            content += "\n\n**Pending Offline Recordings:**\n"
            for audio in pendingAudio {
                let timeString = audio.timestamp.formatted(date: .omitted, time: .shortened)
                content += "\n\n\(timeString)\n\nAudio recording waiting to sync.\n\n"
            }
        }
        
        logContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content
        isLoading = false
    }
}

#Preview {
    DailyLogView(selectedDate: .constant(Date()))
}
