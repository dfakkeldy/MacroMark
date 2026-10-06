import Foundation

public enum StoreAccessPolicy {
    /// The approved free launch gives every user full macro and folder access.
    /// Existing StoreKit ownership and product identifiers remain compatible;
    /// no purchase is required to use the app.
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
