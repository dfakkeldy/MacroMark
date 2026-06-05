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
            _ = await SFSpeechRecognizer.requestAuthorization()
        }

        setupWatchConnectivity()
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity() {
        let provider = WatchConnectivityProvider.shared
        provider.onNoteReceived = { [container] text, timestamp in
            handleIncomingNote(text: text, timestamp: timestamp, container: container)
        }
        provider.onFileReceived = { [container] url, timestamp in
            handleIncomingAudio(url: url, timestamp: timestamp, container: container)
        }
    }

    // MARK: - Note Processing Pipeline

    /// Shared entry point for text notes (from watch dictation).
    private func handleIncomingNote(text: String, timestamp: Date, container: ModelContainer) {
#if DEBUG
        print("MacroMark iOS Received Note: \(text)")
#endif
        startBackgroundTaskAndProcess(name: "ProcessNote", text: text, timestamp: timestamp, container: container)
    }

    /// Shared entry point for audio files (from watch voice recording).
    private func handleIncomingAudio(url: URL, timestamp: Date, container: ModelContainer) {
#if DEBUG
        print("MacroMark iOS Received Audio File: \(url)")
#endif
        startBackgroundTaskAndProcess(name: "ProcessAudio", url: url, timestamp: timestamp, container: container)
    }

    /// Process a text note through the full pipeline: macros → save → export.
    private func startBackgroundTaskAndProcess(
        name: String,
        text: String? = nil,
        url: URL? = nil,
        timestamp: Date,
        container: ModelContainer
    ) {
#if canImport(UIKit)
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: nil)
#endif

        Task {
            let processedText: String
            let macros: [Macro]

            // Fetch macros on main actor (SwiftData requirement)
            let context = container.mainContext
            let descriptor = FetchDescriptor<Macro>(sortBy: [SortDescriptor(\.createdAt)])
            macros = (try? context.fetch(descriptor)) ?? []

            // Snapshot settings on main actor to avoid races
            let autoExport: Bool
            let rawTarget: String
            await MainActor.run {
                autoExport = UserDefaults.standard.bool(forKey: "autoExportEnabled")
                rawTarget = UserDefaults.standard.string(forKey: "defaultExportTarget") ?? ExportTarget.iCloud.rawValue
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

            // Save and export
            await processAndExport(text: result, timestamp: timestamp, autoExport: autoExport, rawTarget: rawTarget, context: context)

#if canImport(UIKit)
            UIApplication.shared.endBackgroundTask(bgTask)
#endif
        }
    }

    /// Save the processed text to SwiftData and export to the configured target.
    @MainActor
    private func processAndExport(
        text: String,
        timestamp: Date,
        autoExport: Bool,
        rawTarget: String,
        context: ModelContext
    ) {
        let note = ProcessedNote(text: text, createdAt: timestamp)
        context.insert(note)
        try? context.save()

        guard let target = ExportTarget(rawValue: rawTarget) else {
            // Fallback to iCloud
            iCloudStorageManager.shared.appendText(text)
            return
        }

        if target == .iCloud {
            iCloudStorageManager.shared.appendText(text)
            note.isExported = true
            note.exportTarget = target.rawValue
            try? context.save()
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
