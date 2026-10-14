//
//  MacroMarkTests.swift
//  MacroMarkTests
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import Testing
import Foundation
@testable import MacroMark
import MacroMarkKit

struct MacroMarkTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test
    func inboxDateFilterKeepsOnlySelectedDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 12)))
        let sameDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 18)))
        let previousDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 23, minute: 59)))
        let nextDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 26)))

        let notes = [
            ProcessedNote(text: "previous", createdAt: previousDay),
            ProcessedNote(text: "same", createdAt: sameDay),
            ProcessedNote(text: "next", createdAt: nextDay),
        ]

        let filtered = InboxDateFilter.notes(notes, on: selected, calendar: calendar)

        #expect(filtered.map(\.text) == ["same"])
    }

    @Test
    func inboxStatusFilterFindsNeedsAttention() throws {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let notes = [
            ProcessedNote(text: "ok", createdAt: day, exportStatus: .exported),
            ProcessedNote(text: "wait", createdAt: day, exportStatus: .deferred),
            ProcessedNote(text: "bad", createdAt: day, exportStatus: .failed),
        ]

        let filtered = InboxDateFilter.notes(notes, on: day, status: .needsAttention)

        #expect(filtered.map(\.text) == ["wait", "bad"])
    }

    @Test
    func processedNoteIDStoreKeepsRecentIDsAndRefreshesDuplicates() throws {
        let first = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let third = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))

        let refreshed = ProcessedNoteIDStore.inserting(first, into: [first, second], maxCount: 2)
        #expect(refreshed == [second, first])

        let capped = ProcessedNoteIDStore.inserting(third, into: refreshed, maxCount: 2)
        #expect(capped == [first, third])
    }

}
