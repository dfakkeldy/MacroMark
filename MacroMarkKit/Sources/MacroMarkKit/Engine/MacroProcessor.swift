import Foundation
import CoreLocation
import MapKit

#if canImport(UIKit)
import UIKit
#endif

public struct MacroProcessor {
    @MainActor
    public static func process(text: String, macros: [Macro], latitude: Double? = nil, longitude: Double? = nil) async -> String {
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
        let date = Date()

        let dateString = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        let timeString = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))

        processedText = processedText.replacing("{date}", with: dateString)
        processedText = processedText.replacing("{time}", with: timeString)
        processedText = processedText.replacing("{newline}", with: "\n")
        processedText = processedText.replacing("{tab}", with: "\t")

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
            if let lat = latitude, let lon = longitude {
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
