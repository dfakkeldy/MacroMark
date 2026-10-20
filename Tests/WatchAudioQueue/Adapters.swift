import Foundation

// Platform adapters only. Queue persistence and retry code come from LocalStore.
struct Logger {
    init(subsystem: String, category: String) {}
    func error(_ message: String) {}
}
struct WidgetCenter {
    static let shared = WidgetCenter()
    func reloadTimelines(ofKind: String) {}
}
struct DirectSendSettingsStore {
    func current() throws -> DirectSendConfiguration? {
        DirectSendConfiguration(mode: .direct,
            webhook: WebhookDestination(url: URL(string: "https://example.com/capture")!))
    }
}
@MainActor final class DirectSendCoordinator {
    init(store: LocalStore) {}
    func retry() {}
}
@MainActor struct PhoneRoute {
    func send(_ note: CapturedNote) -> Bool { false }
    func queryProcessed(id: UUID) {}
}
@MainActor final class WatchConnectivityProvider {
    static let shared = WatchConnectivityProvider()
    var sent: [UUID] = []
    var acceptsTransfer = true
    func queryProcessed(id: UUID) {}
    func sendFile(_ url: URL, id: UUID, timestamp: Date) -> Bool {
        guard acceptsTransfer else { return false }
        sent.append(id)
        return true
    }
}
