import SwiftUI
import MacroMarkKit

struct DirectReplyView: View {
    @State private var selectedDate = Date()
    @State private var reply: String?
    @State private var isLoading = false
    @State private var status: String?
    @State private var refreshID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Reply date", selection: $selectedDate, displayedComponents: .date)
                if isLoading { ProgressView("Reading reply…") }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                if let reply, !reply.isEmpty { Text(reply) }
                Button("Refresh") { refreshID = UUID() }.disabled(isLoading)
            }
        }
        .navigationTitle("Replies")
        .task(id: "\(day)-\(refreshID)") { await load() }
    }

    private var day: String {
        selectedDate.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
    }

    private func load() async {
        isLoading = true
        reply = nil
        status = nil
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            guard let configuration = try DirectSendSettingsStore().current(), let destination = configuration.github else {
                status = "Set up a GitHub destination in Direct Send settings on your iPhone to read replies."
                return
            }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DirectReplies", isDirectory: true)
            let cache = directory.appendingPathComponent("\(configuration.id.uuidString)-\(day).md")
            if let data = try? Data(contentsOf: cache), data.count <= GitHubRoute.maximumFileByteCount {
                reply = String(data: data, encoding: .utf8)
                status = "Cached reply. Checking for updates…"
            }
            do {
                let fresh = try await GitHubRoute().reply(for: day, at: destination)
                try Task.checkCancellation()
                reply = fresh
                status = fresh == nil ? "No reply for this date yet." : nil
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data((fresh ?? "").utf8).write(to: cache, options: .atomic)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                status = reply == nil ? "Could not read a reply. Try again when connected."
                    : "Showing the cached reply. Could not check for updates."
            }
        } catch {
            guard !Task.isCancelled else { return }
            status = "Secure settings could not be read. Unlock the watch and try again."
        }
    }
}
