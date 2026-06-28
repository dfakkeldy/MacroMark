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
            note.exportStatus = .exported
            note.exportStatusMessage = "Saved to \(ExportTarget.iCloud.rawValue)."
            note.lastExportAttemptAt = .now
            note.lastExportedAt = .now
            try? modelContext.save()
            dismiss()
        case .deferred:
            note.exportStatus = .deferred
            note.exportStatusMessage = "Waiting for iCloud or the selected destination to become available."
            note.lastExportAttemptAt = .now
            try? modelContext.save()
            didSave = true
            statusMessage = "Saved to the inbox. iCloud will need another attempt before this appears in the daily file."
        case .failed:
            note.exportStatus = .failed
            note.exportStatusMessage = "The export failed. The original capture is still queued for retry."
            note.lastExportAttemptAt = .now
            try? modelContext.save()
            didSave = true
            statusMessage = "Saved to the inbox, but the daily file export failed."
        }

        isSaving = false
    }
}

#Preview {
    FutureNoteComposerView(selectedDate: Date())
        .modelContainer(for: ProcessedNote.self, inMemory: true)
}
