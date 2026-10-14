import SwiftUI
import SwiftData
import MacroMarkKit

struct AddMacroView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Macro.sortOrder, order: .forward) private var macros: [Macro]

    @State private var trigger: String = ""
    @State private var replacement: String = ""
    @State private var notes: String = ""

    private var cleanedTrigger: String {
        MacroTriggerValidator.cleanedTrigger(trigger)
    }

    private var canSave: Bool {
        !cleanedTrigger.isEmpty
            && !replacement.isEmpty
            && !MacroTriggerValidator.hasDuplicate(cleanedTrigger, in: macros)
    }

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
            Section("Preview") {
                Text("Say: \(cleanedTrigger.isEmpty ? "Trigger" : cleanedTrigger) example")
                    .foregroundStyle(.secondary)
                Text(replacement + " example")
                    .font(.system(.body, design: .monospaced))
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
                    saveMacro()
                }
                .disabled(!canSave)
            }
        }
    }

    private func saveMacro() {
        let newMacro = Macro(trigger: cleanedTrigger, replacement: replacement, notes: notes)
        modelContext.insert(newMacro)
        do {
            try modelContext.save()
            MacroProcessor.invalidateRegexCache()
            dismiss()
        } catch {
            modelContext.delete(newMacro)
#if DEBUG
            print("MacroMark: failed to save new macro: \(error)")
#endif
        }
    }
}

#Preview {
    NavigationStack {
        AddMacroView()
    }
    .modelContainer(for: Macro.self, inMemory: true)
}
