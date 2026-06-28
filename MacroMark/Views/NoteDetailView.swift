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
                    .accessibilityIdentifier("noteDetail.text")
            } header: {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Status") {
                Label(note.exportStatus.displayName, systemImage: note.exportStatus.systemImage)
                if !note.exportStatusMessage.isEmpty {
                    Text(note.exportStatusMessage)
                        .foregroundStyle(.secondary)
                }
                if note.exportStatus.needsAttention {
                    Button("Retry Export", systemImage: "arrow.clockwise") {
                        retryExportToICloud()
                    }
                }
            }
            
            Section("Export") {
                ForEach(ExportTarget.allCases) { target in
                    if target == .shareSheet {
                        ShareLink(item: note.text) {
                            Label(target.rawValue, systemImage: target.iconName)
                        }
                    } else if target == .iCloud {
                        Button {
                            retryExportToICloud()
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
        .accessibilityIdentifier("noteDetail.form")
        .navigationTitle("Note Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func retryExportToICloud() {
        if hasQueuedExport {
            requestQueuedRetry()
        } else {
            exportToICloud()
        }
    }

    private var hasQueuedExport: Bool {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.pendingExports.rawValue),
              let pending = try? JSONDecoder().decode([String: QueuedExportProbe].self, from: data)
        else { return false }

        return pending.values.contains { $0.timestamp == note.createdAt }
    }

    private func requestQueuedRetry() {
        note.exportStatusMessage = "Retry requested. MacroMark will use the queued export path."
        note.lastExportAttemptAt = .now
        try? note.modelContext?.save()
        NotificationCenter.default.post(name: .retryDeferredExports, object: nil)
    }
    
    private func exportTo(target: ExportTarget) {
        guard let url = ExportManager.url(for: note, to: target) else { return }
        Task {
            let success = await UIApplication.shared.open(url)
            if success {
                let exportDate = Date.now
                note.isExported = true
                note.exportTarget = target.rawValue
                note.exportStatus = .exported
                note.exportStatusMessage = "Saved to \(target.rawValue)."
                note.lastExportAttemptAt = exportDate
                note.lastExportedAt = exportDate
                try? note.modelContext?.save()
            }
        }
    }
    
    private func exportToICloud() {
        Task {
            let result = await iCloudStorageManager.shared.appendText(note.text, for: note.createdAt)
            if result == .appended {
                note.isExported = true
                note.exportTarget = ExportTarget.iCloud.rawValue
                note.exportStatus = .exported
                note.exportStatusMessage = "Saved to \(ExportTarget.iCloud.rawValue)."
                note.lastExportAttemptAt = .now
                note.lastExportedAt = .now
                try? note.modelContext?.save()
            } else {
                note.exportStatus = result == .deferred ? .deferred : .failed
                note.exportStatusMessage = result == .deferred
                    ? "Waiting for iCloud to materialize the daily file."
                    : "The daily file export failed."
                note.lastExportAttemptAt = .now
                try? note.modelContext?.save()
            }
        }
    }

    private struct QueuedExportProbe: Decodable {
        let timestamp: Date
    }
}
