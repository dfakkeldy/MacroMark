import SwiftUI
import SwiftData
import MacroMarkKit

struct MacroEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Macro.sortOrder, order: .forward) private var macros: [Macro]

    @Bindable var macro: Macro

    @State private var editedTrigger: String
    @State private var editedReplacement: String
    @State private var editedNotes: String

    init(macro: Macro) {
        self.macro = macro
        _editedTrigger = State(initialValue: macro.trigger)
        _editedReplacement = State(initialValue: macro.replacement)
        _editedNotes = State(initialValue: macro.notes)
    }

    private var cleanedTrigger: String {
        MacroTriggerValidator.cleanedTrigger(editedTrigger)
    }

    private var canSave: Bool {
        !cleanedTrigger.isEmpty
            && !editedReplacement.isEmpty
            && !MacroTriggerValidator.hasDuplicate(cleanedTrigger, in: macros, excluding: macro)
    }

    var body: some View {
        Form {
            Section {
                TextField("Trigger", text: $editedTrigger)
            } header: {
                Text("Trigger Word")
            } footer: {
                Text("The word or phrase you speak to activate this macro.")
            }

            Section {
                TextField("Replacement", text: $editedReplacement, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .lineLimit(3...10)
            } header: {
                Text("Replacement Text")
            } footer: {
                Text("What the macro outputs. Use {date}, {time}, {newline}, {tab}, {backspace}, {clipboard}, {location}, and {uuid} for dynamic content.")
            }

            Section("Preview") {
                Text("Say: \(cleanedTrigger.isEmpty ? "Trigger" : cleanedTrigger) example")
                    .foregroundStyle(.secondary)
                Text(editedReplacement + " example")
                    .font(.system(.body, design: .monospaced))
            }

            Section {
                TextField("Notes", text: $editedNotes, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Notes (Optional)")
            } footer: {
                Text("Add personal notes or documentation about what this macro does.")
            }

            if macro.isDefault {
                Section {
                    Label("This is a default macro. Your changes will be marked as customized.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Edit Macro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(!canSave)
            }
        }
    }

    private func saveChanges() {
        let originalTrigger = macro.trigger
        let originalReplacement = macro.replacement
        let originalNotes = macro.notes
        let originalIsDefaultEdited = macro.isDefaultEdited

        macro.trigger = cleanedTrigger
        macro.replacement = editedReplacement
        macro.notes = editedNotes
        if macro.isDefault {
            macro.isDefaultEdited = true
        }

        do {
            try modelContext.save()
            // The regex cache is keyed by trigger pattern; an edit may have
            // changed it, so drop stale compiled regexes.
            MacroProcessor.invalidateRegexCache()
            dismiss()
        } catch {
            macro.trigger = originalTrigger
            macro.replacement = originalReplacement
            macro.notes = originalNotes
            macro.isDefaultEdited = originalIsDefaultEdited
#if DEBUG
            print("MacroMark: failed to save macro edits: \(error)")
#endif
        }
    }
}

#Preview {
    NavigationStack {
        MacroEditView(macro: Macro(trigger: "Heading One", replacement: "# ", isDefault: true))
    }
}
