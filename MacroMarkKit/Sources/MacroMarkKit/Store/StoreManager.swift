import Foundation
@preconcurrency import StoreKit
import Observation

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
            print("Failed to load products: \(error)")
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
            print("Purchase failed: \(error)")
        }
    }

    private func handleTransaction(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            await transaction.finish()
        case .unverified:
            print("Unverified transaction received")
        }
    }

    public func restorePurchases() async {
        purchaseState = .inProgress

        do {
            try await AppStore.sync()
            // After syncing, check whether there are actually restored entitlements
            // rather than unconditionally showing "purchased".
            await EntitlementManager.shared.refreshEntitlements()
            purchaseState = EntitlementManager.shared.isSubscribed || EntitlementManager.shared.hasLifetimeUnlock
                ? .purchased
                : .notStarted
        } catch {
            purchaseState = .failed(error)
            print("Restore purchases failed: \(error)")
        }
    }
}
