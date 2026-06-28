import Foundation

public enum AppRoute {
    public static let scheme = "macromark"

    public static var instantCaptureURL: URL {
        URL(string: "\(scheme)://capture/instant")!
    }

    public static var systemCaptureURL: URL {
        URL(string: "\(scheme)://capture/system")!
    }

    public static func dailyLogURL(date: Date? = nil, calendar: Calendar = .current) -> URL {
        guard let date else {
            return URL(string: "\(scheme)://daily-log")!
        }

        let normalizedDate = calendar.startOfDay(for: date)
        let dateString = formattedRouteDate(for: normalizedDate, calendar: calendar)
        var components = URLComponents(string: "\(scheme)://daily-log")
        components?.queryItems = [URLQueryItem(name: "date", value: dateString)]
        return components?.url ?? URL(string: "\(scheme)://daily-log")!
    }

    public static func appendTextURL(_ text: String) -> URL {
        var components = URLComponents(string: "\(scheme)://append")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url ?? URL(string: "\(scheme)://append")!
    }

    private static func formattedRouteDate(for date: Date, calendar: Calendar) -> String {
        let normalizedDate = calendar.startOfDay(for: date)
        return normalizedDate.formatted(.iso8601.year().month().day())
    }
}
