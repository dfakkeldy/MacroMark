import Foundation

public enum StoreAccessPolicy {
    /// Temporary testing hiatus for the MacroMark Pro paywall.
    ///
    /// Flip this back to `false` before App Store submission so StoreKit
    /// purchases, restores, refunds, and subscription expiration control access.
    public static let paywallDisabled = true

    public static func isEntitled(
        isSubscribed: Bool,
        hasLifetimeUnlock: Bool,
        simulateEntitled: Bool,
        paywallDisabled: Bool = Self.paywallDisabled
    ) -> Bool {
        paywallDisabled || simulateEntitled || isSubscribed || hasLifetimeUnlock
    }
}
