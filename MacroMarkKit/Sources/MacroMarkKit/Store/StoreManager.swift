import Foundation
@preconcurrency import StoreKit
import Observation
import os

@MainActor
@Observable
public final class StoreManager {
    public static let shared = StoreManager()

    public private(set) var products: [Product] = []

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task {
            for await result in Transaction.updates {
                await handleTransaction(result)
            }
        }
    }

    public func loadProducts() async {
        do {
            products = try await Product.products(for: ProductIdentifiers.all)
            products.sort { $0.price < $1.price }
        } catch {
            Logger.store.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                await handleTransaction(verificationResult)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
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
        do {
            try await AppStore.sync()
            await EntitlementManager.shared.refreshEntitlements()
        } catch {
            Logger.store.error("Restore purchases failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
