import Foundation
@preconcurrency import StoreKit
import Observation
import os

public enum PurchaseState {
    case notStarted
    case inProgress
    case purchased
    case failed(Error)
}

@MainActor
@Observable
public final class StoreManager {
    public static let shared = StoreManager()

    public private(set) var products: [Product] = []
    public private(set) var purchaseState: PurchaseState = .notStarted
    public private(set) var isLoadingProducts = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task {
            for await result in Transaction.updates {
                await handleTransaction(result)
            }
        }
    }

    public func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: ProductIdentifiers.all)
            products.sort { $0.price < $1.price }
        } catch {
            Logger.store.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func purchase(_ product: Product) async {
        purchaseState = .inProgress

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                await handleTransaction(verificationResult)
                purchaseState = .purchased

            case .userCancelled:
                purchaseState = .notStarted

            case .pending:
                purchaseState = .inProgress

            @unknown default:
                purchaseState = .notStarted
            }
        } catch {
            purchaseState = .failed(error)
            Logger.store.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleTransaction(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            // Persist entitlement before finishing — if the app crashes between
            // finish() and persistence, the purchase would be permanently lost.
            await EntitlementManager.shared.refreshEntitlements()
            await transaction.finish()
        case .unverified:
            Logger.store.notice("Unverified transaction received")
        }
    }

    public func restorePurchases() async {
        purchaseState = .inProgress

        do {
            try await AppStore.sync()
            // After syncing, check whether there are actually restored entitlements
            // rather than unconditionally showing "purchased".
            await EntitlementManager.shared.refreshEntitlements()
            purchaseState = EntitlementManager.shared.isEntitled
                ? .purchased
                : .notStarted
        } catch {
            purchaseState = .failed(error)
            Logger.store.error("Restore purchases failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
