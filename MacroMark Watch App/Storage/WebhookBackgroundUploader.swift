import Foundation
import WatchKit
import MacroMarkKit

@MainActor
final class WebhookBackgroundUploader: NSObject, URLSessionTaskDelegate {
    static let sessionIdentifier = "com.danfakkeldy.macromark.direct-send.webhook"
    private unowned let store: LocalStore
    private(set) var activeIDs: Set<UUID> = []
    private var backgroundTasks: [WKURLSessionRefreshBackgroundTask] = []
    private var eventsFinished = false
    private let directory: URL

    // A main operation queue makes delegate completion persistence synchronous and
    // ordered before didFinishEvents. MainActor.assumeIsolated below uses this guarantee.
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 15 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    init(store: LocalStore) {
        self.store = store
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebhookUploads", isDirectory: true)
        super.init()
    }

    func reconcile() async {
        let tasks = await session.allTasks
        activeIDs = Set(tasks.compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
        // If the process died after creating a task but before resume(), continue it.
        for task in tasks where task.state == .suspended { task.resume() }
    }

    func enqueue(_ note: CapturedNote, destination: WebhookDestination) throws {
        guard !activeIDs.contains(note.id) else { return }
        let upload = try WebhookRoute.upload(note, to: destination)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bodyURL = directory.appendingPathComponent("\(note.id.uuidString).json")
        try upload.body.write(to: bodyURL, options: .atomic)
        let task = session.uploadTask(with: upload.request, fromFile: bodyURL)
        task.taskDescription = note.id.uuidString
        activeIDs.insert(note.id)
        eventsFinished = false
        task.resume()
    }

    func handle(_ task: WKURLSessionRefreshBackgroundTask) {
        _ = session
        if eventsFinished {
            task.setTaskCompletedWithSnapshot(false)
        } else {
            backgroundTasks.append(task)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let id = task.taskDescription.flatMap(UUID.init(uuidString:))
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let retryAfter = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        MainActor.assumeIsolated {
            guard let id else { return }
            activeIDs.remove(id)
            if error == nil, let status, (200..<300).contains(status) {
                if store.completeDirect(id, destination: .webhook) {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id.uuidString).json"))
                }
            } else {
                let failure = status.map { DirectSendError.http($0, retryAfter: retryAfter) }
                store.failDirect(id, destination: .webhook, error: failure, retryAfter: retryAfter)
            }
            store.directDelivery.retry()
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            eventsFinished = true
            for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
            backgroundTasks.removeAll()
        }
    }
}
