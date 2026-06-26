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

    // Note: the inbox's "only the selected day" filtering moved from the in-memory
    // `InboxDateFilter` helper to a day-scoped SwiftData `@Query` predicate built
    // from `DaySelection.dayInterval(_:)`, which is covered by the MacroMarkKit
    // `DaySelectionTests` (dayIntervalCoversOnlySelectedLocalDay).

}
