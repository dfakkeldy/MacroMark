import Foundation
import CoreLocation
import MapKit

#if canImport(UIKit)
import UIKit
#endif

public struct MacroProcessor {
    /// Cache compiled NSRegularExpression instances keyed by macro trigger pattern.
    /// Marked nonisolated(unsafe) because races on this cache are benign — worst case
    /// is compiling the same regex twice, which is a minor perf hit, never a crash.
    private static nonisolated(unsafe) var regexCache: [String: NSRegularExpression] = [:]

    /// Invalidate the compiled regex cache. Call after macros are added, removed, or edited.
    public static func invalidateRegexCache() {
        regexCache.removeAll()
    }

    /// Pre-compiled wrapping-tag cleanup regex (constant pattern, cached once).
    private static let wrapCleanupRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"([\*\_\~]+)\s+(.+?)\s+\1"#, options: [])
    }()

    /// Process text through macro expansion and dynamic variable replacement.
    /// This is CPU-bound work — it is NOT isolated to any actor so callers
    /// should invoke it from the global cooperative pool, not the main actor.
    public static func process(text: String, macros: [Macro], date: Date = Date(), fetchLocation: (() async -> (latitude: Double, longitude: Double)?)? = nil) async -> String {
        var processedText = text

        // 1. Apply trigger macros (with cached regex compilation)
        for macro in macros {
            guard !macro.trigger.isEmpty else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: macro.trigger))\\b"

            let regex: NSRegularExpression
            if let cached = regexCache[pattern] {
                regex = cached
            } else {
                do {
                    let compiled = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                    regexCache[pattern] = compiled
                    regex = compiled
                } catch {
                    print("Failed to compile regex for macro \(macro.trigger): \(error)")
                    continue
                }
            }

            let range = NSRange(processedText.startIndex..., in: processedText)
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: macro.replacement)
            )
        }

        // 2. Evaluate dynamic variables

        // ISO 8601 date (always unambiguous for file naming and logging)
        let dateString = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        // Locale-respecting time (respects user's 12h/24h preference)
        let timeString = date.formatted(date: .omitted, time: .shortened)

        processedText = processedText.replacing("{date}", with: dateString)
        processedText = processedText.replacing("{time}", with: timeString)
        processedText = processedText.replacing("{newline}", with: "\n")
        processedText = processedText.replacing("{tab}", with: "\t")

        // Evaluate {backspace} — deletes the character immediately before it.
        while processedText.contains("{backspace}") {
            if let range = processedText.firstRange(of: "{backspace}") {
                let deleteStart = range.lowerBound == processedText.startIndex
                    ? range.lowerBound
                    : processedText.index(before: range.lowerBound)
                processedText.removeSubrange(deleteStart..<range.upperBound)
            }
        }

        // Evaluate {uuid}
        while processedText.contains("{uuid}") {
            if let range = processedText.firstRange(of: "{uuid}") {
                processedText.replaceSubrange(range, with: UUID().uuidString)
            }
        }

        // Evaluate {clipboard} — must hop to MainActor for UIPasteboard access.
        if processedText.contains("{clipboard}") {
            let clipboardText: String
#if canImport(UIKit)
            clipboardText = await MainActor.run { UIPasteboard.general.string ?? "" }
#else
            clipboardText = ""
#endif
            processedText = processedText.replacing("{clipboard}", with: clipboardText)
        }

        // Evaluate {location}
        if processedText.contains("{location}") {
            var locationString = "Unknown Location"
            if let fetch = fetchLocation, let coords = await fetch() {
                let lat = coords.latitude
                let lon = coords.longitude
                let location = CLLocation(latitude: lat, longitude: lon)
#if os(macOS)
                // MKReverseGeocodingRequest requires macOS 26+. On earlier macOS,
                // fall back to lat/lon string.
                if #available(macOS 26.0, *) {
                    locationString = await reverseGeocode(location: location, fallback: "Lat: \(lat), Lon: \(lon)")
                } else {
                    locationString = "Lat: \(lat), Lon: \(lon)"
                }
#else
                locationString = await reverseGeocode(location: location, fallback: "Lat: \(lat), Lon: \(lon)")
#endif
            }
            processedText = processedText.replacing("{location}", with: locationString)
        }

        // 3. Wrapping tag cleanup
        if let regex = wrapCleanupRegex {
            let range = NSRange(processedText.startIndex..., in: processedText)
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: "$1$2$1"
            )
        }

        return processedText
    }

    /// Reverse-geocode a location to a human-readable string.
    @available(macOS 26.0, *)
    private static func reverseGeocode(location: CLLocation, fallback: String) async -> String {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return fallback
        }
        do {
            let mapItems = try await request.mapItems
            if let placemark = mapItems.first?.placemark {
                let street = placemark.thoroughfare ?? ""
                let subThoroughfare = placemark.subThoroughfare ?? ""
                let city = placemark.locality ?? ""

                if !street.isEmpty && !city.isEmpty {
                    return "\(subThoroughfare) \(street), \(city)".trimmingCharacters(in: .whitespaces)
                } else if !city.isEmpty {
                    return city
                } else {
                    return placemark.name ?? fallback
                }
            }
        } catch {
            print("Reverse geocoding failed: \(error)")
        }
        return fallback
    }
}
