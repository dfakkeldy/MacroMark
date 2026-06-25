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
        let requestedDate = selectedDate
        isLoading = true
        var content = await WatchConnectivityProvider.shared.fetchDailyFile(for: requestedDate)
        guard !Task.isCancelled,
              DaySelection.contains(requestedDate, inSelectedDay: selectedDate) else {
            return
        }
        
        let pending = LocalStore.shared.pendingNotes.filter { note in
            DaySelection.contains(note.timestamp, inSelectedDay: requestedDate)
        }
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
    DailyLogView(selectedDate: .constant(Date()))
}
