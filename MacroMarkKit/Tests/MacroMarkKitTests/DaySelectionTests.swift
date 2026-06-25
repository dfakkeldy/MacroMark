import Foundation
import Testing
@testable import MacroMarkKit

struct DaySelectionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test
    func dayIntervalCoversOnlySelectedLocalDay() throws {
        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 14)))
        let interval = DaySelection.dayInterval(for: selected, calendar: calendar)

        let sameDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 23, minute: 59)))
        let previousDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 23, minute: 59)))
        let nextDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 26)))

        #expect(interval.start == calendar.startOfDay(for: selected))
        #expect(interval.end == calendar.startOfDay(for: nextDay))
        #expect(DaySelection.contains(sameDay, inSelectedDay: selected, calendar: calendar))
        #expect(!DaySelection.contains(previousDay, inSelectedDay: selected, calendar: calendar))
        #expect(!DaySelection.contains(nextDay, inSelectedDay: selected, calendar: calendar))
    }

    @Test
    func futureDetectionComparesByDay() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 23)))
        let laterToday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 23, minute: 30)))
        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 26, hour: 1)))

        #expect(!DaySelection.isFutureDay(laterToday, relativeTo: now, calendar: calendar))
        #expect(DaySelection.isFutureDay(tomorrow, relativeTo: now, calendar: calendar))
    }

    @Test
    func timestampUsesSelectedDateAndCurrentTime() throws {
        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 9)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 16, minute: 30, second: 45)))

        let timestamp = DaySelection.timestamp(onSelectedDay: selected, now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: timestamp)

        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 4)
        #expect(components.hour == 16)
        #expect(components.minute == 30)
        #expect(components.second == 45)
    }
}
