import Foundation
import StoreKit
import Observation
import Security

@MainActor
@Observable
public final class EntitlementManager {
    public static let shared = EntitlementManager()

    public private(set) var isSubscribed = false
    public private(set) var isInTrial = false
    public private(set) var hasLifetimeUnlock = false

    private let lifetimeKeychainKey = "com.macromark.lifetime.keychain"

    private init() {
        updateEntitlements()
        hasLifetimeUnlock = checkKeychainFlag()

        Task {
            for await _ in Transaction.updates {
                updateEntitlements()
                hasLifetimeUnlock = checkLifetimePurchase() || checkKeychainFlag()
            }
        }
    }

    public func updateEntitlements() {
        Task {
            await refreshEntitlements()
        }
    }

    private func refreshEntitlements() async {
        var subscribed = false
        var inTrial = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == ProductIdentifiers.lifetime {
                    subscribed = true
                    hasLifetimeUnlock = true
                    persistKeychainFlag()
                } else if transaction.productID == ProductIdentifiers.annualSubscription {
                    if let expirationDate = transaction.expirationDate,
                       expirationDate > Date() {
                        subscribed = true

                        if let offer = transaction.offer,
                           offer.type == .introductory {
                            inTrial = true
                        }
                    }
                }

            case .unverified:
                continue
            }
        }

        isSubscribed = subscribed
        isInTrial = inTrial
    }

    private func checkLifetimePurchase() -> Bool {
        // Quick check of current entitlements for lifetime
        // The full check happens in refreshEntitlements
        return hasLifetimeUnlock
    }

    // MARK: - Free Tier Helpers

    public var canAddCustomMacro: Bool {
        isSubscribed || hasLifetimeUnlock
    }

    public func customMacroCount(_ count: Int) -> Bool {
        // Free tier: max 3 custom macros
        if isSubscribed || hasLifetimeUnlock {
            return true // unlimited
        }
        return count < 3
    }

    public var canEditDefaultMacros: Bool {
        isSubscribed || hasLifetimeUnlock
    }

    public var canCustomizeFolderStructure: Bool {
        isSubscribed || hasLifetimeUnlock
    }

    // MARK: - Keychain (Lifetime Unlock Persistence)

    private func persistKeychainFlag() {
        guard let data = "lifetime_unlocked".data(using: .utf8) else { return }

        // Remove existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: lifetimeKeychainKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: lifetimeKeychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func checkKeychainFlag() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: lifetimeKeychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              value == "lifetime_unlocked" else {
            return false
        }

        return true
    }
}
