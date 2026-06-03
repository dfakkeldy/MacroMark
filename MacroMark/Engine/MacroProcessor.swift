import Foundation
import UIKit
import CoreLocation
import MapKit

struct MacroProcessor {
    @MainActor
    static func process(text: String, macros: [Macro], latitude: Double? = nil, longitude: Double? = nil) async -> String {
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
        
        processedText = processedText.replacingOccurrences(of: "{date}", with: dateString)
        processedText = processedText.replacingOccurrences(of: "{time}", with: timeString)
        processedText = processedText.replacingOccurrences(of: "{newline}", with: "\n")
        processedText = processedText.replacingOccurrences(of: "{tab}", with: "\t")
        
        // Evaluate {uuid}
        while processedText.contains("{uuid}") {
            // Only replace the first occurrence so each {uuid} gets a unique identifier if used multiple times
            if let range = processedText.range(of: "{uuid}") {
                processedText.replaceSubrange(range, with: UUID().uuidString)
            }
        }
        
        // Evaluate {clipboard}
        if processedText.contains("{clipboard}") {
            let clipboardText = UIPasteboard.general.string ?? ""
            processedText = processedText.replacingOccurrences(of: "{clipboard}", with: clipboardText)
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
            processedText = processedText.replacingOccurrences(of: "{location}", with: locationString)
        }
        
        // 3. Wrapping tag cleanup
        // e.g., "* bold *" -> "*bold*"
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
