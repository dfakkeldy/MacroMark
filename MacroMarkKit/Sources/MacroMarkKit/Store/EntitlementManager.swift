import Foundation
@preconcurrency import StoreKit
import Observation
import Security

@MainActor
@Observable
public final class EntitlementManager {
    public static let shared = EntitlementManager()

    public private(set) var isSubscribed = false
    public private(set) var hasLifetimeUnlock = false

    public static let maxFreeMacros = 3

    /// Runtime flag for development/testing. Set via launch argument
    /// `-MacroMarkSimulateEntitled` in the scheme editor (Run → Arguments).
    /// Safer than compile-time `#if DEBUG` or sandbox-receipt heuristics
    /// because it cannot leak into distribution builds.
    public private(set) var simulateEntitled: Bool = {
#if targetEnvironment(simulator)
        return true
#else
        return ProcessInfo.processInfo.arguments.contains("-MacroMarkSimulateEntitled")
#endif
    }()

    private let lifetimeKeychainKey = "com.macromark.lifetime.keychain"
    private var updatesTask: Task<Void, Never>?

    private init() {
        hasLifetimeUnlock = checkKeychainFlag()
        scheduleRefresh()

        updatesTask = Task {
            for await _ in Transaction.updates {
                await refreshEntitlements()
                hasLifetimeUnlock = hasLifetimeUnlock || checkKeychainFlag()
            }
        }
    }

    private func scheduleRefresh() {
        Task { await refreshEntitlements() }
    }

    public func refreshEntitlements() async {
        var subscribed = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == ProductIdentifiers.lifetime {
                    subscribed = true
                    hasLifetimeUnlock = true
                    await persistKeychainFlag()
                } else if transaction.productID == ProductIdentifiers.annualSubscription {
                    if let expirationDate = transaction.expirationDate,
                       expirationDate > Date() {
                        subscribed = true
                    }
                }

            case .unverified:
                continue
            }
        }

        if !simulateEntitled {
            isSubscribed = subscribed
        }
    }

    // MARK: - Entitlement Checks

    /// Single source of truth for all entitlement-gated features.
    public var isEntitled: Bool {
        StoreAccessPolicy.isEntitled(
            isSubscribed: isSubscribed,
            hasLifetimeUnlock: hasLifetimeUnlock,
            simulateEntitled: simulateEntitled
        )
    }

    public var canEditDefaultMacros: Bool {
        isEntitled
    }

    public var canCustomizeFolderStructure: Bool {
        isEntitled
    }

    // MARK: - Keychain (Lifetime Unlock Persistence)

    /// Runs keychain operations off the main actor to avoid blocking UI.
    /// Adds `kSecAttrSynchronizable` so the lifetime flag iCloud-syncs across
    /// the user's devices as a durable backstop when StoreKit is unavailable.
    private func persistKeychainFlag() async {
        guard let data = "lifetime_unlocked".data(using: .utf8) else { return }

        await Task.detached {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: self.lifetimeKeychainKey,
                kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: self.lifetimeKeychainKey,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }.value
    }

    private func checkKeychainFlag() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: lifetimeKeychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              value == "lifetime_unlocked" else {
            // One-time migration: if we don't find a synchronizable item, check
            // for a pre-existing non-synchronized item (from before this fix).
            return checkKeychainFlagWithoutSync()
        }

        return true
    }

    /// Fallback query for pre-existing non-synchronized keychain items. If found,
    /// re-persist it with the synchronizable flag so this migration runs only once.
    private func checkKeychainFlagWithoutSync() -> Bool {
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

        // Migration: persist with synchronizable flag, delete old non-sync item.
        Task { await persistKeychainFlag() }
        return true
    }
}
