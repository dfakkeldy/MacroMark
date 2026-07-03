# App Store Connect IAP Setup

Last verified against Apple documentation: 2026-07-03.

This is a Dan-only App Store Connect checklist for MacroMark app ID `6785081218`. The repository can prepare product IDs and local StoreKit testing, but it cannot prove that App Store Connect products exist, are approved, or are attached to a submitted app version.

Canonical product IDs:

| Product | Type | Product ID | Price |
| --- | --- | --- | --- |
| MacroMark Pro Annual | Auto-renewable subscription | `com.macromark.subscription.annual` | $9.99 USD/year with 1-month free trial |
| MacroMark Pro Lifetime | Non-consumable IAP | `com.macromark.lifetime` | $24.99 USD standard, $16.99 USD launch intro |

The app code does not reference a subscription group ID. Create the subscription group in App Store Connect and keep the annual product inside that group; the app loads products by product ID.

## 1. Confirm Agreements And App Record

1. Open App Store Connect.
2. Confirm the app record is MacroMark, app ID `6785081218`.
3. Open Business, Agreements, Tax, and Banking.
4. Confirm the Paid Apps Agreement is active and banking/tax information is complete.
5. If the Paid Apps Agreement is not active, finish it before creating paid IAPs or submitting purchases for review.

## 2. Create The Subscription Group

1. Open App Store Connect.
2. Choose Apps.
3. Select MacroMark.
4. In the sidebar, open Monetization, then Subscriptions.
5. Click the add button to create a subscription group.
6. Set Reference Name to `MacroMark Pro`.
7. Save.

Use one subscription group. MacroMark has one paid entitlement tier, so a single group avoids accidental overlapping subscriptions.

## 3. Create The Annual Subscription

1. In App Store Connect, stay in Apps, MacroMark, Monetization, Subscriptions.
2. Open the `MacroMark Pro` subscription group.
3. Click the add button to create a subscription.
4. Set Reference Name to `MacroMark Pro Annual`.
5. Set Product ID to `com.macromark.subscription.annual`.
6. Set Subscription Duration to `1 Year`.
7. Save.
8. Open Subscription Prices.
9. Set the starting United States price to `$9.99`.
10. Leave generated comparable prices in other storefronts unless deliberately localizing prices.
11. Open Availability and choose the launch storefronts.
12. Add the `en-US` localization:
    - Display Name: `MacroMark Pro Annual`
    - Description: `Unlock unlimited macros, default macro editing, and folder customization for one year. Capture stays free.`
13. Add an App Review screenshot showing the MacroMark paywall with fake/demo content only.

## 4. Add The Annual 1-Month Free Trial

1. In App Store Connect, open Apps, MacroMark, Monetization, Subscriptions.
2. Open the `MacroMark Pro` group.
3. Open `MacroMark Pro Annual`.
4. Open Subscription Prices.
5. Choose Set Up Introductory Offer.
6. Select all launch storefronts.
7. Set the start date to the launch date or the earliest date you want the offer available.
8. Leave the end date empty unless the trial is intentionally time-limited.
9. Choose the `Free` offer type.
10. Choose `1 Month`.
11. Confirm and save.

Do not choose Pay As You Go for the trial. Apple treats free trial, pay up front, and pay as you go as separate introductory offer types.

## 5. Create The Lifetime Non-Consumable

1. Open App Store Connect.
2. Choose Apps.
3. Select MacroMark.
4. In the sidebar, open Monetization, then In-App Purchases.
5. Click the add button.
6. Choose Non-Consumable.
7. Set Reference Name to `MacroMark Pro Lifetime`.
8. Set Product ID to `com.macromark.lifetime`.
9. Save.
10. Open Price Schedule.
11. For launch, set the active price to `$16.99` if the launch intro is still intended to be live.
12. Schedule the standard price change to `$24.99` effective September 1, 2026, or the first business day after launch week.
13. If the launch intro is no longer active, set `$24.99` as the starting price immediately.
14. Add the `en-US` localization:
    - Display Name: `MacroMark Pro Lifetime`
    - Description: `One-time unlock for unlimited macros, default macro editing, and folder customization. Capture stays free.`
15. Add an App Review screenshot showing the lifetime option with fake/demo content only.

Non-consumable IAPs do not use subscription introductory offers. The launch intro must be implemented as a temporary/scheduled App Store Connect price change, then returned to the standard `$24.99` price.

## 6. Attach IAPs To The First App Version

1. Open App Store Connect.
2. Choose Apps.
3. Select MacroMark.
4. Open the app version being submitted for App Review.
5. In the In-App Purchases and Subscriptions section, choose Select or Edit.
6. Select `com.macromark.subscription.annual`.
7. Select `com.macromark.lifetime`.
8. Save the app version.
9. Confirm both products show as included with the version before submission.

First-time IAPs and subscriptions normally need to be submitted with a new app version. Do not assume approved products are available in production until the app version and IAPs are approved.

## 7. Small Business Program Check

1. Confirm the Account Holder is doing the enrollment/status check.
2. Open Apple's Small Business Program page.
3. Confirm Associated Developer Accounts are listed correctly.
4. Confirm the latest Paid Apps Agreement is accepted.
5. Confirm program status by email or App Store Connect business notices.
6. After approval, verify proceeds in Sales and Trends after Apple's stated processing window.

Estimated Dan time: 10-20 minutes if agreements and account ownership are already settled.

## 8. Product ID Audit

Current repository audit:

| Location | `com.macromark.subscription.annual` | `com.macromark.lifetime` | Subscription group reference |
| --- | --- | --- | --- |
| `MacroMarkKit/Sources/MacroMarkKit/Store/ProductIdentifiers.swift` | Present | Present | None |
| `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift` | Loaded through `ProductIdentifiers.all` | Loaded through `ProductIdentifiers.all` | None |
| `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift` | Entitlement check | Entitlement check | None |
| `MacroMark/Settings/SubscriptionPaywallView.swift` | References `ProductIdentifiers.annualSubscription` for trial copy; price uses `displayPrice` | No literal string; card displays `StoreManager` product with `displayPrice` | None |
| `MacroMark Watch App/` | No literal product ID strings found | No literal product ID strings found | None |
| `MacroMarkWidget/` | No literal product ID strings found | No literal product ID strings found | None |
| `MacroMarkKit/Configuration.storekit` | Present at $9.99/year with 1-month free trial | Present at $24.99 | None |
| `MacroMarkKit/Tests/MacroMarkKitTests/MacroMarkKitTests.swift` | Expected by test | Expected by test | None |

Result: code and local StoreKit config match the canonical product IDs. App Store Connect still needs Dan-side verification.

## References

- Apple: [Offer auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/)
- Apple: [Set up introductory offers for auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/)
- Apple: [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
- Apple: [Set a price for an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/)
- Apple: [Schedule price changes for In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/schedule-price-changes-for-in-app-purchases/)
- Apple: [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)
- Apple: [In-App Purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
- Apple: [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
