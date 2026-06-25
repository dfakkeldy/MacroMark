import SwiftUI
import SwiftData
import MacroMarkKit

struct FutureNoteComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let selectedDate: Date

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
            .navigationTitle("Future Note")
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
        let note = ProcessedNote(text: text, createdAt: timestamp)
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
            PendingExportStore.removeMatching(processedText: text, timestamp: timestamp)
            try? modelContext.save()
            dismiss()
        case .deferred:
            queuePendingExport(text: text, timestamp: timestamp)
            didSave = true
            statusMessage = "Saved to the inbox. iCloud export is queued for automatic retry."
        case .failed:
            queuePendingExport(text: text, timestamp: timestamp)
            didSave = true
            statusMessage = "Saved to the inbox. Daily file export is queued for automatic retry."
        }

        isSaving = false
    }

    private func queuePendingExport(text: String, timestamp: Date) {
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

#Preview {
    FutureNoteComposerView(selectedDate: Date())
        .modelContainer(for: ProcessedNote.self, inMemory: true)
}
