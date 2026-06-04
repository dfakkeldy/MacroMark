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
            resolvedContainer = try ModelContainer(for: Macro.self)
        } catch {
            print("Failed to initialize ModelContainer: \(error). Falling back to in-memory store.")
            if let memoryContainer = try? ModelContainer(
                for: Macro.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) {
                resolvedContainer = memoryContainer
            } else {
                fatalError("Could not initialize any ModelContainer: \(error)")
            }
            _containerError = State(initialValue: error.localizedDescription)
        }
        container = resolvedContainer

        // Pre-load StoreKit products
        Task {
            await StoreManager.shared.loadProducts()
        }

        let provider = WatchConnectivityProvider.shared
        provider.onNoteReceived = { [container] text, timestamp in
            #if DEBUG
            print("MacroMark iOS Received Note: \(text)")
            #endif
            let context = container.mainContext

            let descriptor = FetchDescriptor<Macro>(sortBy: [SortDescriptor(\.createdAt)])
            let macros = (try? context.fetch(descriptor)) ?? []

            // MacroProcessor.process is CPU-bound — run off the main actor.
            #if canImport(UIKit)
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "ProcessNote", expirationHandler: nil)
            #endif

            Task {
                let processed = await MacroProcessor.process(text: text, macros: macros, date: timestamp) {
                    if let location = await LocationManager.shared.getCurrentLocation() {
                        return (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    }
                    return nil
                }
                iCloudStorageManager.shared.appendText(processed)

                #if canImport(UIKit)
                UIApplication.shared.endBackgroundTask(bgTask)
                #endif
            }
        }

        provider.onFileReceived = { [container] url, timestamp in
            #if DEBUG
            print("MacroMark iOS Received Audio File: \(url)")
            #endif
            let context = container.mainContext

            let descriptor = FetchDescriptor<Macro>(sortBy: [SortDescriptor(\.createdAt)])
            let macros = (try? context.fetch(descriptor)) ?? []

            // AudioTranscriber.transcribe and MacroProcessor.process are CPU/IO-bound —
            // run off the main actor.
            #if canImport(UIKit)
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "ProcessAudio", expirationHandler: nil)
            #endif

            Task {
                do {
                    let transcript = try await AudioTranscriber.transcribe(fileURL: url)
                    let processed = await MacroProcessor.process(text: transcript, macros: macros, date: timestamp) {
                        if let location = await LocationManager.shared.getCurrentLocation() {
                            return (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                        }
                        return nil
                    }
                    iCloudStorageManager.shared.appendText(processed)

                    try? FileManager.default.removeItem(at: url)
                } catch {
                    #if DEBUG
                    print("Failed to transcribe audio: \(error)")
                    #endif
                }

                #if canImport(UIKit)
                UIApplication.shared.endBackgroundTask(bgTask)
                #endif
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MacroManagerView()
                .environment(entitlementManager)
                .environment(storeManager)
                .overlay(alignment: .top) {
                    if let error = containerError {
                        Text("Storage error: \(error). Using temporary storage — changes may not be saved.")
                            .font(.caption)
                            .foregroundStyle(.white)
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
