import SwiftUI
import SwiftData
import MacroMarkKit

struct FutureNoteComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let selectedDate: Date
    let mode: ComposerMode

    @State private var draftText = ""
    @State private var statusMessage: String?
    @State private var isSaving = false
    @State private var didSave = false

    private var trimmedText: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draftText)
                        .frame(minHeight: 180)
                        .disabled(isSaving || didSave)
                } header: {
                    Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSave ? "Done" : "Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(trimmedText.isEmpty || isSaving || didSave)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        let text = trimmedText
        guard !text.isEmpty else { return }

        isSaving = true
        statusMessage = nil

        let timestamp = DaySelection.timestamp(onSelectedDay: selectedDate)
        let noteID = UUID()
        let note = ProcessedNote(text: text, sourceID: noteID, createdAt: timestamp)
        modelContext.insert(note)

        do {
            try modelContext.save()
        } catch {
            statusMessage = "The note could not be saved."
            isSaving = false
            return
        }

        let result = await iCloudStorageManager.shared.appendText(text, for: timestamp)
        switch result {
        case .appended:
            note.isExported = true
            note.exportTarget = ExportTarget.iCloud.rawValue
            note.exportStatus = .exported
            note.exportStatusMessage = "Saved to \(ExportTarget.iCloud.rawValue)."
            note.lastExportAttemptAt = .now
            note.lastExportedAt = .now
            try? modelContext.save()
            dismiss()
        case .deferred:
            note.exportStatus = .deferred
            note.exportStatusMessage = "Waiting for iCloud to materialize the daily file."
            note.lastExportAttemptAt = .now
            let queued = queuePendingICloudExport(noteID: noteID, text: text, timestamp: timestamp)
            if !queued {
                note.exportStatus = .failed
                note.exportStatusMessage = "The future note export could not be queued for retry."
            }
            try? modelContext.save()
            didSave = true
            statusMessage = queued
                ? "Saved to the inbox. iCloud will retry before this appears in the daily file."
                : "Saved to the inbox, but the daily file export could not be queued for retry."
        case .failed:
            note.exportStatus = .failed
            note.exportStatusMessage = "The future note export is queued for retry."
            note.lastExportAttemptAt = .now
            let queued = queuePendingICloudExport(noteID: noteID, text: text, timestamp: timestamp)
            if !queued {
                note.exportStatusMessage = "The future note export could not be queued for retry."
            }
            try? modelContext.save()
            didSave = true
            statusMessage = queued
                ? "Saved to the inbox. The daily file export is queued for retry."
                : "Saved to the inbox, but the daily file export could not be queued for retry."
        }

        isSaving = false
    }

    private func queuePendingICloudExport(noteID: UUID, text: String, timestamp: Date) -> Bool {
        do {
            try PendingExportStore.upsert(
                PendingExportRecord(
                    noteId: noteID,
                    processedText: text,
                    timestamp: timestamp,
                    target: .iCloud,
                    isAudio: false,
                    requiresWatchAcknowledgement: false
                )
            )
            return true
        } catch {
            return false
        }
    }
}

#Preview {
    FutureNoteComposerView(selectedDate: Date(), mode: .future)
        .modelContainer(for: ProcessedNote.self, inMemory: true)
}
