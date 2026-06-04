import Foundation
import CoreLocation
import MapKit

#if canImport(UIKit)
import UIKit
#endif

public struct MacroProcessor {
    /// Process text through macro expansion and dynamic variable replacement.
    /// This is CPU-bound work — it is NOT isolated to any actor so callers
    /// should invoke it from the global cooperative pool, not the main actor.
    public static func process(text: String, macros: [Macro], date: Date = Date(), fetchLocation: (() async -> (latitude: Double, longitude: Double)?)? = nil) async -> String {
        var processedText = text

        // 1. Apply trigger macros
        for macro in macros {
            guard !macro.trigger.isEmpty else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: macro.trigger))\\b"
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let range = NSRange(processedText.startIndex..., in: processedText)
                processedText = regex.stringByReplacingMatches(
                    in: processedText,
                    options: [],
                    range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: macro.replacement)
                )
            } catch {
                print("Failed to compile regex for macro \(macro.trigger): \(error)")
            }
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
        // Useful for macros that remove a preceding newline (e.g., ending a hashtag).
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

        // Evaluate {clipboard}
        if processedText.contains("{clipboard}") {
            #if canImport(UIKit)
            let clipboardText = UIPasteboard.general.string ?? ""
            #else
            let clipboardText = ""
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
                if let request = MKReverseGeocodingRequest(location: location) {
                    do {
                        let mapItems = try await request.mapItems
                        if let placemark = mapItems.first?.placemark {
                            let street = placemark.thoroughfare ?? ""
                            let subThoroughfare = placemark.subThoroughfare ?? ""
                            let city = placemark.locality ?? ""

                            if !street.isEmpty && !city.isEmpty {
                                locationString = "\(subThoroughfare) \(street), \(city)".trimmingCharacters(in: .whitespaces)
                            } else if !city.isEmpty {
                                locationString = city
                            } else {
                                locationString = placemark.name ?? "Lat: \(lat), Lon: \(lon)"
                            }
                        }
                    } catch {
                        print("Reverse geocoding failed: \(error)")
                        locationString = "Lat: \(lat), Lon: \(lon)"
                    }
                }
            }
            processedText = processedText.replacing("{location}", with: locationString)
        }

        // 3. Wrapping tag cleanup
        do {
            let regex = try NSRegularExpression(pattern: #"([\*\_\~]+)\s+(.+?)\s+\1"#, options: [])
            let range = NSRange(processedText.startIndex..., in: processedText)
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: "$1$2$1"
            )
        } catch {
            print("Failed regex wrap cleanup")
        }

        return processedText
    }
}
