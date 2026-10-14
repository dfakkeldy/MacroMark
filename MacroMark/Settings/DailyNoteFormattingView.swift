import SwiftUI
import MacroMarkKit

struct DailyNoteFormattingView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UserDefaultsKey.dailyNoteFormatting.rawValue) private var formattingData: Data?

    @State private var formatting: DailyNoteFormatting

    init() {
        let current: DailyNoteFormatting
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.dailyNoteFormatting.rawValue),
           let decoded = try? JSONDecoder().decode(DailyNoteFormatting.self, from: data) {
            current = decoded
        } else {
            current = DailyNoteFormatting()
        }
        _formatting = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section("Timestamp") {
                Picker("Style", selection: $formatting.timestampStyle) {
                    ForEach(DailyNoteFormatting.TimestampStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            Section("Separator") {
                Picker("Between Entries", selection: $formatting.separator) {
                    ForEach(DailyNoteFormatting.Separator.allCases) { separator in
                        Text(separator.displayName).tag(separator)
                    }
                }
            }

            Section("Heading") {
                TextField("Optional Markdown heading", text: $formatting.appendHeading)
                    .autocorrectionDisabled()
            }

            Section("Preview") {
                Text(samplePreview)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Daily Note Formatting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
            }
        }
    }

    private var samplePreview: String {
        DailyNoteFormatter.renderEntry(
            text: "Captured idea",
            timestamp: Date(),
            formatting: formatting
        )
    }

    private func save() {
        if let data = try? JSONEncoder().encode(formatting) {
            formattingData = data
        }
    }
}

#Preview {
    NavigationStack {
        DailyNoteFormattingView()
    }
}
