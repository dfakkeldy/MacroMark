//
//  MacroMarkApp.swift
//  MacroMark
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import SwiftUI
import SwiftData
import MacroMarkKit
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif
import Speech

/// A note awaiting processing. Persisted (write-ahead log) so an interrupted
/// note is reprocessed on next launch with its ORIGINAL timestamp.
private struct PendingNote: Codable {
    var text: String
    var timestamp: Date
}

/// An audio note awaiting transcription + save. The audio bytes live on disk in
/// the durable pending-audio directory; this tracks the queue + timestamp.
private struct PendingAudio: Codable {
    var filename: String
    var timestamp: Date
}

private typealias PendingExport = PendingExportRecord

private enum WriteAheadLogError: Error {
    case userDefaultsWriteFailed
}

@main
struct MacroMarkApp: App {
    let container: ModelContainer?

    @State private var navigation = AppNavigation()
    @State private var storeManager = StoreManager.shared
    @State private var entitlementManager = EntitlementManager.shared
    @State private var containerError: String?

    /// True when the on-disk SwiftData store could not be opened and we are
    /// running on a volatile in-memory store. While true we must NOT ACK the
    /// watch (its copy is the only durable one) and the warning is not dismissable.
    @MainActor private static var usingInMemoryStore = false

    /// IDs currently being processed this session. Prevents a re-send (or a
    /// launch-time reprocess racing a live delivery) from creating duplicates.
    @MainActor private static var inFlightIDs: Set<UUID> = []

    init() {
        ScreenshotMode.configureDefaults()

        let resolvedContainer: ModelContainer?
        var startupError: String?
        do {
            if ScreenshotMode.isEnabled {
                Self.usingInMemoryStore = true
                resolvedContainer = try ModelContainer(
                    for: Macro.self, ProcessedNote.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                )
            } else {
                resolvedContainer = try ModelContainer(for: Macro.self, ProcessedNote.self)
            }
        } catch {
#if DEBUG
            print("Failed to initialize ModelContainer: \(error). Falling back to in-memory store.")
#endif
            Self.usingInMemoryStore = true
            startupError = error.localizedDescription
            resolvedContainer = Self.makeInMemoryContainer()
        }
        container = resolvedContainer
        _containerError = State(initialValue: startupError)

        guard let resolvedContainer, !ScreenshotMode.isEnabled else { return }

        // Pre-load StoreKit products
        Task {
            await StoreManager.shared.loadProducts()
        }

        setupWatchConnectivity(container: resolvedContainer)
    }

    private static func makeInMemoryContainer() -> ModelContainer? {
        try? ModelContainer(
            for: Macro.self, ProcessedNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity(container: ModelContainer) {
        let provider = WatchConnectivityProvider.shared
        provider.onNoteReceived = { [container] id, text, timestamp in
            handleIncomingNote(id: id, text: text, timestamp: timestamp, container: container)
        }
        provider.onFileReceived = { [container] id, url, timestamp in
            handleIncomingAudio(id: id, url: url, timestamp: timestamp, container: container)
        }
    }

    // MARK: - Durable storage locations

    /// Durable directory for received-but-not-yet-saved audio. NOT the system
    /// temp dir, which the OS can purge before we transcribe.
    private static let pendingAudioDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PendingAudioIn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Note Processing Pipeline

    // MARK: Deduplication & Write-Ahead Log

    /// Set of note UUIDs that have been successfully saved. Prevents double-processing
    /// when the watch re-sends a note because it didn't receive our ACK.
    /// Capped at ~5000 entries (LRU eviction) to bound UserDefaults plist growth.
    private static let maxProcessedNoteIDs = 5000
    @MainActor private static var cachedProcessedIDs: Set<UUID>?
    @MainActor private static var cachedProcessedIDOrder: [UUID]?

    private static func readProcessedNoteIDOrder() -> [UUID] {
        if let cached = cachedProcessedIDOrder { return cached }
        let order = ProcessedNoteIDStore.loadOrder()
        cachedProcessedIDOrder = order
        cachedProcessedIDs = Set(order)
        return order
    }

    private static func readProcessedNoteIDs() -> Set<UUID> {
        if let cached = cachedProcessedIDs {
            return cached
        }
        let order = readProcessedNoteIDOrder()
        let ids = Set(order)
        cachedProcessedIDs = ids
        return ids
    }

    private static func addProcessedNoteID(_ id: UUID) {
        let updatedOrder = ProcessedNoteIDStore.inserting(
            id,
            into: readProcessedNoteIDOrder(),
            maxCount: maxProcessedNoteIDs
        )
        ProcessedNoteIDStore.saveOrder(updatedOrder)
        cachedProcessedIDOrder = updatedOrder
        cachedProcessedIDs = Set(updatedOrder)
    }

    private var processedNoteIDs: Set<UUID> { Self.readProcessedNoteIDs() }

    /// Text write-ahead log: note UUID → {text, timestamp}. Entries are added
    /// before processing and removed only after the note is durably saved.
    private var pendingProcessing: [UUID: PendingNote] { Self.readPendingProcessing() }

    /// Audio write-ahead log: note UUID → {filename, timestamp}. The audio bytes
    /// stay on disk until the note is durably saved.
    private var pendingAudio: [UUID: PendingAudio] { Self.readPendingAudio() }

    /// Process any notes left in the pending queues from a previous terminated session.
    @MainActor
    private func reprocessPendingItems(container: ModelContainer) {
        let textItems = pendingProcessing
        let audioItems = pendingAudio
        guard !textItems.isEmpty || !audioItems.isEmpty else { return }
#if DEBUG
        print("MacroMark: Reprocessing \(textItems.count) text + \(audioItems.count) audio item(s) from previous session")
#endif
        for (id, item) in textItems {
            handleIncomingNote(id: id, text: item.text, timestamp: item.timestamp, container: container)
        }
        for (id, item) in audioItems {
            let url = Self.pendingAudioDirectory.appendingPathComponent(item.filename)
            // If the audio file is gone we can't recover it; drop the dangling entry.
            guard FileManager.default.fileExists(atPath: url.path) else {
                removePendingAudio(id: id)
                continue
            }
            processAudio(id: id, url: url, timestamp: item.timestamp, container: container)
        }
    }

    /// Re-attempt any exports that saved to SwiftData but failed to reach the
    /// final target (e.g. iCloud daily file wasn't materialized). Called from
    /// the scene's `.task` on appear and on a periodic timer.
    @MainActor
    private func reprocessAndRetry(container: ModelContainer) {
        reprocessPendingItems(container: container)
        retryDeferredExports(container: container)
    }

    /// Shared entry point for text notes (from watch dictation).
    @MainActor
    private func handleIncomingNote(id: UUID, text: String, timestamp: Date, container: ModelContainer) {
#if DEBUG
        print("MacroMark iOS Received Note: \(text)")
#endif
        // Deduplicate: if we've already processed this note, just re-send the ACK
        if processedNoteIDs.contains(id) {
            if pendingProcessing[id] != nil {
                removePendingProcessing(id: id)
            }
            acknowledgeNoteIfDurable(id: id)
            return
        }
        // Already saved to SwiftData and awaiting export — the retry timer will
        // deliver it. Don't re-process (would create a duplicate note).
        guard pendingExports[id] == nil else { return }
        // Already being processed this session — don't start a duplicate pass.
        guard !Self.inFlightIDs.contains(id) else { return }

        // Write-ahead log: persist raw text + original timestamp before processing
        var pending = pendingProcessing
        pending[id] = PendingNote(text: text, timestamp: timestamp)
        do {
            try Self.writePendingProcessing(pending)
        } catch {
#if DEBUG
            print("MacroMark: failed to persist text WAL for \(id): \(error)")
#endif
            return
        }

        Self.inFlightIDs.insert(id)
        startBackgroundTaskAndProcess(name: "ProcessNote", noteId: id, text: text, isAudio: false, timestamp: timestamp, container: container)
    }

    /// Shared entry point for audio files (from watch voice recording).
    /// Uses the watch-supplied `id` end-to-end so the ACK matches the watch's queue.
    @MainActor
    private func handleIncomingAudio(id: UUID, url: URL, timestamp: Date, container: ModelContainer) {
#if DEBUG
        print("MacroMark iOS Received Audio File: \(url)")
#endif
        if processedNoteIDs.contains(id) {
            if pendingAudio[id] != nil {
                removePendingAudio(id: id)
            }
            acknowledgeFileIfDurable(id: id)
            return
        }
        // Already transcribed + saved to SwiftData, awaiting export — the retry
        // timer will deliver it. Don't re-process (would duplicate the note).
        guard pendingExports[id] == nil else { return }
        // Already being transcribed this session — don't replace the file under
        // the active speech recognizer.
        guard !Self.inFlightIDs.contains(id) else { return }

        // Move the audio into durable storage and record it in the WAL BEFORE
        // processing, so a crash mid-transcription doesn't lose the recording.
        let destURL = Self.pendingAudioDirectory.appendingPathComponent("\(id.uuidString).m4a")
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: url, to: destURL)
        } catch {
            try? FileManager.default.copyItem(at: url, to: destURL)
        }
        guard FileManager.default.fileExists(atPath: destURL.path) else {
#if DEBUG
            print("MacroMark: Failed to persist incoming audio \(id) — leaving for watch retry")
#endif
            return  // No ACK → watch keeps its copy and re-sends.
        }

        var pending = pendingAudio
        pending[id] = PendingAudio(filename: destURL.lastPathComponent, timestamp: timestamp)
        do {
            try Self.writePendingAudio(pending)
        } catch {
#if DEBUG
            print("MacroMark: failed to persist audio WAL for \(id): \(error)")
#endif
            return
        }

        processAudio(id: id, url: destURL, timestamp: timestamp, container: container)
    }

    @MainActor
    private func processAudio(id: UUID, url: URL, timestamp: Date, container: ModelContainer) {
        guard !Self.inFlightIDs.contains(id) else { return }
        Self.inFlightIDs.insert(id)
        startBackgroundTaskAndProcess(name: "ProcessAudio", noteId: id, url: url, isAudio: true, timestamp: timestamp, container: container)
    }

    /// Process a note through the full pipeline: (transcribe →) macros → save → export.
    @MainActor
    private func startBackgroundTaskAndProcess(
        name: String,
        noteId: UUID,
        text: String? = nil,
        url: URL? = nil,
        isAudio: Bool,
        timestamp: Date,
        container: ModelContainer
    ) {
#if canImport(UIKit)
        var bgTask = UIBackgroundTaskIdentifier.invalid
        var processingTask: Task<Void, Never>?
        bgTask = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Background task expiring — the raw text/audio is already saved in the
            // write-ahead log, so it will be reprocessed on next launch.
#if DEBUG
            print("MacroMark: Background task '\(name)' expiring for note \(noteId)")
#endif
            Task { @MainActor in
                processingTask?.cancel()
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
            }
        }
#endif

        let task = Task { @MainActor in
            defer {
                Self.inFlightIDs.remove(noteId)
#if canImport(UIKit)
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
#endif
            }

            guard !Task.isCancelled else { return }

            let processedText: String
            let macros: [Macro]

            // Fetch macros on main actor (SwiftData requirement)
            let context = container.mainContext
            let descriptor = FetchDescriptor<Macro>(sortBy: [SortDescriptor(\.createdAt)])
            macros = (try? context.fetch(descriptor)) ?? []

            // Snapshot settings on main actor to avoid races
            let autoExport = UserDefaults.standard.bool(forKey: UserDefaultsKey.autoExportEnabled.rawValue)
            let rawTarget = UserDefaults.standard.string(forKey: UserDefaultsKey.defaultExportTarget.rawValue) ?? ExportTarget.iCloud.rawValue

            // Transcribe audio if needed, otherwise use text directly
            var transcriptionPartial = false
            if let audioURL = url {
                do {
                    let result = try await AudioTranscriber.transcribe(fileURL: audioURL)
                    guard !Task.isCancelled else { return }
                    processedText = result.text
                    transcriptionPartial = result.hadPartialFailure
                } catch {
#if DEBUG
                    print("Failed to transcribe audio: \(error)")
#endif
                    // Keep the audio file AND the WAL entry so it can be retried on
                    // the next launch. Do NOT delete and do NOT ACK — losing the
                    // recording is worse than a deferred retry.
                    return
                }
            } else if let directText = text {
                processedText = directText
            } else {
                return
            }

            // Run macro processing (CPU-bound). Snapshot the SwiftData models into
            // Sendable value types on the main actor before handing them to the
            // off-actor processor — `@Model` objects must not cross isolation domains.
            let macroRules = macros.map { MacroRule(trigger: $0.trigger, replacement: $0.replacement) }
            let result = await MacroProcessor.process(text: processedText, macros: macroRules, date: timestamp) {
                if let location = await LocationManager.shared.getCurrentLocation() {
                    return (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
                return nil
            }
            guard !Task.isCancelled else { return }

            // Save and export — ACK is sent inside processAndExport only after the
            // export target actually succeeds (§5.1).
            await processAndExport(noteId: noteId, text: result, isAudio: isAudio, timestamp: timestamp, autoExport: autoExport, rawTarget: rawTarget, context: context, transcriptionPartial: transcriptionPartial)
        }
#if canImport(UIKit)
        processingTask = task
#endif
    }

    // MARK: - Write-ahead log accessors

    /// Remove a text note from the pending-processing write-ahead log.
    private func removePendingProcessing(id: UUID) {
        var pending = Self.readPendingProcessing()
        pending.removeValue(forKey: id)
        do {
            try Self.writePendingProcessing(pending)
        } catch {
#if DEBUG
            print("MacroMark: failed to remove text WAL entry \(id): \(error)")
#endif
        }
    }

    /// Remove an audio note from the WAL and delete its durable file.
    private func removePendingAudio(id: UUID) {
        var pending = Self.readPendingAudio()
        if let item = pending[id] {
            let url = Self.pendingAudioDirectory.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: url)
        }
        pending.removeValue(forKey: id)
        do {
            try Self.writePendingAudio(pending)
        } catch {
#if DEBUG
            print("MacroMark: failed to remove audio WAL entry \(id): \(error)")
#endif
        }
    }

    private static func readPendingProcessing() -> [UUID: PendingNote] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.pendingProcessing.rawValue),
              let dict = try? JSONDecoder().decode([String: PendingNote].self, from: data)
        else { return [:] }
        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) { partial[id] = entry.value }
        }
    }

    private static func writePendingProcessing(_ dict: [UUID: PendingNote]) throws {
        let stringDict = dict.reduce(into: [String: PendingNote]()) { $0[$1.key.uuidString] = $1.value }
        let data = try JSONEncoder().encode(stringDict)
        UserDefaults.standard.set(data, forKey: UserDefaultsKey.pendingProcessing.rawValue)
        guard UserDefaults.standard.synchronize() else {
            throw WriteAheadLogError.userDefaultsWriteFailed
        }
    }

    private static func readPendingAudio() -> [UUID: PendingAudio] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.pendingAudioIn.rawValue),
              let dict = try? JSONDecoder().decode([String: PendingAudio].self, from: data)
        else { return [:] }
        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) { partial[id] = entry.value }
        }
    }

    private static func writePendingAudio(_ dict: [UUID: PendingAudio]) throws {
        let stringDict = dict.reduce(into: [String: PendingAudio]()) { $0[$1.key.uuidString] = $1.value }
        let data = try JSONEncoder().encode(stringDict)
        UserDefaults.standard.set(data, forKey: UserDefaultsKey.pendingAudioIn.rawValue)
        guard UserDefaults.standard.synchronize() else {
            throw WriteAheadLogError.userDefaultsWriteFailed
        }
    }

    // MARK: - ACK helpers (suppressed on the volatile in-memory store)

    @MainActor
    private func acknowledgeNoteIfDurable(id: UUID) {
        guard !Self.usingInMemoryStore else { return }
        WatchConnectivityProvider.shared.acknowledgeNote(id: id)
    }

    @MainActor
    private func acknowledgeFileIfDurable(id: UUID) {
        guard !Self.usingInMemoryStore else { return }
        WatchConnectivityProvider.shared.acknowledgeFile(id: id)
    }

    /// Save the processed text to SwiftData and export to the configured target.
    ///
    /// The ACK to the watch (and clearing the write-ahead log) happens only after
    /// the note reaches a durable terminal state. iCloud must append successfully;
    /// third-party URL targets stay visible in the inbox because those apps cannot
    /// confirm receipt. Deferred or failed iCloud exports remain in `PendingExport`
    /// and retry until the daily-note append completes.
    @MainActor
    private func processAndExport(
        noteId: UUID,
        text: String,
        isAudio: Bool,
        timestamp: Date,
        autoExport: Bool,
        rawTarget: String,
        context: ModelContext,
        transcriptionPartial: Bool = false
    ) async {
        let note: ProcessedNote
        if let existingNote = Self.fetchStoredNote(in: context, sourceID: noteId) {
            note = existingNote
            note.exportStatus = .processing
            note.exportStatusMessage = "Processing capture."
        } else {
            note = ProcessedNote(
                text: text,
                sourceID: noteId,
                createdAt: timestamp,
                transcriptionPartial: transcriptionPartial,
                exportStatus: .processing,
                exportStatusMessage: "Processing capture."
            )
            context.insert(note)
        }

        // Save to SwiftData (the durable source of truth for the note content).
        do {
            try context.save()
        } catch {
#if DEBUG
            print("MacroMark: SwiftData save failed for note \(noteId): \(error)")
#endif
            // Leave the note in the input WAL for retry on next launch.
            // Do NOT send ACK — the watch will re-send.
            return
        }

        let exportText = note.text
        let exportTarget = ExportTarget(rawValue: rawTarget) ?? .iCloud
        do {
            try addPendingExport(
                PendingExport(
                    noteId: noteId,
                    processedText: exportText,
                    timestamp: timestamp,
                    target: exportTarget,
                    isAudio: isAudio
                )
            )
        } catch {
#if DEBUG
            print("MacroMark: failed to persist pending export for note \(noteId): \(error)")
#endif
            do {
                try markExportPending(note: note, outcome: .failed, context: context)
            } catch {
#if DEBUG
                print("MacroMark: failed to persist pending-export failure for note \(noteId): \(error)")
#endif
            }
            return
        }

        // Attempt the export. The ACK and WAL-clearing are gated on its result.
        let exportResult = await performExport(
            note: note,
            text: exportText,
            timestamp: timestamp,
            autoExport: autoExport,
            rawTarget: rawTarget,
            context: context
        )

        switch exportResult {
        case .appended, .savedInInbox:
            // Durable terminal state — record as processed, clear the input WAL,
            // and ACK the watch so it deletes its copy.
            Self.addProcessedNoteID(noteId)
            if isAudio {
                removePendingAudio(id: noteId)
                acknowledgeFileIfDurable(id: noteId)
            } else {
                removePendingProcessing(id: noteId)
                acknowledgeNoteIfDurable(id: noteId)
            }
            do {
                try removePendingExport(id: noteId)
            } catch {
#if DEBUG
                print("MacroMark: failed to remove pending export \(noteId): \(error)")
#endif
            }
        case .deferred, .failed:
            // Saved to SwiftData but NOT delivered to the final target. Keep
            // everything durable in place: the input WAL entry (raw text or the
            // .m4a file), the watch's copy (no ACK), and do NOT mark as processed.
            // The pending-export WAL was written before export, so a crash after
            // SwiftData save but before/inside export retries by source ID.
            do {
                try markExportPending(note: note, outcome: exportResult, context: context)
            } catch {
#if DEBUG
                print("MacroMark: failed to persist export status for \(noteId): \(error)")
#endif
            }
        }
    }

    /// The outcome of an export attempt to the configured final target.
    private enum ExportOutcome {
        case appended       // iCloud append succeeded
        case savedInInbox   // saved locally; no final-target confirmation
        case deferred       // iCloud file not materialized; retryable
        case failed         // I/O or coordinator failure; retryable
    }

    /// Run the configured export. Does not touch the WAL or send any ACK — the
    /// caller decides what to do based on the outcome.
    @MainActor
    private func performExport(
        note: ProcessedNote,
        text: String,
        timestamp: Date,
        autoExport: Bool,
        rawTarget: String,
        context: ModelContext
    ) async -> ExportOutcome {
        note.lastExportAttemptAt = .now
        guard let target = ExportTarget(rawValue: rawTarget) else {
            do {
                try markSavedInInbox(
                    note: note,
                    target: nil,
                    message: "Saved in the inbox because no export target was available.",
                    context: context
                )
                return .savedInInbox
            } catch {
                return .failed
            }
        }

        if target == .iCloud {
            let result = await iCloudStorageManager.shared.appendText(text, for: timestamp)
            if result == .appended {
                do {
                    try markExported(note: note, target: .iCloud, context: context)
                } catch {
                    return .failed
                }
            }
            return mapAppendResult(result)
        } else if autoExport {
            if let exportURL = ExportManager.url(for: note, to: target) {
                let success = await UIApplication.shared.open(exportURL)
                do {
                    try markSavedInInbox(
                        note: note,
                        target: target,
                        message: success
                            ? "Opened \(target.rawValue). Confirm the note in the destination app."
                            : "Could not open \(target.rawValue). The note is saved in the inbox.",
                        context: context
                    )
                    return .savedInInbox
                } catch {
                    return .failed
                }
            }
            do {
                try markSavedInInbox(
                    note: note,
                    target: target,
                    message: "Saved in the inbox because \(target.rawValue) cannot be opened automatically.",
                    context: context
                )
                return .savedInInbox
            } catch {
                return .failed
            }
        }
        do {
            try markSavedInInbox(
                note: note,
                target: target,
                message: "Saved in the inbox. Use Export when you are ready to send it to \(target.rawValue).",
                context: context
            )
            return .savedInInbox
        } catch {
            return .failed
        }
    }

    @MainActor
    private func mapAppendResult(_ result: AppendResult) -> ExportOutcome {
        switch result {
        case .appended: return .appended
        case .deferred: return .deferred
        case .failed: return .failed
        }
    }

    @MainActor
    private func markExported(note: ProcessedNote, target: ExportTarget, context: ModelContext) throws {
        note.isExported = true
        note.exportTarget = target.rawValue
        note.exportStatus = .exported
        note.exportStatusMessage = "Saved to \(target.rawValue)."
        note.lastExportedAt = .now
        try context.save()
    }

    @MainActor
    private func markSavedInInbox(
        note: ProcessedNote,
        target: ExportTarget?,
        message: String,
        context: ModelContext
    ) throws {
        note.isExported = false
        note.exportTarget = target?.rawValue
        note.exportStatus = .noTarget
        note.exportStatusMessage = message
        note.lastExportAttemptAt = .now
        try context.save()
    }

    @MainActor
    private func markExportPending(note: ProcessedNote, outcome: ExportOutcome, context: ModelContext) throws {
        note.lastExportAttemptAt = .now
        switch outcome {
        case .deferred:
            note.exportStatus = .deferred
            note.exportStatusMessage = "Waiting for iCloud or the selected destination to become available."
        case .failed:
            note.exportStatus = .failed
            note.exportStatusMessage = "The export failed. The original capture is still queued for retry."
        case .appended, .savedInInbox:
            return
        }
        try context.save()
    }

    // MARK: - Pending-export WAL (retry until the final target confirms)

    private var pendingExports: [UUID: PendingExport] { Self.readPendingExports() }

    private func addPendingExport(_ entry: PendingExport) throws {
        try PendingExportStore.upsert(entry)
    }

    private func removePendingExport(id: UUID) throws {
        try PendingExportStore.remove(id: id)
    }

    private static func readPendingExports() -> [UUID: PendingExport] {
        PendingExportStore.read()
    }

    /// Retry every pending export whose final target hasn't confirmed yet.
    /// Called on launch (after `reprocessPendingItems`) and on a periodic timer.
    @MainActor
    private func retryDeferredExports(container: ModelContainer) {
        let pending = pendingExports
        guard !pending.isEmpty else { return }
        let context = container.mainContext
        let autoExport = UserDefaults.standard.bool(forKey: UserDefaultsKey.autoExportEnabled.rawValue)
        let processedIDs = Self.readProcessedNoteIDs()

        for (id, entry) in pending {
            if processedIDs.contains(entry.noteId) {
                do {
                    try removePendingExport(id: id)
                } catch {
#if DEBUG
                    print("MacroMark: failed to remove already-processed pending export \(id): \(error)")
#endif
                }
                continue
            }

            // Skip entries already being retried by a prior tick — prevents the
            // periodic timer from spawning a second retry Task for the same id
            // while the first is still awaiting `performExport` (which would
            // double-append the note to the daily file).
            guard !Self.retryingExportIDs.contains(id) else { continue }
            Self.retryingExportIDs.insert(id)

            Task { @MainActor in
                let storedNote = Self.fetchStoredNote(in: context, matching: entry)
                let note: ProcessedNote
                if let storedNote {
                    if storedNote.exportStatus == .exported {
                        Self.addProcessedNoteID(entry.noteId)
                        do {
                            try removePendingExport(id: id)
                        } catch {
#if DEBUG
                            print("MacroMark: failed to remove exported pending export \(id): \(error)")
#endif
                        }
                        Self.retryingExportIDs.remove(id)
                        return
                    }
                    note = storedNote
                } else {
                    note = ProcessedNote(
                        text: entry.processedText,
                        sourceID: entry.noteId,
                        createdAt: entry.timestamp,
                        exportTarget: entry.targetRawValue,
                        exportStatus: .deferred,
                        exportStatusMessage: "Recovered from the retry queue."
                    )
                    context.insert(note)
                    do {
                        try context.save()
                    } catch {
#if DEBUG
                        print("MacroMark: failed to restore pending-export note \(entry.noteId): \(error)")
#endif
                        Self.retryingExportIDs.remove(id)
                        return
                    }
                }

                let outcome = await performExport(
                    note: note,
                    text: note.text,
                    timestamp: note.createdAt,
                    autoExport: autoExport,
                    rawTarget: entry.targetRawValue,
                    context: context
                )
                Self.retryingExportIDs.remove(id)

                if outcome == .appended || outcome == .savedInInbox {
                    // Durable-terminal-state cleanup. This is the symmetric
                    // counterpart of the success arm in `processAndExport`.
                    Self.addProcessedNoteID(entry.noteId)
                    if entry.isAudio {
                        removePendingAudio(id: entry.noteId)
                        if entry.requiresWatchAcknowledgement {
                            acknowledgeFileIfDurable(id: entry.noteId)
                        }
                    } else {
                        removePendingProcessing(id: entry.noteId)
                        if entry.requiresWatchAcknowledgement {
                            acknowledgeNoteIfDurable(id: entry.noteId)
                        }
                    }
                    do {
                        try removePendingExport(id: id)
                    } catch {
#if DEBUG
                        print("MacroMark: failed to remove pending export \(id): \(error)")
#endif
                    }
                } else {
                    do {
                        try markExportPending(note: note, outcome: outcome, context: context)
                    } catch {
#if DEBUG
                        print("MacroMark: failed to persist retry status for \(entry.noteId): \(error)")
#endif
                    }
                }
            }
        }
    }

    /// IDs whose export retry is currently in flight (guarded so the periodic
    /// timer doesn't double-append a note while a prior retry awaits an append).
    @MainActor private static var retryingExportIDs: Set<UUID> = []

    /// Find the persisted `ProcessedNote` matching a pending-export entry.
    /// New records use durable source IDs; the timestamp fallback exists only for
    /// pending export records created before the source ID field existed.
    private static func fetchStoredNote(in context: ModelContext, matching entry: PendingExport) -> ProcessedNote? {
        if let note = fetchStoredNote(in: context, sourceID: entry.noteId) {
            return note
        }
        let timestamp = entry.timestamp
        let predicate = #Predicate<ProcessedNote> { $0.createdAt == timestamp }
        return (try? context.fetch(FetchDescriptor<ProcessedNote>(predicate: predicate)))?.first
    }

    private static func fetchStoredNote(in context: ModelContext, sourceID: UUID) -> ProcessedNote? {
        let predicate = #Predicate<ProcessedNote> { $0.sourceID == sourceID }
        return (try? context.fetch(FetchDescriptor<ProcessedNote>(predicate: predicate)))?.first
    }

    private func parseRouteDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    @MainActor
    private func appendTextFromRoute(_ text: String, container: ModelContainer, navigation: AppNavigation) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let timestamp = Date()
        let shortcutNoteID = UUID()
        navigation.openDailyLog(date: timestamp)

        let context = container.mainContext
        let note = ProcessedNote(
            text: trimmedText,
            sourceID: shortcutNoteID,
            createdAt: timestamp,
            exportStatus: .processing,
            exportStatusMessage: "Processing capture."
        )
        context.insert(note)

        do {
            try context.save()
        } catch {
#if DEBUG
            print("MacroMark: failed to save append-route note: \(error)")
#endif
            return
        }

        let result = await iCloudStorageManager.shared.appendText(trimmedText, for: timestamp)
        note.lastExportAttemptAt = .now

        switch result {
        case .appended:
            note.isExported = true
            note.exportTarget = ExportTarget.iCloud.rawValue
            note.exportStatus = .exported
            note.exportStatusMessage = "Saved to \(ExportTarget.iCloud.rawValue)."
            note.lastExportedAt = .now
        case .deferred:
            note.exportStatus = .deferred
            note.exportStatusMessage = "Waiting for iCloud or the selected destination to become available."
            do {
                try addPendingExport(
                    PendingExport(
                        noteId: shortcutNoteID,
                        processedText: trimmedText,
                        timestamp: timestamp,
                        target: .iCloud,
                        isAudio: false,
                        requiresWatchAcknowledgement: false
                    )
                )
            } catch {
                note.exportStatus = .failed
                note.exportStatusMessage = "The shortcut append could not be queued for retry."
            }
        case .failed:
            note.exportStatus = .failed
            note.exportStatusMessage = "The shortcut append is queued for retry."
            do {
                try addPendingExport(
                    PendingExport(
                        noteId: shortcutNoteID,
                        processedText: trimmedText,
                        timestamp: timestamp,
                        target: .iCloud,
                        isAudio: false,
                        requiresWatchAcknowledgement: false
                    )
                )
            } catch {
                note.exportStatusMessage = "The shortcut append could not be queued for retry."
            }
        }

        do {
            try context.save()
        } catch {
#if DEBUG
            print("MacroMark: failed to persist append-route export status: \(error)")
#endif
        }
    }

    private func handleOpenURL(_ url: URL, container: ModelContainer, navigation: AppNavigation) {
        guard url.scheme == AppRoute.scheme else { return }

        if url.host == "capture" {
            switch url.path {
            case "/instant":
                navigation.openCaptureComposer(date: .now, mode: .instant)
            case "/system", "":
                navigation.openCaptureComposer(date: .now, mode: .system)
            default:
                navigation.openDailyLog(date: .now)
            }
            return
        }

        if url.host == "daily-log" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let rawDate = components?.queryItems?.first(where: { $0.name == "date" })?.value
            navigation.openDailyLog(date: parseRouteDate(rawDate))
            return
        }

        if url.host == "append" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let text = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            Task { @MainActor in
                await appendTextFromRoute(text, container: container, navigation: navigation)
            }
        }
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            if let container {
                AppTabView()
                    .environment(navigation)
                    .environment(entitlementManager)
                    .environment(storeManager)
                    .onOpenURL { url in
                        handleOpenURL(url, container: container, navigation: navigation)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .retryDeferredExports)) { _ in
                        retryDeferredExports(container: container)
                    }
                    .task {
                        guard !ScreenshotMode.isEnabled else { return }

                        // Retry any exports that saved to SwiftData but didn't reach
                        // the final target before (iCloud file wasn't materialized, etc.).
                        reprocessAndRetry(container: container)
                        // Periodically retry while foregrounded — bounded so we don't
                        // spin forever if iCloud is permanently unavailable.
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(60))
                            if Task.isCancelled { break }
                            retryDeferredExports(container: container)
                        }
                    }
                    .overlay(alignment: .top) {
                        if let error = containerError {
                            HStack {
                                Text("Storage error: \(error). Using temporary storage — changes may not be saved.")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                // Only allow dismissal when we are NOT on the volatile
                                // in-memory store. On in-memory storage the warning must
                                // stay visible because notes will be lost on quit.
                                if !Self.usingInMemoryStore {
                                    Button {
                                        withAnimation {
                                            containerError = nil
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                            }
                            .padding(12)
                            .background(.orange, in: .rect(cornerRadius: 8))
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .modelContainer(container)
            } else {
                StorageUnavailableView(message: containerError)
            }
        }
    }
}

private struct StorageUnavailableView: View {
    let message: String?

    var body: some View {
        ContentUnavailableView {
            Label("Storage Unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message ?? "MacroMark could not open its local storage. Relaunch the app or reinstall if this persists.")
        }
    }
}
