import SwiftUI
import MacroMarkKit

struct DestinationProofView: View {
    @AppStorage(UserDefaultsKey.defaultExportTarget.rawValue) private var defaultExportTarget: ExportTarget = .iCloud
    @AppStorage(UserDefaultsKey.lastSuccessfulExportPath.rawValue) private var lastPath: String = ""
    @AppStorage(UserDefaultsKey.lastSuccessfulExportAt.rawValue) private var lastExportTimestamp: Double = 0

    @State private var resultMessage: String?
    @State private var isWriting = false

    var body: some View {
        Form {
            Section("Active Destination") {
                Label(defaultExportTarget.rawValue, systemImage: defaultExportTarget.iconName)
            }

            Section("Last Successful Write") {
                if !lastPath.isEmpty {
                    Text(lastPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if lastExportTimestamp > 0 {
                    Text(lastExportDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No successful iCloud write has been recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Write Test Note", systemImage: "square.and.pencil") {
                    Task { await writeTestNote() }
                }
                .disabled(isWriting || defaultExportTarget != .iCloud)

                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if defaultExportTarget != .iCloud {
                    Text("Test writes are available for iCloud Drive daily notes. Other destinations are confirmed from each note's export status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Destination")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lastExportDate: Date {
        Date(timeIntervalSince1970: lastExportTimestamp)
    }

    @MainActor
    private func writeTestNote() async {
        guard !isWriting else { return }
        guard defaultExportTarget == .iCloud else {
            resultMessage = "Switch the default destination to iCloud Drive before writing a test note."
            return
        }

        isWriting = true
        defer { isWriting = false }

        let result = await iCloudStorageManager.shared.appendText("MacroMark test note")
        switch result {
        case .appended:
            if iCloudStorageManager.shared.isUsingFallbackStorage {
                resultMessage = "Test note was written to local fallback storage. iCloud Drive setup is not confirmed yet."
            } else {
                resultMessage = "Test note written."
            }
        case .deferred:
            resultMessage = "iCloud is not ready yet. The test note was not written; try again after the daily file finishes downloading."
        case .failed:
            resultMessage = "Test note could not be written. Check iCloud Drive and folder permissions."
        }
    }
}

#Preview {
    NavigationStack {
        DestinationProofView()
    }
}
