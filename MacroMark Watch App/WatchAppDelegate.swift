import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let task as WKURLSessionRefreshBackgroundTask:
                if task.sessionIdentifier == WebhookBackgroundUploader.sessionIdentifier {
                    LocalStore.shared.directDelivery.webhooks.handle(task)
                } else {
                    task.setTaskCompletedWithSnapshot(false)
                }
            case let task as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    await LocalStore.shared.directDelivery.refreshInBackground()
                    task.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
