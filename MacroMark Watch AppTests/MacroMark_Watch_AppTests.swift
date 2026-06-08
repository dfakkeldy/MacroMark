//
//  MacroMark_Watch_AppTests.swift
//  MacroMark Watch AppTests
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import Testing
@testable import MacroMark_Watch_App

struct MacroMark_Watch_AppTests {

    @Test("Test adding note to LocalStore")
    @MainActor
    func testLocalStoreQueueBehavior() async throws {
        let store = LocalStore.shared
        store.pendingNotes = []
        
        store.addNote("Hello world")
        
        #expect(store.pendingNotes.count == 1)
        #expect(store.pendingNotes.first?.text == "Hello world")
    }

}
