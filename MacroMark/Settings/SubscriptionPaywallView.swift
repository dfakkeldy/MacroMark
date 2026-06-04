import SwiftUI
import StoreKit
import MacroMarkKit

struct SubscriptionPaywallView: View {
    let reason: MacroManagerView.PaywallReason

    @Environment(StoreManager.self) private var storeManager
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Unlock Full Access")
                    .font(.title)
                    .bold()

                Text(paywallMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 32)

            // Product Cards
            VStack(spacing: 12) {
                ForEach(storeManager.products, id: \.id) { product in
                    ProductCardView(product: product) {
                        Task {
                            await storeManager.purchase(product)
                            await entitlements.refreshEntitlements()
                            if entitlements.isSubscribed {
                                dismiss()
                            }
                        }
                    }
                }

                if storeManager.products.isEmpty {
                    ProgressView("Loading products...")
                }
            }
            .padding(.horizontal)

            // Terms
            VStack(spacing: 8) {
                Button("Restore Purchases") {
                    Task {
                        await storeManager.restorePurchases()
                        await entitlements.refreshEntitlements()
                        if entitlements.isSubscribed {
                            dismiss()
                        }
                    }
                }
                .font(.subheadline)

                Text(subscriptionInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Dismiss
            Button("Maybe Later") {
                dismiss()
            }
            .padding(.bottom, 24)
        }
    }

    private var paywallMessage: String {
        switch reason {
        case .addMacro:
            return "You've reached the 3-macro free limit. Subscribe to add unlimited custom macros."
        case .editDefault:
            return "Editing default macros is a premium feature. Subscribe to customize built-in macros."
        case .folderSettings:
            return "Custom folder structures are a premium feature. Subscribe to organize your notes your way."
        }
    }

    private var subscriptionInfo: String {
        if let annual = storeManager.products.first(where: { $0.id == ProductIdentifiers.annualSubscription }),
           let introOffer = annual.subscription?.introductoryOffer {
            return "\(annual.displayPrice)/year. Includes \(introOffer.period.debugDescription) free trial. Cancel anytime."
        }
        return "Subscribe to unlock all features. Cancel anytime."
    }
}

// MARK: - Product Card

struct ProductCardView: View {
    let product: Product
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.title3)
                        .bold()

                    if let subscriptionInfo = product.subscription {
                        Text("per \(subscriptionInfo.subscriptionPeriod.unit.localizedDescription)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper for subscription period display

extension Product.SubscriptionPeriod.Unit {
    var localizedDescription: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}

#Preview {
    SubscriptionPaywallView(reason: .addMacro)
        .environment(StoreManager.shared)
        .environment(EntitlementManager.shared)
}
