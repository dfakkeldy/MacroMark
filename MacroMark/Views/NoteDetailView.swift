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
        queuedExportID != nil
    }

    private var queuedExportID: UUID? {
        let pending = PendingExportStore.read()
        if let sourceID = note.sourceID, pending[sourceID] != nil {
            return sourceID
        }

        return pending.first { $0.value.timestamp == note.createdAt }?.key
    }

    private func requestQueuedRetry() {
        do {
            try enqueuePendingICloudExport()
            note.exportStatusMessage = "Retry requested. MacroMark will use the queued export path."
            note.lastExportAttemptAt = .now
            try note.modelContext?.save()
            NotificationCenter.default.post(name: .retryDeferredExports, object: nil)
        } catch {
            note.exportStatus = .failed
            note.exportStatusMessage = "The export retry could not be queued."
            note.lastExportAttemptAt = .now
            try? note.modelContext?.save()
        }
    }
    
    private func exportTo(target: ExportTarget) {
        guard let url = ExportManager.url(for: note, to: target) else { return }
        Task {
            let success = await UIApplication.shared.open(url)
            note.isExported = false
            note.exportTarget = target.rawValue
            note.exportStatus = success ? .noTarget : .failed
            note.exportStatusMessage = success
                ? "Opened \(target.rawValue). Confirm the note in the destination app."
                : "Could not open \(target.rawValue). The note is still saved in the inbox."
            note.lastExportAttemptAt = .now
            try? note.modelContext?.save()
        }
    }
    
    private func exportToICloud() {
        Task {
            let result = await iCloudStorageManager.shared.appendText(note.text, for: note.createdAt)
            note.lastExportAttemptAt = .now
            if result == .appended {
                note.isExported = true
                note.exportTarget = ExportTarget.iCloud.rawValue
                note.exportStatus = .exported
                note.exportStatusMessage = "Saved to \(ExportTarget.iCloud.rawValue)."
                note.lastExportedAt = .now
                try? note.modelContext?.save()
            } else {
                note.isExported = false
                note.exportTarget = ExportTarget.iCloud.rawValue
                note.exportStatus = result == .deferred ? .deferred : .failed
                note.exportStatusMessage = result == .deferred
                    ? "Waiting for iCloud to materialize the daily file."
                    : "The daily file export failed."
                do {
                    try enqueuePendingICloudExport()
                    try note.modelContext?.save()
                } catch {
                    note.exportStatus = .failed
                    note.exportStatusMessage = "The daily file export could not be queued for retry."
                    try? note.modelContext?.save()
                }
            }
        }
    }

    private func enqueuePendingICloudExport() throws {
        let sourceID = queuedExportID ?? note.sourceID ?? UUID()
        if note.sourceID == nil {
            note.sourceID = sourceID
        }
        try PendingExportStore.upsert(
            PendingExportRecord(
                noteId: sourceID,
                processedText: note.text,
                timestamp: note.createdAt,
                target: .iCloud,
                isAudio: false,
                requiresWatchAcknowledgement: false
            )
        )
    }
}
