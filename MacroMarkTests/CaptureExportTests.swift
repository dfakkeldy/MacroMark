import Foundation
import SwiftData
import Testing
import MacroMarkKit
@testable import MacroMark

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CaptureExportTests {
    @Test
    func initialAppendExcludesRetryForTheSameCapture() async throws {
        let sink = HeldCaptureAppend(holdingCall: 1)
        let fixture = try CaptureExportFixture(sink: sink)
        defer { sink.release(); fixture.cleanup() }
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let initial = try #require(fixture.app.handleIncomingNote(
            id: id, text: "Synthetic export capture", timestamp: timestamp, container: fixture.container))
        #expect(await sink.waitForHeldEntry(orCompletionOf: initial))
        let pending = PendingExportStore.read(from: fixture.defaults)[id]
        #expect(pending?.processedText == "Synthetic export capture")
        #expect(pending?.timestamp == timestamp)

        for task in fixture.app.retryDeferredExports(container: fixture.container) { await task.value }
        #expect(sink.calls.count == 1, "Retry must not append while initial delivery owns this capture")
        sink.release()
        await initial.value
        #expect(sink.successfulEntries.count == 1)
        #expect(sink.calls.allSatisfy { $0.text == "Synthetic export capture" && $0.timestamp == timestamp })
        try fixture.verifyCompleted(id: id)
    }

    @Test
    func failedInitialDeliveryCanBeRetriedWithoutEarlyAcknowledgement() async throws {
        let sink = HeldCaptureAppend(holdingCall: nil, failedCalls: [1])
        let fixture = try CaptureExportFixture(sink: sink)
        defer { fixture.cleanup() }
        let id = UUID()
        let initial = try #require(fixture.app.handleIncomingNote(
            id: id, text: "Synthetic failed delivery", timestamp: .now, container: fixture.container))
        await initial.value
        #expect(fixture.acknowledgedNotes.isEmpty)
        #expect(PendingExportStore.read(from: fixture.defaults)[id] != nil)
        #expect(try fixture.walContains(id: id, key: .pendingProcessing))
        for task in fixture.app.retryDeferredExports(container: fixture.container) { await task.value }
        #expect(sink.calls.count == 2)
        #expect(sink.successfulEntries.count == 1)
        #expect(fixture.acknowledgedNotes == [id])
        try fixture.verifyCompleted(id: id)
    }

    @Test
    func repeatedRetryDoesNotAppendWhileTheFirstRetryIsHeld() async throws {
        let sink = HeldCaptureAppend(holdingCall: 2, failedCalls: [1])
        let fixture = try CaptureExportFixture(sink: sink)
        defer { sink.release(); fixture.cleanup() }
        let id = UUID()
        let initial = try #require(fixture.app.handleIncomingNote(
            id: id, text: "Synthetic repeated retry", timestamp: .now, container: fixture.container))
        await initial.value
        let firstRetry = try #require(fixture.app.retryDeferredExports(container: fixture.container).first)
        #expect(await sink.waitForHeldEntry(orCompletionOf: firstRetry))
        for task in fixture.app.retryDeferredExports(container: fixture.container) { await task.value }
        #expect(sink.calls.count == 2)
        sink.release()
        await firstRetry.value
        #expect(sink.successfulEntries.count == 1)
        try fixture.verifyCompleted(id: id)
    }

    @Test
    func retryExcludesAudioRecoveryForTheSameCapture() async throws {
        let sink = HeldCaptureAppend(holdingCall: 2, failedCalls: [1])
        let fixture = try CaptureExportFixture(sink: sink)
        defer { sink.release(); fixture.cleanup() }
        let id = UUID()
        let incoming = fixture.directory.appendingPathComponent("synthetic-input.m4a")
        try Data("isolated synthetic audio fixture".utf8).write(to: incoming)
        let initial = try #require(fixture.app.handleIncomingAudio(
            id: id, url: incoming, timestamp: .now, container: fixture.container))
        await initial.value
        #expect(fixture.transcriptionCount == 1)
        #expect(fixture.acknowledgedFiles.isEmpty)
        #expect(try fixture.walContains(id: id, key: .pendingAudioIn))
        #expect(FileManager.default.fileExists(atPath: fixture.runtime.pendingAudioDirectory.appendingPathComponent("\(id.uuidString).m4a").path))
        let firstRetry = try #require(fixture.app.retryDeferredExports(container: fixture.container).first)
        #expect(await sink.waitForHeldEntry(orCompletionOf: firstRetry))
        for task in fixture.app.reprocessPendingItems(container: fixture.container) { await task.value }
        #expect(fixture.transcriptionCount == 1, "Audio recovery must not reprocess a capture owned by retry")
        #expect(sink.calls.count == 2, "Audio recovery must not duplicate the held retry append")
        sink.release()
        await firstRetry.value
        #expect(sink.successfulEntries.count == 1)
        #expect(fixture.acknowledgedFiles == [id])
        #expect(!FileManager.default.fileExists(atPath: fixture.runtime.pendingAudioDirectory.appendingPathComponent("\(id.uuidString).m4a").path))
        try fixture.verifyCompleted(id: id)
    }
}

/// Holds only the chosen append; later calls finish, exposing overlap without sleeps.
@MainActor
private final class HeldCaptureAppend {
    struct Entry { let text: String; let timestamp: Date }
    var calls: [Entry] = []
    var successfulEntries: [Entry] = []
    private let holdingCall: Int?
    private let failedCalls: Set<Int>
    private var held: CheckedContinuation<AppendResult, Never>?
    private var entryWaiter: CheckedContinuation<Bool, Never>?
    private var hasEntered = false
    private var observedTaskCompleted = false

    init(holdingCall: Int?, failedCalls: Set<Int> = []) {
        self.holdingCall = holdingCall
        self.failedCalls = failedCalls
    }

    func append(_ text: String, _ timestamp: Date) async -> AppendResult {
        let entry = Entry(text: text, timestamp: timestamp)
        calls.append(entry)
        let number = calls.count
        let result: AppendResult
        if number == holdingCall {
            result = await withCheckedContinuation { continuation in
                held = continuation
                hasEntered = true
                entryWaiter?.resume(returning: true)
                entryWaiter = nil
            }
        } else {
            result = failedCalls.contains(number) ? .failed : .appended
        }
        if result == .appended { successfulEntries.append(entry) }
        return result
    }

    func waitForHeldEntry(orCompletionOf task: Task<Void, Never>) async -> Bool {
        if hasEntered { return true }
        Task { @MainActor in
            await task.value
            observedTaskCompleted = true
            entryWaiter?.resume(returning: hasEntered)
            entryWaiter = nil
        }
        return await withCheckedContinuation { continuation in
            if hasEntered || observedTaskCompleted { continuation.resume(returning: hasEntered) }
            else { entryWaiter = continuation }
        }
    }

    func release() {
        let continuation = held
        held = nil
        continuation?.resume(returning: .appended)
    }
}

@MainActor
private final class CaptureExportFixture {
    let suite = "CaptureExportTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory: URL
    let container: ModelContainer
    let runtime: CaptureRuntime
    let app: MacroMarkApp
    private let transport: SyntheticTransport
    var acknowledgedNotes: [UUID] { transport.notes }
    var acknowledgedFiles: [UUID] { transport.files }
    var transcriptionCount: Int { transport.transcriptions }

    init(sink: HeldCaptureAppend) throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let audioDirectory = directory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        container = try ModelContainer(for: Macro.self, ProcessedNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        transport = SyntheticTransport()
        let recorder = transport
        runtime = CaptureRuntime(defaults: defaults, pendingAudioDirectory: audioDirectory,
            append: { await sink.append($0, $1) },
            transcribe: { _ in
                recorder.transcriptions += 1
                return AudioTranscriber.TranscriptionResult(text: "Synthetic audio capture", hadPartialFailure: false)
            },
            acknowledgeNote: { recorder.notes.append($0) },
            acknowledgeFile: { recorder.files.append($0) })
        // Simulate durable eligibility only: ACKs go to this recorder, never a Watch.
        app = MacroMarkApp(container: container, captureRuntime: runtime)
        defaults.set(false, forKey: UserDefaultsKey.autoExportEnabled.rawValue)
        defaults.set(ExportTarget.iCloud.rawValue, forKey: UserDefaultsKey.defaultExportTarget.rawValue)
    }

    func verifyCompleted(id: UUID, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let notes = try container.mainContext.fetch(FetchDescriptor<ProcessedNote>())
        #expect(notes.filter { $0.sourceID == id }.count == 1, sourceLocation: sourceLocation)
        #expect(notes.first?.exportStatus == .exported, sourceLocation: sourceLocation)
        #expect(ProcessedNoteIDStore.loadOrder(from: defaults).contains(id), sourceLocation: sourceLocation)
        #expect(PendingExportStore.read(from: defaults)[id] == nil, sourceLocation: sourceLocation)
        for key in [UserDefaultsKey.pendingProcessing, .pendingAudioIn] {
            let data = defaults.data(forKey: key.rawValue) ?? Data("{}".utf8)
            let entries = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(entries?[id.uuidString] == nil, sourceLocation: sourceLocation)
        }
    }

    func walContains(id: UUID, key: UserDefaultsKey) throws -> Bool {
        let data = defaults.data(forKey: key.rawValue) ?? Data("{}".utf8)
        let entries = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return entries?[id.uuidString] != nil
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class SyntheticTransport {
    var notes: [UUID] = []
    var files: [UUID] = []
    var transcriptions = 0
}
