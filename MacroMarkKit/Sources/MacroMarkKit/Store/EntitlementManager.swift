import Foundation
@preconcurrency import StoreKit
import Observation
import Security

@MainActor
@Observable
public final class EntitlementManager {
    public static let shared = EntitlementManager()

    public private(set) var isSubscribed = false
    public private(set) var isInTrial = false
    public private(set) var hasLifetimeUnlock = false

    public static let maxFreeMacros = 3

    private let lifetimeKeychainKey = "com.macromark.lifetime.keychain"
    private var updatesTask: Task<Void, Never>?

    private init() {
#if DEBUG
        isSubscribed = true
#endif
        hasLifetimeUnlock = checkKeychainFlag()
        scheduleRefresh()

        updatesTask = Task {
            for await _ in Transaction.updates {
                await refreshEntitlements()
                hasLifetimeUnlock = hasLifetimeUnlock || checkKeychainFlag()
            }
        }
    }

    /// Schedule an async entitlement refresh without waiting for the result.
    /// Used at init time and from fire-and-forget contexts.
    private func scheduleRefresh() {
        Task { await refreshEntitlements() }
    }

    /// Refresh entitlements from StoreKit and update published state.
    /// Await this method when callers need the updated state before proceeding.
    public func refreshEntitlements() async {
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

#if !DEBUG
        isSubscribed = subscribed
#endif
        isInTrial = inTrial
    }

    // MARK: - Free Tier Helpers

    public var canAddCustomMacro: Bool {
#if DEBUG
        return true
#else
        isSubscribed || hasLifetimeUnlock
#endif
    }

    public func customMacroCount(_ count: Int) -> Bool {
#if DEBUG
        return true
#else
        if isSubscribed || hasLifetimeUnlock {
            return true
        }
        return count < Self.maxFreeMacros
#endif
    }

    public var canEditDefaultMacros: Bool {
#if DEBUG
        return true
#else
        isSubscribed || hasLifetimeUnlock
#endif
    }

    public var canCustomizeFolderStructure: Bool {
#if DEBUG
        return true
#else
        isSubscribed || hasLifetimeUnlock
#endif
    }

    // MARK: - Keychain (Lifetime Unlock Persistence)

    private func persistKeychainFlag() {
        guard let data = "lifetime_unlocked".data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: lifetimeKeychainKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

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
