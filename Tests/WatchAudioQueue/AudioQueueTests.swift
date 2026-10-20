import Foundation
import Testing
@testable import WatchQueue

@Suite(.serialized)
@MainActor
struct AudioQueueTests {
    @Test func expiredAudioTransferRetriesAfterRelaunchUntilAcknowledged() throws {
        let store = LocalStore.shared
        let transport = WatchConnectivityProvider.shared
        store.debugReset()
        defer { store.debugReset() }
        transport.acceptsTransfer = true
        transport.sent = []
        let id = UUID()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).m4a")
        let bytes = Data("recording".utf8)
        try bytes.write(to: temporary)
        store.enqueueAudio(from: temporary, id: id, timestamp: Date())
        #expect(transport.sent == [id])

        // Transport accepted the file, but the phone never durably processed it.
        store.debugMarkAudioQueued(id, at: Date(timeIntervalSinceNow: -25 * 60 * 60))
        store.debugReloadFromDisk()
        store.syncPendingAudio()
        #expect(transport.sent == [id, id])
        #expect(store.pendingAudio.map(\.id) == [id])
        #expect(try Data(contentsOf: store.debugAudioURL(for: id)) == bytes)

        // A fresh transfer must not be enqueued again on every foreground sync.
        store.syncPendingAudio()
        #expect(transport.sent == [id, id])
        store.removeAudio(withId: id)
        #expect(store.pendingAudio.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.debugAudioURL(for: id).path))
    }

    @Test func unavailableTransportKeepsExpiredAudioRetryable() throws {
        let store = LocalStore.shared
        let transport = WatchConnectivityProvider.shared
        store.debugReset()
        defer {
            store.debugReset()
            transport.acceptsTransfer = true
        }
        transport.acceptsTransfer = true
        transport.sent = []
        let id = UUID()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).m4a")
        try Data("recording".utf8).write(to: temporary)
        store.enqueueAudio(from: temporary, id: id, timestamp: Date())
        store.debugMarkAudioQueued(id, at: Date(timeIntervalSinceNow: -25 * 60 * 60))
        transport.acceptsTransfer = false
        store.syncPendingAudio()
        #expect(store.debugQueuedAudioDate(for: id) == nil)
        #expect(store.pendingAudio.map(\.id) == [id])
        store.debugReloadFromDisk()
        transport.acceptsTransfer = true
        store.syncPendingAudio()
        #expect(transport.sent == [id, id])
    }
}
