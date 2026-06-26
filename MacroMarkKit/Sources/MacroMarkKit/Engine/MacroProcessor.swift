import Foundation
import CoreLocation
import MapKit
import os

#if canImport(UIKit)
import UIKit
#endif

public struct MacroProcessor {
    /// Cache compiled NSRegularExpression instances keyed by macro trigger pattern.
    /// Synchronized with an unfair lock because `process(...)` is non-isolated and
    /// can be invoked concurrently from the cooperative pool; a Swift `Dictionary`
    /// is not safe under concurrent mutation.
    private static let regexCache = OSAllocatedUnfairLock<[String: NSRegularExpression]>(initialState: [:])

    /// Invalidate the compiled regex cache. Call after macros are added, removed, or edited.
    public static func invalidateRegexCache() {
        regexCache.withLock { $0.removeAll() }
    }

    /// Sentinels (Unicode private-use scalars) that wrap every macro replacement so
    /// the wrapping-tag cleanup can act ONLY on markers a macro inserted, never on
    /// `*`/`_`/`~` the user dictated (e.g. "3 * 4 * 5"). Stripped before returning.
    private static let macroOpen = "\u{E000}"
    private static let macroClose = "\u{E001}"

    /// Pre-compiled wrapping-tag cleanup regex (constant pattern, cached once).
    /// Matches a sentinel-wrapped marker run, spaces, content, spaces, then the same
    /// sentinel-wrapped marker run — so only macro-inserted emphasis collapses
    /// ("⟨**⟩ word ⟨**⟩" → "**word**"). User-typed markers carry no sentinels.
    private static let wrapCleanupRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\u{E000}([\\*\\_\\~]+)\u{E001}\\s+(.+?)\\s+\u{E000}\\1\u{E001}",
            options: []
        )
    }()

    /// Process text through macro expansion and dynamic variable replacement.
    /// This is CPU-bound work — it is NOT isolated to any actor so callers
    /// should invoke it from the global cooperative pool, not the main actor.
    public static func process(text: String, macros: [MacroRule], date: Date = Date(), fetchLocation: (@Sendable () async -> (latitude: Double, longitude: Double)?)? = nil) async -> String {
        var processedText = text

        // 1. Apply trigger macros (with cached regex compilation)
        for macro in macros {
            guard !macro.trigger.isEmpty else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: macro.trigger))\\b"

            let regex: NSRegularExpression
            if let cached = regexCache.withLock({ $0[pattern] }) {
                regex = cached
            } else {
                do {
                    let compiled = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                    regexCache.withLock { $0[pattern] = compiled }
                    regex = compiled
                } catch {
                    Logger.engine.error("Failed to compile regex for macro \(macro.trigger): \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }

            // Wrap the replacement in sentinels so the wrapping-tag cleanup can tell
            // macro-inserted markers apart from ones the user dictated.
            let template = Self.macroOpen
                + NSRegularExpression.escapedTemplate(for: macro.replacement)
                + Self.macroClose
            let range = NSRange(processedText.startIndex..., in: processedText)
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: template
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
#if os(iOS) || os(tvOS) || os(visionOS)
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
#if os(macOS) || os(watchOS)
                // MKReverseGeocodingRequest requires macOS/watchOS 26+. On
                // earlier OSes, fall back to a deterministic lat/lon string.
                if #available(macOS 26.0, watchOS 26.0, *) {
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

        // 3. Wrapping tag cleanup — collapse "⟨**⟩ word ⟨**⟩" to "**word**", but ONLY
        // for macro-inserted (sentinel-wrapped) markers, never for `*`/`_`/`~` the
        // user dictated. Then strip every sentinel so non-emphasis macro insertions
        // (e.g. "# ") and the surrounding text come out clean.
        if let regex = wrapCleanupRegex {
            let range = NSRange(processedText.startIndex..., in: processedText)
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: "$1$2$1"
            )
        }
        processedText = processedText
            .replacing(Self.macroOpen, with: "")
            .replacing(Self.macroClose, with: "")

        return processedText
    }

    /// Reverse-geocode a location to a human-readable string.
    @available(iOS 26.0, watchOS 26.0, macOS 26.0, *)
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
            Logger.engine.error("Reverse geocoding failed: \(error.localizedDescription, privacy: .public)")
        }
        return fallback
    }
}
