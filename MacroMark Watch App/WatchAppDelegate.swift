import WatchKit
import os

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let task as WKWatchConnectivityRefreshBackgroundTask:
                WatchConnectivityProvider.shared.handleConnectivityRefresh(task)
            case let task as WKURLSessionRefreshBackgroundTask:
                if task.sessionIdentifier == WebhookBackgroundUploader.sessionIdentifier {
                    LocalStore.shared.directDelivery.webhooks.handle(task)
                } else {
                    task.setTaskCompletedWithSnapshot(false)
                }
            case let task as WKApplicationRefreshBackgroundTask:
                let completed = OSAllocatedUnfairLock(initialState: false)
                task.expirationHandler = {
                    Task { @MainActor in
                        LocalStore.shared.directDelivery.expireBackgroundRefresh()
                        guard completed.withLock({ state in
                            if state { return false }; state = true; return true
                        }) else { return }
                        task.expirationHandler = nil
                        task.setTaskCompletedWithSnapshot(false)
                    }
                }
                Task { @MainActor in
                    await LocalStore.shared.directDelivery.refreshInBackground()
                    guard completed.withLock({ state in
                        if state { return false }; state = true; return true
                    }) else { return }
                    task.expirationHandler = nil
                    task.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
