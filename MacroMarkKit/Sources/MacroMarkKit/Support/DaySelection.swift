import Foundation

public enum DaySelection {
    public static func dayInterval(
        for date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    public static func isFutureDay(
        _ selectedDate: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: selectedDate) > calendar.startOfDay(for: now)
    }

    public static func contains(
        _ date: Date,
        inSelectedDay selectedDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let interval = dayInterval(for: selectedDate, calendar: calendar)
        return date >= interval.start && date < interval.end
    }

    public static func timestamp(
        onSelectedDay selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let selectedComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)

        var combined = DateComponents()
        combined.calendar = calendar
        combined.timeZone = calendar.timeZone
        combined.year = selectedComponents.year
        combined.month = selectedComponents.month
        combined.day = selectedComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second
        combined.nanosecond = timeComponents.nanosecond

        return calendar.date(from: combined) ?? calendar.startOfDay(for: selectedDate)
    }
}
