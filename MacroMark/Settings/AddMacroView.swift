import SwiftUI
import SwiftData
import MacroMarkKit

struct AddMacroView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var trigger: String = ""
    @State private var replacement: String = ""
    @State private var notes: String = ""

    var body: some View {
        Form {
            Section("Trigger (What you say)") {
                TextField("e.g., Heading One", text: $trigger)
                    .accessibilityIdentifier("newMacro.trigger")
            }
            Section("Replacement (What it outputs)") {
                TextField("e.g., # ", text: $replacement)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("newMacro.replacement")
            }
            Section("Notes (Optional)") {
                TextField("e.g., Use this to format headings", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("newMacro.notes")
            }
        }
        .accessibilityIdentifier("newMacro.form")
        .navigationTitle("New Macro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let newMacro = Macro(trigger: trigger, replacement: replacement, notes: notes)
                    modelContext.insert(newMacro)
                    MacroProcessor.invalidateRegexCache()
                    dismiss()
                }
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || replacement.isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddMacroView()
    }
    .modelContainer(for: Macro.self, inMemory: true)
}
