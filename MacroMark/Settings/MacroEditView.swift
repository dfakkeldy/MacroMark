import SwiftUI
import SwiftData
import MacroMarkKit

struct MacroEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                    macro.trigger = editedTrigger
                    macro.replacement = editedReplacement
                    macro.notes = editedNotes
                    if macro.isDefault {
                        macro.isDefaultEdited = true
                    }
                    dismiss()
                }
                .disabled(editedTrigger.trimmingCharacters(in: .whitespaces).isEmpty || editedReplacement.isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MacroEditView(macro: Macro(trigger: "Heading One", replacement: "# ", isDefault: true))
    }
}
