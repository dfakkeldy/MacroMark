import Foundation

/// How the watch captures user input. Stored in `@AppStorage` via `.rawValue`
/// so the raw strings are centralized here rather than scattered in switch
/// statements and string comparisons.
public enum CaptureMode: String, CaseIterable {
    case audio = "audio"
    case system = "system"
}
