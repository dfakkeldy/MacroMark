import SwiftUI
import MacroMarkKit

struct FolderSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UserDefaultsKey.folderSettings.rawValue) private var folderSettingsData: Data?

    @State private var settings: FolderSettings

    init() {
        let current: FolderSettings
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.folderSettings.rawValue),
           let decoded = try? JSONDecoder().decode(FolderSettings.self, from: data) {
            current = decoded
        } else {
            current = FolderSettings()
        }
        _settings = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section {
                Picker("Structure", selection: $settings.structure) {
                    ForEach(FolderSettings.FolderStructure.allCases, id: \.self) { structure in
                        Text(structure.displayName).tag(structure)
                    }
                }
            } header: {
                Text("Folder Structure")
            } footer: {
                Text(structureExample)
            }

            Section {
                TextField("Date Format", text: $settings.dateFormat)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Date Format")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Example: \(currentDateExample)")
                    Text("Use yyyy, MM, dd patterns (e.g., yyyy-MM-dd, MM-dd-yyyy, dd-MM-yyyy)")
                        .font(.caption2)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Files saved after changing this setting will use the new structure. Existing files remain in their current location.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Folder Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSettings()
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }

    private var structureExample: String {
        let today = Date()
        let year = today.formatted(Date.FormatStyle().year())
        let month = today.formatted(Date.FormatStyle().month(.twoDigits))
        let day = today.formatted(Date.FormatStyle().day(.twoDigits))

        switch settings.structure {
        case .flat:
            return "Example: \(formatWithSettings())/\(year)-\(month)-\(day).md"
        case .monthly:
            return "Example: \(formatWithSettings())/\(year)-\(month)/\(day).md"
        case .yearlyMonthly:
            return "Example: \(formatWithSettings())/\(year)/\(month)/\(day).md"
        }
    }

    /// The current date formatted through the selected format string, using the
    /// canonical `FolderSettings.format(date:)` (the same method used for the
    /// actual daily-note filename).
    private var currentDateExample: String {
        settings.format(date: Date())
    }

    /// The `"Notes/"`-prefixed path used by the structure-preview example — also
    /// delegates to the canonical formatter.
    private func formatWithSettings() -> String {
        return "Notes/\(settings.format(date: Date()))"
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            folderSettingsData = data
        }
    }
}

#Preview {
    NavigationStack {
        FolderSettingsView()
    }
}
