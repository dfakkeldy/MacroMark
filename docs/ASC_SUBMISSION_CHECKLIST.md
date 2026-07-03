# App Store Connect Submission Checklist

Last updated: 2026-07-03.

This checklist separates repository-confirmed facts from Dan-only App Store Connect tasks. Do not claim App Store Connect products, pricing, review status, or production purchases are live until verified in App Store Connect.

## Product IDs And Pricing

| Item | Status | Evidence |
| --- | --- | --- |
| Annual product ID is `com.macromark.subscription.annual` | Confirmed in code | `ProductIdentifiers.swift`, `StoreManager.swift`, `EntitlementManager.swift`, tests, and local StoreKit config |
| Lifetime product ID is `com.macromark.lifetime` | Confirmed in code | `ProductIdentifiers.swift`, `StoreManager.swift`, `EntitlementManager.swift`, tests, and local StoreKit config |
| App target product ID literals | Confirmed absent except centralized references | iOS paywall uses `ProductIdentifiers.annualSubscription` for annual trial copy and `Product.displayPrice` for prices; Watch app and widget have no product ID literals |
| Subscription group ID/reference in code | Confirmed absent | The app loads by product ID and does not use `SubscriptionStoreView(groupID:)` |
| Annual price | Repo configured locally | `$9.99` in `MacroMarkKit/Configuration.storekit`; verify in App Store Connect |
| Annual intro offer | Repo configured locally | 1-month free trial in `MacroMarkKit/Configuration.storekit`; verify in App Store Connect |
| Lifetime standard price | Repo configured locally | `$24.99` in `MacroMarkKit/Configuration.storekit`; verify in App Store Connect |
| Lifetime launch intro | Dan-only ASC task | `$16.99` launch intro must be a temporary/scheduled non-consumable price change, not an introductory offer |
| Simulator free-tier StoreKit gate tests | Verify/follow-up needed | `EntitlementManager.simulateEntitled` returns true on simulator, so simulator-only testing cannot prove unentitled gates |
| Paywall trial copy | Verify/follow-up needed | `SubscriptionPaywallView` uses `introOffer.period.debugDescription`; fail screenshots/review prep if this renders as `P1M` |

## Privacy Labels

Recommended App Privacy posture: answer from Apple's definitions in App Store Connect, not from marketing language. Based on the current repository, MacroMark appears designed to avoid developer-side data collection.

| Question | Recommended answer | Status |
| --- | --- | --- |
| Tracking | No | Confirmed in all privacy manifests: `NSPrivacyTracking` is false and no tracking domains are listed |
| Third-party analytics or ad SDK data | No | Confirmed by source scan; no analytics/ad SDK imports found |
| Data collected by developer | Likely No | Verify in App Store Connect. Notes, macros, settings, queued captures, and exported Markdown stay local or in the user's Apple/iCloud storage; support emails outside the app are separate business records |
| Microphone | Disclose permission purpose, not collected data unless ASC asks differently | Confirmed in `Info.plist` via microphone usage description |
| Speech recognition | Disclose permission purpose, not collected data unless ASC asks differently | Confirmed in `Info.plist` via speech recognition usage description |
| Location | Optional location macro only | Confirmed in `Info.plist` and `LocationManager`; uses When In Use authorization, no Always authorization found |
| User content in iCloud | Explain user-controlled storage | Confirmed in iCloud entitlements and privacy policy; verify App Privacy wording because developer does not receive the data |
| Purchase data | Apple/StoreKit processed | Confirmed StoreKit usage; MacroMark reads entitlement transactions only and does not receive card details |

Suggested review note:

MacroMark records dictated or typed notes, optionally expands a location macro with When In Use permission, and appends user-controlled Markdown daily notes to local/iCloud storage. The app does not run developer-operated note servers, ads, tracking, or analytics.

## Privacy And Terms URLs

| URL | Status |
| --- | --- |
| `https://dfakkeldy.github.io/MacroMark/privacy.html` | Verified HTTP 200 on 2026-07-03 |
| `https://dfakkeldy.github.io/MacroMark/#support` | Root page verified HTTP 200 on 2026-07-03; verify anchor manually before submission |
| `https://dfakkeldy.github.io/MacroMark/` | Verified HTTP 200 on 2026-07-03 |
| Terms page `https://dfakkeldy.github.io/MacroMark/terms.html` | Verified HTTP 200 on 2026-07-03 |

The scanned privacy and terms pages do not hardcode the new `$9.99`, `$16.99`, or `$24.99` prices. If pricing is later added to those pages, update it before submission.

## Accessibility Nutrition Labels

Accessibility labels are an App Store Connect declaration and should be filled only after testing. Apple's evaluation rule is that users must be able to complete all common tasks with the feature before the app claims support.

| Feature | Recommended status |
| --- | --- |
| VoiceOver | Verify on iPhone, iPad, and Watch before declaring. Prior real-world testing found watch image-only capture buttons needing attention, so do not claim full support without a fresh pass. |
| Larger Text | Verify Dynamic Type on capture, macro manager, paywall, settings, and daily log. |
| Dark Interface | Likely supported through SwiftUI/system styling, but verify all major screens. |
| Sufficient Contrast | Verify paywall, watch capture buttons, macro rows, and settings. |
| Differentiate Without Color Alone | Verify macro gates and status indicators. |
| Reduced Motion | Verify there are no essential animations without fallback. |

Dan-only estimate: 30-60 minutes for a focused pass, more if issues are found.

## Age Rating

Recommended questionnaire posture, pending Dan verification:

- No unrestricted web access.
- No social networking or public user-generated content.
- No gambling, contests, alcohol, tobacco, drugs, medical treatment, or mature content features.
- User-created notes are private and not shared through MacroMark.
- In-app purchases are present.
- Location permission is optional and used only for the `{location}` macro.

Expected outcome is likely a low age rating, but the final category must come from the App Store Connect questionnaire.

## Export Compliance

| Item | Status |
| --- | --- |
| `ITSAppUsesNonExemptEncryption` | Confirmed false in `MacroMark/Info.plist` |
| Custom encryption implementation | None found in source scan |
| Apple OS networking/security only | Likely, through StoreKit/iCloud/platform services; verify if new networking or encryption code is added |

Recommended answer: no non-exempt encryption based on current code. Dan should still verify because export compliance is a legal submission answer.

## Build And Version Submission

1. Confirm the processed build is selected on the app version.
2. Attach both IAPs/subscriptions to the first app version before review.
3. Add App Review notes explaining the free capture tier and Pro gates.
4. Include the IAP review screenshots from fake/demo data.
5. Confirm TestFlight smoke testing before review submission.
6. Confirm the lifetime launch intro price schedule before release.
7. Confirm the paywall does not display developer-facing trial text such as `P1M`.
8. Confirm StoreKit gate testing was done on a non-auto-entitled build or physical device, not only the current simulator default.

## Dan-Only Tasks And Estimates

| Task | Estimate |
| --- | --- |
| Paid Apps Agreement, banking, tax, and Small Business Program status check | 10-20 minutes |
| Create subscription group and annual subscription | 20-30 minutes |
| Add annual 1-month free trial | 10-15 minutes |
| Create lifetime non-consumable and schedule $16.99 to $24.99 pricing | 15-25 minutes |
| Prepare and upload IAP review screenshots | 15-30 minutes |
| Attach IAPs to first app version | 5-10 minutes |
| Privacy, age rating, accessibility, export compliance answers | 30-60 minutes |
| Local StoreKit purchase/restore/refund test pass | 45-90 minutes |
| Watch screenshot capture and App Store upload | 45-90 minutes |

## References

- Apple: [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- Apple: [Manage Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels/)
- Apple: [Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- Apple: [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- Apple: [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- Apple: [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
