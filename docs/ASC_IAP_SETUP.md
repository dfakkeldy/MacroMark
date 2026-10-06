# App Store Connect IAP Setup

Re-checked: 2026-10-06. Use [the prepared packet](APP_STORE_PACKET.md) for
current copy, source blockers, and owner decisions. This navigation guide
does not authorize store mutations, prices or agreements.

This is an authorized-operator App Store Connect checklist for MacroMark app ID `6785081218`. Inspect existing products before creating anything. Product IDs and local
StoreKit testing cannot establish that ASC products exist, are approved, or
are attached to a submitted version. The account owner handles agreement,
business, price, territory and legal decisions; an operator can enter the
prepared copy and assets after authorization.

Canonical IDs and **planning prices requiring owner confirmation**:

| Product | Type | Product ID | Price |
| --- | --- | --- | --- |
| MacroMark Pro Annual | Auto-renewable subscription | `com.macromark.subscription.annual` | $9.99 USD/year with 1-month free trial |
| MacroMark Pro Lifetime | Non-consumable IAP | `com.macromark.lifetime` | $24.99 USD standard, $16.99 USD launch intro |

The app code does not reference a subscription group ID. Create the subscription group in App Store Connect and keep the annual product inside that group; the app loads products by product ID.

## 0. Product ID Audit Result

Use these exact IDs in App Store Connect. They intentionally do not use the app bundle ID prefix `com.danfakkeldy.macromark`, and that is okay as long as ASC uses the exact same strings.

| Location | Annual | Lifetime | Subscription group reference |
| --- | --- | --- | --- |
| `MacroMarkKit/Sources/MacroMarkKit/Store/ProductIdentifiers.swift` | `com.macromark.subscription.annual` | `com.macromark.lifetime` | None |
| `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift` | Loaded through `ProductIdentifiers.all` | Loaded through `ProductIdentifiers.all` | None |
| `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift` | Entitlement check | Entitlement check and keychain backstop | None |
| `MacroMark/Settings/SubscriptionPaywallView.swift` | Uses centralized ID for annual trial copy; price comes from `Product.displayPrice` | Product card comes from loaded StoreKit product; price comes from `Product.displayPrice` | None |
| `MacroMark Watch App/` | No product ID strings found | No product ID strings found | None |
| `MacroMarkWidget/` | No product ID strings found | No product ID strings found | None |
| `MacroMarkKit/Configuration.storekit` | $9.99/year, 1-month free trial | $24.99 | None |

Result: code and local StoreKit config match the canonical product IDs. No code-vs-canonical mismatch was found. App Store Connect still needs Dan-side verification.

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
12. If App Store Connect asks for tax category, obtain the owner's approved
    category; do not choose a legal/tax answer from this guide.
13. Add the `en-US` localization:
    - Display Name: `MacroMark Pro Annual`
    - Description: `Unlimited macros and folder customization for one year.`
14. Add an App Review screenshot showing the MacroMark paywall with fake/demo content only.

## 4. Add The Annual 1-Month Free Trial

1. In App Store Connect, open Apps, MacroMark, Monetization, Subscriptions.
2. Open the `MacroMark Pro` group.
3. Open `MacroMark Pro Annual`.
4. Open Subscription Prices.
5. Click View all Subscription Pricing if the introductory-offer controls are not already visible.
6. Choose Set Up Introductory Offer.
7. Select all launch storefronts.
8. Set the start date to the launch date or the earliest date you want the offer available.
9. Leave the end date empty unless the trial is intentionally time-limited.
10. Choose the `Free` offer type.
11. Choose `1 Month`.
12. Confirm and save.

Do not choose Pay As You Go for this trial. Apple treats free trial, pay up front, and pay as you go as separate introductory offer types. MacroMark's intended offer is a 1-month free trial.

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
11. Click Add Pricing.
12. Select United States as the base country or region.
13. For launch week, set the active price to `$16.99` if the launch intro is still intended to be live.
14. Only with an approved future launch window, schedule the return to the
    approved standard price. The old September 1, 2026 date has passed and
    must not be reused; do not invent a replacement date.
15. If no launch discount is authorized, ask the owner to confirm the standard
    starting price; do not choose a price on their behalf.
16. Leave Apple's comparable storefront prices in place unless deliberately localizing prices.
17. If App Store Connect asks for tax category, obtain the owner's approved
    category; do not choose a legal/tax answer from this guide.
18. Add the `en-US` localization:
    - Display Name: `MacroMark Pro Lifetime`
    - Description: `Unlimited macros and folder customization, forever.`
19. Add an App Review screenshot showing the lifetime option with fake/demo content only.

Non-consumable IAPs do not use subscription introductory offers. The launch intro must be implemented as a temporary or scheduled App Store Connect price change, then returned to the standard `$24.99` price. Apple documents In-App Purchase price changes as supporting definite start and end dates or permanent changes, so this is the right ASC mechanism for the $16.99 launch intro.

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

## 7. IAP Review Screenshot Requirements

Add one App Review screenshot for each product:

1. Run MacroMark with fake/demo data only.
2. Open the paywall so the annual and lifetime products are visible.
3. Capture an iPhone or iPad screenshot that clearly shows the product being offered.
4. Upload that image in each product's Review Information section.
5. Add a short review note, for example: `Open the Macros tab, add a fourth custom macro, then choose the annual or lifetime product on the paywall. Capture itself remains free.`

Apple uses these screenshots for review only; they are not displayed on the App Store. The screenshot must meet one of the screenshot specifications supported by MacroMark. If the paywall shows `P1M` or any other developer-facing trial text, fix that before taking the final screenshots.

## 8. Small Business Program Check

1. Confirm the Account Holder is doing the enrollment/status check.
2. Open Apple's Small Business Program page: `https://developer.apple.com/app-store/small-business-program/`.
3. Choose Enroll Now and sign in with the Account Holder Apple Account.
4. Confirm the latest Paid Apps Agreement is accepted in App Store Connect.
5. List all Associated Developer Accounts if any apply.
6. Submit the enrollment or confirm the current enrollment status from Apple's confirmation email/business notices.
7. After approval, verify proceeds in Sales and Trends after Apple's stated processing window.

The Account Holder handles only unresolved agreement/business decisions.
Program enrollment is optional; it does not block basic release preparation.

## References

- Apple: [Offer auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/)
- Apple: [Set up introductory offers for auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/)
- Apple: [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
- Apple: [Set a price for an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/)
- Apple: [Schedule price changes for In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/schedule-price-changes-for-in-app-purchases/)
- Apple: [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)
- Apple: [In-App Purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
- Apple: [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
