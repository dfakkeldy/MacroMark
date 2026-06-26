//
//  MacroMark_Watch_AppTests.swift
//  MacroMark Watch AppTests
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import Testing
import Foundation
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

    @Test("Audio is enqueued durably and removed only on ACK")
    @MainActor
    func testAudioQueueDurability() async throws {
        let store = LocalStore.shared

        // Write a throwaway audio file to the temp dir, as the recorder would.
        let id = UUID()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).m4a")
        try Data("fake-audio".utf8).write(to: tmp)

        store.enqueueAudio(from: tmp, id: id, timestamp: Date())

        // It should now be tracked in the durable queue...
        #expect(store.pendingAudio.contains { $0.id == id })
        // ...and the source temp file should have been moved out of harm's way.
        #expect(!FileManager.default.fileExists(atPath: tmp.path))

        // Until the phone ACKs it, the audio note must NOT disappear.
        // Simulate the ACK and confirm it is then removed.
        store.removeAudio(withId: id)
        #expect(!store.pendingAudio.contains { $0.id == id })
    }

}
