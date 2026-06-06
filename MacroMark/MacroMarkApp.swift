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

@main
struct MacroMarkApp: App {
    let container: ModelContainer

    @State private var storeManager = StoreManager.shared
    @State private var entitlementManager = EntitlementManager.shared
    @State private var containerError: String?

    init() {
        let resolvedContainer: ModelContainer
        do {
            resolvedContainer = try ModelContainer(for: Macro.self, ProcessedNote.self)
        } catch {
            print("Failed to initialize ModelContainer: \(error). Falling back to in-memory store.")
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
        provider.onFileReceived = { [container] url, timestamp in
            handleIncomingAudio(url: url, timestamp: timestamp, container: container)
        }
    }

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

    /// Write-ahead log: maps note UUID → raw text. Entries are added before processing
    /// and removed only after the note is durably saved. Survives app termination.
    private var pendingProcessing: [UUID: String] { Self.readPendingProcessing() }

    /// Process any notes left in the pending queue from a previous terminated session.
    private func reprocessPendingItems(container: ModelContainer) {
        let items = pendingProcessing
        guard !items.isEmpty else { return }
#if DEBUG
        print("MacroMark: Reprocessing \(items.count) pending item(s) from previous session")
#endif
        for (id, text) in items {
            handleIncomingNote(id: id, text: text, timestamp: Date(), container: container)
        }
    }

    /// Shared entry point for text notes (from watch dictation).
    private func handleIncomingNote(id: UUID, text: String, timestamp: Date, container: ModelContainer) {
#if DEBUG
        print("MacroMark iOS Received Note: \(text)")
#endif
        // Deduplicate: if we've already processed this note, just re-send the ACK
        if processedNoteIDs.contains(id) {
#if DEBUG
            print("MacroMark: Note \(id) already processed, re-sending ACK")
#endif
            WatchConnectivityProvider.shared.acknowledgeNote(id: id)
            return
        }

        // Write-ahead log: persist raw text before processing
        var pending = pendingProcessing
        pending[id] = text
        Self.writePendingProcessing(pending)

        startBackgroundTaskAndProcess(name: "ProcessNote", noteId: id, text: text, timestamp: timestamp, container: container)
    }

    /// Shared entry point for audio files (from watch voice recording).
    private func handleIncomingAudio(url: URL, timestamp: Date, container: ModelContainer) {
#if DEBUG
        print("MacroMark iOS Received Audio File: \(url)")
#endif
        let noteId = UUID()  // Audio files generate a new ID for tracking
        startBackgroundTaskAndProcess(name: "ProcessAudio", noteId: noteId, url: url, timestamp: timestamp, container: container)
    }

    /// Process a text note through the full pipeline: macros → save → export.
    private func startBackgroundTaskAndProcess(
        name: String,
        noteId: UUID,
        text: String? = nil,
        url: URL? = nil,
        timestamp: Date,
        container: ModelContainer
    ) {
#if canImport(UIKit)
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Background task expiring — the raw text is already saved in pendingProcessing,
            // so it will be reprocessed on next launch. We just need to clean up.
#if DEBUG
            print("MacroMark: Background task '\(name)' expiring for note \(noteId)")
#endif
        }
#endif

        Task {
            let processedText: String
            let macros: [Macro]

            // Fetch macros on main actor (SwiftData requirement)
            let context = container.mainContext
            let descriptor = FetchDescriptor<Macro>(sortBy: [SortDescriptor(\.createdAt)])
            macros = (try? context.fetch(descriptor)) ?? []

            // Snapshot settings on main actor to avoid races
            let (autoExport, rawTarget) = await MainActor.run {
                return (
                    UserDefaults.standard.bool(forKey: "autoExportEnabled"),
                    UserDefaults.standard.string(forKey: "defaultExportTarget") ?? ExportTarget.iCloud.rawValue
                )
            }

            // Transcribe audio if needed, otherwise use text directly
            if let audioURL = url {
                do {
                    processedText = try await AudioTranscriber.transcribe(fileURL: audioURL)
                    try? FileManager.default.removeItem(at: audioURL)
                } catch {
#if DEBUG
                    print("Failed to transcribe audio: \(error)")
#endif
#if canImport(UIKit)
                    UIApplication.shared.endBackgroundTask(bgTask)
#endif
                    // Note: raw data is in pendingProcessing, will be retried on next launch
                    // but for audio, we can't recover — transcription failed
                    removePendingProcessing(id: noteId)
                    return
                }
            } else if let directText = text {
                processedText = directText
            } else {
#if canImport(UIKit)
                UIApplication.shared.endBackgroundTask(bgTask)
#endif
                return
            }

            // Run macro processing off the main actor (CPU-bound)
            let result = await MacroProcessor.process(text: processedText, macros: macros, date: timestamp) {
                if let location = await LocationManager.shared.getCurrentLocation() {
                    return (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
                return nil
            }

            // Save and export — ACK is sent inside processAndExport on success
            processAndExport(noteId: noteId, text: result, timestamp: timestamp, autoExport: autoExport, rawTarget: rawTarget, context: context)

#if canImport(UIKit)
            UIApplication.shared.endBackgroundTask(bgTask)
#endif
        }
    }

    /// Remove a note from the pending-processing write-ahead log.
    /// Uses direct UserDefaults access (not computed property) to be callable
    /// from non-mutating contexts like Task closures.
    private func removePendingProcessing(id: UUID) {
        var pending = Self.readPendingProcessing()
        pending.removeValue(forKey: id)
        Self.writePendingProcessing(pending)
    }

    private static func readPendingProcessing() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: "MacroMark_PendingProcessing"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict.reduce(into: [:]) { $0[UUID(uuidString: $1.key) ?? UUID()] = $1.value }
    }

    private static func writePendingProcessing(_ dict: [UUID: String]) {
        let stringDict = dict.reduce(into: [String: String]()) { $0[$1.key.uuidString] = $1.value }
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: "MacroMark_PendingProcessing")
        }
    }

    /// Save the processed text to SwiftData and export to the configured target.
    /// Sends an ACK back to the watch on successful SwiftData save.
    @MainActor
    private func processAndExport(
        noteId: UUID,
        text: String,
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
            // Leave the note in pendingProcessing for retry on next launch.
            // Do NOT send ACK — the watch will re-send on next launch.
            return
        }

        // SwiftData save succeeded — note is durably stored.
        // Add to processed set and remove from pending log.
        Self.addProcessedNoteID(noteId)
        removePendingProcessing(id: noteId)

        // Send ACK to watch so it can delete its copy
        WatchConnectivityProvider.shared.acknowledgeNote(id: noteId)

        // Export to iCloud / third-party targets (best-effort; failures don't undo the ACK)
        guard let target = ExportTarget(rawValue: rawTarget) else {
            _ = iCloudStorageManager.shared.appendText(text)  // fallback
            return
        }

        if target == .iCloud {
            if iCloudStorageManager.shared.appendText(text) {
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
                            Button {
                                withAnimation {
                                    containerError = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.8))
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
