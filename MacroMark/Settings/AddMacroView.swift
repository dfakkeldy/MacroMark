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
            }
            Section("Replacement (What it outputs)") {
                TextField("e.g., # ", text: $replacement)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section("Preview") {
                Text("Say: \(trigger.isEmpty ? "Trigger" : trigger) example")
                    .foregroundStyle(.secondary)
                Text(replacement + " example")
                    .font(.system(.body, design: .monospaced))
            }
            Section("Notes (Optional)") {
                TextField("e.g., Use this to format headings", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
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
