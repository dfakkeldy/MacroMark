//
//  MacroMarkApp.swift
//  MacroMark
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import SwiftUI
import SwiftData

@main
struct MacroMarkApp: App {
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: Macro.self)
        } catch {
            fatalError("Could not initialize ModelContainer")
        }
        
        let provider = WatchConnectivityProvider.shared
        provider.onNoteReceived = { [container] text, lat, lon in
            print("MacroMark iOS Received Note: \(text)")
            let context = container.mainContext
            
            // Fetch macros
            let descriptor = FetchDescriptor<Macro>(sortBy: [SortDescriptor(\.createdAt)])
            let macros = (try? context.fetch(descriptor)) ?? []
            
            Task { @MainActor in
                // Process text
                let processed = await MacroProcessor.process(text: text, macros: macros, latitude: lat, longitude: lon)
                
                // Save to iCloud
                iCloudStorageManager.shared.appendText(processed)
            }
        }
        
        provider.onFileReceived = { [container] url, lat, lon in
            print("MacroMark iOS Received Audio File: \(url)")
            let context = container.mainContext
            
            // Fetch macros
            let descriptor = FetchDescriptor<Macro>(sortBy: [SortDescriptor(\.createdAt)])
            let macros = (try? context.fetch(descriptor)) ?? []
            
            Task { @MainActor in
                do {
                    let transcript = try await AudioTranscriber.transcribe(fileURL: url)
                    let processed = await MacroProcessor.process(text: transcript, macros: macros, latitude: lat, longitude: lon)
                    iCloudStorageManager.shared.appendText(processed)
                    
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    print("Failed to transcribe audio: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MacroManagerView()
        }
        .modelContainer(container)
    }
}
