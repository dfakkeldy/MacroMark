import Foundation
import WatchKit
import MacroMarkKit

@MainActor
final class DirectSendCoordinator {
    private unowned let store: LocalStore
    private let settings = DirectSendSettingsStore()
    private let github = GitHubRoute()
    private(set) var isForeground = false
    private var retryTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var retryRequested = false
    lazy var webhooks = WebhookBackgroundUploader(store: store)

    init(store: LocalStore) { self.store = store }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        timer?.cancel()
        timer = nil
        if !foreground { retryTask?.cancel() }
        if foreground {
            store.syncPendingNotes()
            store.syncPendingAudio()
            retry()
        } else {
            scheduleBackgroundRefresh()
        }
    }

    func retry() {
        guard retryTask == nil else { retryRequested = true; return }
        retryTask = Task { [weak self] in
            guard let self else { return }
            await drain()
            retryTask = nil
            scheduleTimer()
            scheduleBackgroundRefresh()
            if retryRequested {
                retryRequested = false
                retry()
            }
        }
    }

    /// Refreshes enqueue file-backed webhooks. GitHub is attempted only while awake.
    func refreshInBackground() async {
        store.syncPendingNotes()
        store.syncPendingAudio()
        retry()
        await retryTask?.value
    }

    func expireBackgroundRefresh() {
        if !isForeground { retryTask?.cancel() }
    }

    private func drain() async {
        if let queue = store.textQueue {
            let receipts = queue.flushConfirmations()
            for receipt in receipts where receipt.destination == .webhook { webhooks.removeBody(for: receipt.noteID) }
            if !receipts.isEmpty {
                store.updatePendingCount()
                if !queue.hasUnpersistedConfirmations { store.deliveryError = nil }
            }
        }
        await webhooks.reconcile()
        for snapshot in store.pendingNotes {
            if Task.isCancelled { return }
            guard case let .direct(configurationID, _) = snapshot.route else { continue }
            let eligible = snapshot.eligibleDestinations(at: Date()).filter {
                store.textQueue?.isConfirmed(snapshot.id, destination: $0) != true
            }
            guard !eligible.isEmpty else { continue }
            let configuration: DirectSendConfiguration
            do {
                guard let saved = try settings.deliveryConfiguration(id: configurationID) else {
                    throw DirectSendError.credentialsUnavailable
                }
                configuration = saved
            } catch {
                for destination in eligible { store.failDirect(snapshot.id, destination: destination, error: error) }
                continue
            }

            if eligible.contains(.webhook), !webhooks.activeIDs.contains(snapshot.id) {
                do {
                    guard let destination = configuration.webhook else { throw DirectSendError.credentialsUnavailable }
                    try webhooks.enqueue(snapshot, destination: destination)
                } catch {
                    store.failDirect(snapshot.id, destination: .webhook, error: error)
                }
            }
            if isForeground, eligible.contains(.github) {
                do {
                    guard let destination = configuration.github else { throw DirectSendError.credentialsUnavailable }
                    try await github.send(snapshot, to: destination)
                    store.completeDirect(snapshot.id, destination: .github)
                } catch is CancellationError {
                    return
                } catch {
                    store.failDirect(snapshot.id, destination: .github, error: error)
                }
            }
        }
    }

    private func scheduleTimer() {
        timer?.cancel()
        guard isForeground else { return }
        let dates = store.pendingNotes.flatMap { note in
            note.pendingDestinations.compactMap { destination -> Date? in
                if store.textQueue?.isConfirmed(note.id, destination: destination) == true {
                    return Date().addingTimeInterval(5)
                }
                if destination == .webhook && webhooks.activeIDs.contains(note.id) { return nil }
                return note.retryDate(for: destination)
            }
        }
        guard let next = dates.min() else { return }
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) }
            catch { return }
            self?.retry()
        }
    }

    func scheduleBackgroundRefresh() {
        guard store.pendingNotes.contains(where: { !$0.pendingDestinations.isEmpty }) else { return }
        let next = store.pendingNotes.compactMap(\.nextAttemptAt).min() ?? Date()
        let preferred = max(Date().addingTimeInterval(15 * 60), next)
        WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: preferred, userInfo: nil) { _ in }
    }
}
