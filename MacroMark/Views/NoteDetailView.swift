import SwiftUI
import SwiftData
import MacroMarkKit

struct NoteDetailView: View {
    @Bindable var note: ProcessedNote
    
    var body: some View {
        Form {
            if note.transcriptionPartial {
                Section {
                    Label("Some parts of this dictation may be missing. The audio was partially transcribed.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            Section {
                TextEditor(text: $note.text)
                    .frame(minHeight: 200)
                    .font(.body)
            } header: {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            
            Section("Export") {
                ForEach(ExportTarget.allCases) { target in
                    if target == .shareSheet {
                        ShareLink(item: note.text) {
                            Label(target.rawValue, systemImage: target.iconName)
                        }
                    } else if target == .iCloud {
                        Button {
                            exportToICloud()
                        } label: {
                            Label(target.rawValue, systemImage: target.iconName)
                        }
                    } else {
                        Button {
                            exportTo(target: target)
                        } label: {
                            Label(target.rawValue, systemImage: target.iconName)
                        }
                    }
                }
            }
        }
        .navigationTitle("Note Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func exportTo(target: ExportTarget) {
        guard let url = ExportManager.url(for: note, to: target) else { return }
        Task {
            let success = await UIApplication.shared.open(url)
            if success {
                note.isExported = true
                note.exportTarget = target.rawValue
                try? note.modelContext?.save()
            }
        }
    }
    
    private func exportToICloud() {
        Task { @MainActor in
            let text = note.text
            let timestamp = note.createdAt
            let result = await iCloudStorageManager.shared.appendText(text, for: timestamp)
            switch result {
            case .appended:
                note.isExported = true
                note.exportTarget = ExportTarget.iCloud.rawValue
                PendingExportStore.removeMatching(processedText: text, timestamp: timestamp)
                try? note.modelContext?.save()
            case .deferred, .failed:
                let entry = PendingExportStore.firstEntry(processedText: text, timestamp: timestamp)
                    ?? PendingExportEntry(
                        processedText: text,
                        timestamp: timestamp,
                        isAudio: false,
                        requiresWatchAcknowledgement: false
                    )
                PendingExportStore.upsert(entry)
            }
        }
    }
}
