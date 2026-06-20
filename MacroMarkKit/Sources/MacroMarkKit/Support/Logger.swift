import Foundation
import os

/// Centralized loggers for MacroMarkKit. Uses `os.Logger` (unified logging) so
/// that log levels are honored at runtime and no internal details are written to
/// stdout in release builds. Replaces ad-hoc `print()` calls throughout the kit.
extension Logger {
    /// Reverse-DNS subsystem shared by every MacroMark target.
    static let subsystem = "com.macromark"

    /// Engine: macro processing, regex compilation, transcription helpers.
    static let engine = Logger(subsystem: subsystem, category: "engine")

    /// Storage: iCloud append/read, file coordination, daily-note materialization.
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// Store: StoreKit product loading, purchases, entitlement persistence.
    static let store = Logger(subsystem: subsystem, category: "store")
}
