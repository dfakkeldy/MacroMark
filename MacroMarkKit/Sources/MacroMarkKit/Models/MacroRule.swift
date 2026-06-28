import Foundation

/// A `Sendable`, value-type snapshot of a macro's trigger/replacement pair.
///
/// `MacroProcessor.process(...)` is `nonisolated` and runs on the cooperative
/// pool (off the main actor), so it must not receive SwiftData `@Model` objects:
/// `Macro` is a reference type bound to a `ModelContext` and is not `Sendable`,
/// and using it off its owning actor is a data race. Callers snapshot their
/// `[Macro]` into `[MacroRule]` on the main actor before processing, so only an
/// immutable value type crosses the isolation boundary.
public struct MacroRule: Sendable, Equatable {
    public let trigger: String
    public let replacement: String

    public init(trigger: String, replacement: String) {
        self.trigger = trigger
        self.replacement = replacement
    }
}
