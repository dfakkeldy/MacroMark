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
        guard let strings = UserDefaults.standard.stringArray(forKey: "MacroMark_ProcessedNoteIDs") else { return [] }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func addProcessedNoteID(_ id: UUID) {
        var processed = readProcessedNoteIDs()
        processed.insert(id)
        UserDefaults.standard.set(processed.map(\.uuidString), forKey: "MacroMark_ProcessedNoteIDs")
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
            let autoExport = UserDefaults.standard.bool(forKey: "autoExportEnabled")
            let rawTarget = UserDefaults.standard.string(forKey: "defaultExportTarget") ?? ExportTarget.iCloud.rawValue

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

            // Save and export — ACK is sent inside processAndExport on success
            processAndExport(noteId: noteId, text: result, isAudio: isAudio, timestamp: timestamp, autoExport: autoExport, rawTarget: rawTarget, context: context)

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
        guard let data = UserDefaults.standard.data(forKey: "MacroMark_PendingProcessing"),
              let dict = try? JSONDecoder().decode([String: PendingNote].self, from: data)
        else { return [:] }
        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) { partial[id] = entry.value }
        }
    }

    private static func writePendingProcessing(_ dict: [UUID: PendingNote]) {
        let stringDict = dict.reduce(into: [String: PendingNote]()) { $0[$1.key.uuidString] = $1.value }
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: "MacroMark_PendingProcessing")
        }
    }

    private static func readPendingAudio() -> [UUID: PendingAudio] {
        guard let data = UserDefaults.standard.data(forKey: "MacroMark_PendingAudioIn"),
              let dict = try? JSONDecoder().decode([String: PendingAudio].self, from: data)
        else { return [:] }
        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) { partial[id] = entry.value }
        }
    }

    private static func writePendingAudio(_ dict: [UUID: PendingAudio]) {
        let stringDict = dict.reduce(into: [String: PendingAudio]()) { $0[$1.key.uuidString] = $1.value }
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: "MacroMark_PendingAudioIn")
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
    /// Sends an ACK back to the watch on successful SwiftData save (unless we're
    /// on the volatile in-memory store, in which case the watch must keep its copy).
    @MainActor
    private func processAndExport(
        noteId: UUID,
        text: String,
        isAudio: Bool,
        timestamp: Date,
        autoExport: Bool,
        rawTarget: String,
        context: ModelContext
    ) {
        let note = ProcessedNote(text: text, createdAt: timestamp)
        context.insert(note)

        // Save to SwiftData (the durable source of truth)
        do {
            try context.save()
        } catch {
#if DEBUG
            print("MacroMark: SwiftData save failed for note \(noteId): \(error)")
#endif
            // Leave the note in the WAL for retry on next launch.
            // Do NOT send ACK — the watch will re-send.
            return
        }

        // SwiftData save succeeded — note is durably stored.
        // Add to processed set and clear the write-ahead log entry.
        Self.addProcessedNoteID(noteId)
        if isAudio {
            removePendingAudio(id: noteId)
            acknowledgeFileIfDurable(id: noteId)
        } else {
            removePendingProcessing(id: noteId)
            acknowledgeNoteIfDurable(id: noteId)
        }

        // Export to iCloud / third-party targets (best-effort; failures don't undo the ACK)
        guard let target = ExportTarget(rawValue: rawTarget) else {
            _ = iCloudStorageManager.shared.appendText(text, for: timestamp)  // fallback
            return
        }

        if target == .iCloud {
            if iCloudStorageManager.shared.appendText(text, for: timestamp) {
                note.isExported = true
                note.exportTarget = target.rawValue
                try? context.save()
            }
        } else if autoExport {
            if let exportURL = ExportManager.url(for: note, to: target) {
                Task {
                    let success = await UIApplication.shared.open(exportURL)
                    if success {
                        note.isExported = true
                        note.exportTarget = target.rawValue
                        try? context.save()
                    }
                }
            }
        }
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            AppTabView()
                .environment(entitlementManager)
                .environment(storeManager)
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
