//
//  MacroMarkApp.swift
//  MacroMark Watch App
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import SwiftUI

@main
struct MacroMarkWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    init() {
        _ = WatchConnectivityProvider.shared
        _ = LocalStore.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase, initial: true) { _, phase in
                    LocalStore.shared.directDelivery.setForeground(phase == .active)
                }
        }
    }
}
