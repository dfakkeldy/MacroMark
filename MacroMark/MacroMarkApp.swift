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

/// A note that has been processed (macros expanded, transcription done) and
/// saved to SwiftData, but whose export to the final target (iCloud `.md` file
/// or a third-party app) has not yet been confirmed. Persisted so a `.deferred`
/// or `.failed` export is retried on subsequent launches / a periodic timer
/// rather than silently dropped after the watch has been ACK'd.
private struct PendingExport: Codable {
    /// The note's UUID — matches the watch-side id and the `processedNoteIDs` set.
    var noteId: UUID
    /// The fully-processed text ready to append (post macro expansion).
    var processedText: String
    /// The original capture timestamp (used for the daily-note filename + heading).
    var timestamp: Date
    /// Whether the originating capture was audio (controls which ACK to send).
    var isAudio: Bool
}

@main
struct MacroMarkApp: App {
    let container: ModelContainer

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
        let resolvedContainer: ModelContainer
        do {
            resolvedContainer = try ModelContainer(for: Macro.self, ProcessedNote.self)
        } catch {
            print("Failed to initialize ModelContainer: \(error). Falling back to in-memory store.")
            Self.usingInMemoryStore = true
            // Try in-memory as first fallback
            if let memoryContainer = try? ModelContainer(
                for: Macro.self, ProcessedNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) {
                resolvedContainer = memoryContainer
            } else {
                // Last-resort: create a bare container with no schema validation
                if let bareContainer = try? ModelContainer(
                    for: Macro.self, ProcessedNote.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                ) {
                    resolvedContainer = bareContainer
                } else {
                    // Truly unrecoverable — but we must not crash
                    resolvedContainer = try! ModelContainer(
                        for: Macro.self,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                    )
                }
            }
            _containerError = State(initialValue: error.localizedDescription)
        }
        container = resolvedContainer

        // Pre-load StoreKit products and request speech authorization once
        Task {
            await StoreManager.shared.loadProducts()
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }

        setupWatchConnectivity()

        // Reprocess any notes that were in-flight when the app was last terminated
        reprocessPendingItems(container: container)
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity() {
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
    private static func readProcessedNoteIDs() -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: UserDefaultsKey.processedNoteIDs.rawValue) else { return [] }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func addProcessedNoteID(_ id: UUID) {
        var processed = readProcessedNoteIDs()
        processed.insert(id)
        UserDefaults.standard.set(processed.map(\.uuidString), forKey: UserDefaultsKey.processedNoteIDs.rawValue)
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
            acknowledgeNoteIfDurable(id: id)
            return
        }
        // Already saved to SwiftData and awaiting export — the retry timer will
        // deliver it. Don't re-process (would create a duplicate note).
        guard pendingExports[id] == nil else { return }
        // Already being processed this session — don't start a duplicate pass.
        guard !Self.inFlightIDs.contains(id) else { return }
        Self.inFlightIDs.insert(id)

        // Write-ahead log: persist raw text + original timestamp before processing
        var pending = pendingProcessing
        pending[id] = PendingNote(text: text, timestamp: timestamp)
        Self.writePendingProcessing(pending)

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
            acknowledgeFileIfDurable(id: id)
            return
        }
        // Already transcribed + saved to SwiftData, awaiting export — the retry
        // timer will deliver it. Don't re-process (would duplicate the note).
        guard pendingExports[id] == nil else { return }

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
        Self.writePendingAudio(pending)

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
        bgTask = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Background task expiring — the raw text/audio is already saved in the
            // write-ahead log, so it will be reprocessed on next launch.
#if DEBUG
            print("MacroMark: Background task '\(name)' expiring for note \(noteId)")
#endif
            Self.inFlightIDs.remove(noteId)
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
#endif

        Task { @MainActor in
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
            if let audioURL = url {
                do {
                    processedText = try await AudioTranscriber.transcribe(fileURL: audioURL)
                } catch {
#if DEBUG
                    print("Failed to transcribe audio: \(error)")
#endif
                    // Keep the audio file AND the WAL entry so it can be retried on
                    // the next launch. Do NOT delete and do NOT ACK — losing the
                    // recording is worse than a deferred retry.
                    Self.inFlightIDs.remove(noteId)
#if canImport(UIKit)
                    if bgTask != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTask)
                        bgTask = .invalid
                    }
#endif
                    return
                }
            } else if let directText = text {
                processedText = directText
            } else {
                Self.inFlightIDs.remove(noteId)
#if canImport(UIKit)
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
#endif
                return
            }

            // Run macro processing (CPU-bound)
            let result = await MacroProcessor.process(text: processedText, macros: macros, date: timestamp) {
                if let location = await LocationManager.shared.getCurrentLocation() {
                    return (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
                return nil
            }

            // Save and export — ACK is sent inside processAndExport only after the
            // export target actually succeeds (§5.1).
            await processAndExport(noteId: noteId, text: result, isAudio: isAudio, timestamp: timestamp, autoExport: autoExport, rawTarget: rawTarget, context: context)

            Self.inFlightIDs.remove(noteId)

#if canImport(UIKit)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
#endif
        }
    }

    // MARK: - Write-ahead log accessors

    /// Remove a text note from the pending-processing write-ahead log.
    private func removePendingProcessing(id: UUID) {
        var pending = Self.readPendingProcessing()
        pending.removeValue(forKey: id)
        Self.writePendingProcessing(pending)
    }

    /// Remove an audio note from the WAL and delete its durable file.
    private func removePendingAudio(id: UUID) {
        var pending = Self.readPendingAudio()
        if let item = pending[id] {
            let url = Self.pendingAudioDirectory.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: url)
        }
        pending.removeValue(forKey: id)
        Self.writePendingAudio(pending)
    }

    private static func readPendingProcessing() -> [UUID: PendingNote] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.pendingProcessing.rawValue),
              let dict = try? JSONDecoder().decode([String: PendingNote].self, from: data)
        else { return [:] }
        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) { partial[id] = entry.value }
        }
    }

    private static func writePendingProcessing(_ dict: [UUID: PendingNote]) {
        let stringDict = dict.reduce(into: [String: PendingNote]()) { $0[$1.key.uuidString] = $1.value }
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.pendingProcessing.rawValue)
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

    private static func writePendingAudio(_ dict: [UUID: PendingAudio]) {
        let stringDict = dict.reduce(into: [String: PendingAudio]()) { $0[$1.key.uuidString] = $1.value }
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.pendingAudioIn.rawValue)
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
    /// The ACK to the watch (and clearing the write-ahead log) happens **only after
    /// the export target succeeds** — the user's definition of "delivered" is "in
    /// the daily-note file," not "saved to SwiftData." On `.deferred` or `.failed`
    /// (or a third-party export that doesn't confirm), the note is recorded in the
    /// `PendingExport` WAL and retried by `retryDeferredExports` so it is never
    /// silently dropped.
    @MainActor
    private func processAndExport(
        noteId: UUID,
        text: String,
        isAudio: Bool,
        timestamp: Date,
        autoExport: Bool,
        rawTarget: String,
        context: ModelContext
    ) async {
        let note = ProcessedNote(text: text, createdAt: timestamp)
        context.insert(note)

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

        // Attempt the export. The ACK and WAL-clearing are gated on its result.
        let exportResult = await performExport(
            note: note,
            text: text,
            timestamp: timestamp,
            autoExport: autoExport,
            rawTarget: rawTarget,
            context: context
        )

        switch exportResult {
        case .appended, .exported:
            // Fully delivered — record as processed, clear the input WAL, ACK the
            // watch so it deletes its copy.
            Self.addProcessedNoteID(noteId)
            if isAudio {
                removePendingAudio(id: noteId)
                acknowledgeFileIfDurable(id: noteId)
            } else {
                removePendingProcessing(id: noteId)
                acknowledgeNoteIfDurable(id: noteId)
            }
        case .deferred, .failed, .noTarget:
            // Saved to SwiftData but NOT delivered to the final target. Keep
            // everything durable in place: the input WAL entry (raw text or the
            // .m4a file), the watch's copy (no ACK), and do NOT mark as processed.
            // Only record a PendingExport entry so the export is retried. This is
            // the data-loss-safe contract: the watch keeps its copy and the phone
            // keeps the raw input until the final target actually confirms
            // delivery. A re-send from the watch (lost ACK) is harmless — the
            // in-flight guard and the input WAL prevent duplicate processing.
            addPendingExport(
                PendingExport(noteId: noteId, processedText: text, timestamp: timestamp, isAudio: isAudio)
            )
        }
    }

    /// The outcome of an export attempt to the configured final target.
    private enum ExportOutcome {
        case appended       // iCloud append succeeded
        case exported       // third-party URL export succeeded
        case deferred       // iCloud file not materialized; retryable
        case failed         // I/O or coordinator failure; retryable
        case noTarget       // no/invalid target configured
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
        guard let target = ExportTarget(rawValue: rawTarget) else {
            // No valid target — fall back to iCloud; if that also has no target,
            // treat as deferred so the note isn't lost.
            let result = await iCloudStorageManager.shared.appendText(text, for: timestamp)
            if result == .appended {
                markExported(note: note, target: .iCloud, context: context)
            }
            return mapAppendResult(result)
        }

        if target == .iCloud {
            let result = await iCloudStorageManager.shared.appendText(text, for: timestamp)
            if result == .appended {
                markExported(note: note, target: .iCloud, context: context)
            }
            return mapAppendResult(result)
        } else if autoExport {
            if let exportURL = ExportManager.url(for: note, to: target) {
                let success = await UIApplication.shared.open(exportURL)
                if success {
                    markExported(note: note, target: target, context: context)
                    return .exported
                }
                return .failed
            }
            return .failed
        }
        // Non-iCloud target with auto-export disabled: nothing to do. Treat as
        // exported (the user opted out of auto-export; the note is in the Inbox).
        return .exported
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
    private func markExported(note: ProcessedNote, target: ExportTarget, context: ModelContext) {
        note.isExported = true
        note.exportTarget = target.rawValue
        do {
            try context.save()
        } catch {
#if DEBUG
            print("MacroMark: failed to persist export flag: \(error)")
#endif
        }
    }

    // MARK: - Pending-export WAL (retry until the final target confirms)

    private static let pendingExportKey = UserDefaultsKey.pendingExports.rawValue

    private var pendingExports: [UUID: PendingExport] { Self.readPendingExports() }

    private func addPendingExport(_ entry: PendingExport) {
        var pending = Self.readPendingExports()
        pending[entry.noteId] = entry
        Self.writePendingExports(pending)
    }

    private func removePendingExport(id: UUID) {
        var pending = Self.readPendingExports()
        pending.removeValue(forKey: id)
        Self.writePendingExports(pending)
    }

    private static func readPendingExports() -> [UUID: PendingExport] {
        guard let data = UserDefaults.standard.data(forKey: pendingExportKey),
              let dict = try? JSONDecoder().decode([String: PendingExport].self, from: data)
        else { return [:] }
        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) { partial[id] = entry.value }
        }
    }

    private static func writePendingExports(_ dict: [UUID: PendingExport]) {
        let stringDict = dict.reduce(into: [String: PendingExport]()) { $0[$1.key.uuidString] = $1.value }
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: pendingExportKey)
        }
    }

    /// Retry every pending export whose final target hasn't confirmed yet.
    /// Called on launch (after `reprocessPendingItems`) and on a periodic timer.
    @MainActor
    private func retryDeferredExports(container: ModelContainer) {
        let pending = pendingExports
        guard !pending.isEmpty else { return }
        let context = container.mainContext
        let autoExport = UserDefaults.standard.bool(forKey: UserDefaultsKey.autoExportEnabled.rawValue)
        let rawTarget = UserDefaults.standard.string(forKey: UserDefaultsKey.defaultExportTarget.rawValue) ?? ExportTarget.iCloud.rawValue

        for (id, entry) in pending {
            // Skip entries already being retried by a prior tick — prevents the
            // periodic timer from spawning a second retry Task for the same id
            // while the first is still awaiting `performExport` (which would
            // double-append the note to the daily file).
            guard !Self.retryingExportIDs.contains(id) else { continue }
            Self.retryingExportIDs.insert(id)

            Task { @MainActor in
                let outcome = await performExport(
                    note: Self.fetchStoredNote(in: context, matching: entry)
                        ?? ProcessedNote(text: entry.processedText, createdAt: entry.timestamp),
                    text: entry.processedText,
                    timestamp: entry.timestamp,
                    autoExport: autoExport,
                    rawTarget: rawTarget,
                    context: context
                )
                Self.retryingExportIDs.remove(id)

                if outcome == .appended || outcome == .exported {
                    // Full delivery cleanup — the note has now reached its final
                    // target, so clear the input WAL, drop the durable audio file
                    // (if any), mark as processed, and ACK the watch so it frees
                    // its copy. This is the symmetric counterpart of the success
                    // arm in `processAndExport`.
                    Self.addProcessedNoteID(entry.noteId)
                    if entry.isAudio {
                        removePendingAudio(id: entry.noteId)
                        acknowledgeFileIfDurable(id: entry.noteId)
                    } else {
                        removePendingProcessing(id: entry.noteId)
                        acknowledgeNoteIfDurable(id: entry.noteId)
                    }
                    removePendingExport(id: entry.noteId)
                }
            }
        }
    }

    /// IDs whose export retry is currently in flight (guarded so the periodic
    /// timer doesn't double-append a note while a prior retry awaits an append).
    @MainActor private static var retryingExportIDs: Set<UUID> = []

    /// Find the persisted `ProcessedNote` matching a pending-export entry, so its
    /// `isExported` flag can be updated on retry success. Matches on the exact
    /// `createdAt` + `text` the WAL recorded.
    private static func fetchStoredNote(in context: ModelContext, matching entry: PendingExport) -> ProcessedNote? {
        let timestamp = entry.timestamp
        let text = entry.processedText
        let predicate = #Predicate<ProcessedNote> { $0.createdAt == timestamp && $0.text == text }
        return (try? context.fetch(FetchDescriptor<ProcessedNote>(predicate: predicate)))?.first
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            AppTabView()
                .environment(entitlementManager)
                .environment(storeManager)
                .task {
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
        }
        .modelContainer(container)
    }
}
