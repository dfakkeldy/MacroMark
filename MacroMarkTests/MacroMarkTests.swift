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

}
