//
//  MacroMarkApp.swift
//  MacroMark Watch App
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import SwiftUI

@main
struct MacroMarkWatchApp: App {
    init() {
        _ = WatchConnectivityProvider.shared
        _ = LocalStore.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
