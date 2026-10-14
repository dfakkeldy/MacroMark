import SwiftUI
import MacroMarkKit

struct DailyLogFileBrowserView: View {
    @Binding var selectedPath: String?

    @Environment(\.dismiss) private var dismiss
    @State private var filePaths: [String] = []
    @State private var loadError: DailyLogFetchError?
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                ProgressView("Fetching files...")
            } else if let loadError {
                Text(loadError.message)
                    .foregroundStyle(.secondary)
            } else if filePaths.isEmpty {
                Text("No saved daily log files.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filePaths, id: \.self) { path in
                    Button {
                        selectedPath = path
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(filePath: path).lastPathComponent)
                                .lineLimit(1)
                            if path.contains("/") {
                                Text(path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Daily Files")
        .task {
            isLoading = true
            loadError = nil
            defer { isLoading = false }

            do {
                let index = try await WatchConnectivityProvider.shared.fetchDailyLogFileIndex()
                guard !Task.isCancelled else { return }
                filePaths = index.paths
            } catch let error as DailyLogFetchError {
                guard !Task.isCancelled else { return }
                loadError = error
            } catch {
                guard !Task.isCancelled else { return }
                loadError = .transportFailure
            }
        }
    }
}

#Preview {
    NavigationStack {
        DailyLogFileBrowserView(selectedPath: .constant("2026/07/2026-07-12.md"))
    }
}
