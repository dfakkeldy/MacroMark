import SwiftUI
import MacroMarkKit

struct DailyLogView: View {
    @State private var todayPath: String?
    @State private var selectedPath: String?
    @State private var logContent: String?
    @State private var isLoading = true
    @State private var didLoadInitialFile = false
    @State private var loadedPath: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    DailyLogFileBrowserView(selectedPath: $selectedPath)
                } label: {
                    Label(displayName, systemImage: "doc.text")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Browse saved daily log files.")

                DailyLogBody(isLoading: isLoading, logContent: logContent)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Daily Log")
        .task {
            await loadInitialFile()
        }
        .onChange(of: selectedPath) { _, newPath in
            guard didLoadInitialFile, newPath != loadedPath else { return }
            Task {
                await loadSelectedFile()
            }
        }
    }

    private var displayName: String {
        selectedPath.map { URL(filePath: $0).lastPathComponent } ?? "Today’s Daily Log"
    }

    private func loadInitialFile() async {
        guard !didLoadInitialFile else { return }

        let index = await WatchConnectivityProvider.shared.fetchDailyLogFileIndex()
        guard !Task.isCancelled else { return }

        let availableTodayPath = index.todayPath.flatMap { path in
            index.paths.contains(path) ? path : nil
        }
        todayPath = availableTodayPath

        // A user can enter the browser while the initial index request is in flight.
        // Preserve a file they selected instead of overwriting it with today's path.
        let initialPath = selectedPath ?? availableTodayPath
        selectedPath = initialPath

        if let path = initialPath {
            await loadFile(at: path, includesPendingContent: path == availableTodayPath)
        } else {
            await loadTodayFallback()
        }

        didLoadInitialFile = true

        // A browser selection can arrive while the initial file request is in flight.
        // Reconcile it after that request completes so the chosen file always loads.
        if selectedPath != initialPath {
            await loadSelectedFile()
        }
    }

    private func loadSelectedFile() async {
        guard let selectedPath else {
            await loadTodayFallback()
            return
        }

        await loadFile(at: selectedPath, includesPendingContent: selectedPath == todayPath)
    }

    private func loadFile(at path: String, includesPendingContent: Bool) async {
        loadedPath = path
        isLoading = true
        defer {
            if selectedPath == path {
                isLoading = false
            }
        }

        var content = await WatchConnectivityProvider.shared.fetchDailyFile(relativePath: path)
        guard !Task.isCancelled, selectedPath == path else { return }

        if includesPendingContent {
            content += pendingContent()
        }

        logContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content
    }

    private func loadTodayFallback() async {
        loadedPath = nil
        isLoading = true
        defer {
            if selectedPath == nil {
                isLoading = false
            }
        }

        var content = await WatchConnectivityProvider.shared.fetchDailyFile()
        guard !Task.isCancelled, selectedPath == nil else { return }

        content += pendingContent()
        logContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content
    }

    private func pendingContent() -> String {
        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        let pendingNotes = LocalStore.shared.pendingNotes.filter { note in
            DaySelection.contains(note.timestamp, inSelectedDay: today)
        }
        let pendingAudio = LocalStore.shared.pendingAudio.filter { audio in
            DaySelection.contains(audio.timestamp, inSelectedDay: today)
        }

        var content = ""
        if !pendingNotes.isEmpty {
            content += "\n\n**Pending Offline Notes:**\n"
            for note in pendingNotes {
                let time = note.timestamp.formatted(date: .omitted, time: .shortened)
                content += "\n\n\(time)\n\n\(note.text)\n\n"
            }
        }

        if !pendingAudio.isEmpty {
            content += "\n\n**Pending Offline Recordings:**\n"
            for audio in pendingAudio {
                let time = audio.timestamp.formatted(date: .omitted, time: .shortened)
                content += "\n\n\(time)\n\nAudio recording waiting to sync.\n\n"
            }
        }
        return content
    }
}

private struct DailyLogBody: View {
    let isLoading: Bool
    let logContent: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Fetching from iPhone...")
                    .padding()
            } else if let logContent {
                Text(logContent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text("No content found.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    DailyLogView()
}
