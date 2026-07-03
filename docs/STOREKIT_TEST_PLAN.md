# StoreKit Test Plan

Last updated: 2026-07-03.

Use this plan for local StoreKit testing before App Store Connect submission. Local StoreKit tests prove MacroMark code paths and UI behavior only; they do not prove App Store Connect products exist, prices are approved, or production purchases work.

Local config:

- StoreKit file: `MacroMarkKit/Configuration.storekit`
- Annual product ID: `com.macromark.subscription.annual`, $9.99/year, 1-month free trial
- Lifetime product ID: `com.macromark.lifetime`, $24.99
- Free tier: unlimited capture and daily-note append, up to 3 custom macros

Before each test, use a clean simulator install or clear the StoreKit test session transactions in Xcode's StoreKit Transaction Manager.

## 1. Annual Purchase And Trial

- [ ] Pass
- [ ] Fail

Steps:

1. Launch the iOS app in a simulator using the MacroMark scheme and local StoreKit configuration.
2. Open the macro manager with no entitlement.
3. Add custom macros until the fourth macro prompts the paywall.
4. Confirm the annual card displays the localized StoreKit price for `com.macromark.subscription.annual`.
5. Confirm the terms copy mentions the annual price and 1-month free trial.
6. Purchase the annual product.
7. Return to macro management.

Expected result:

The purchase succeeds, the paywall dismisses, Pro gates open, and the app still allows capture without making purchase part of the capture flow.

## 2. Annual Renewal And Expiry With Time Acceleration

- [ ] Pass
- [ ] Fail

Steps:

1. Start from a successful annual purchase.
2. In Xcode's StoreKit Transaction Manager, set an accelerated subscription renewal rate.
3. Let the trial and subscription renewal windows advance.
4. Refresh entitlements by relaunching the app or using Restore Purchases.
5. Let the subscription expire in the StoreKit test session.
6. Refresh entitlements again.

Expected result:

While the annual subscription is active, Pro gates stay open. After expiry and entitlement refresh, subscription-only access closes unless lifetime has also been purchased. Capture and daily-note append remain available.

## 3. Lifetime Permanent Entitlement

- [ ] Pass
- [ ] Fail

Steps:

1. Clear local transactions and app data.
2. Trigger the paywall from the fourth custom macro or another Pro-only control.
3. Confirm the lifetime card displays the localized StoreKit price for `com.macromark.lifetime`.
4. Purchase the lifetime product.
5. Relaunch the app.
6. Open the macro manager and folder settings.

Expected result:

The lifetime purchase grants Pro access after purchase and after relaunch. The entitlement should remain available without requiring an active annual subscription.

## 4. Annual And Lifetime Coexistence

- [ ] Pass
- [ ] Fail

Steps:

1. Clear app data and StoreKit transactions.
2. Purchase the annual product.
3. Confirm Pro gates open.
4. Purchase the lifetime product.
5. Expire the annual subscription through the StoreKit test session.
6. Relaunch and refresh entitlements.

Expected result:

The lifetime unlock keeps Pro access active after annual expiry. The app should not duplicate exports, daily notes, or macro state because of the second purchase.

## 5. Restore On Fresh Install

- [ ] Pass
- [ ] Fail

Steps:

1. Purchase annual or lifetime in a StoreKit test session.
2. Delete the app from the simulator.
3. Reinstall and launch the app with the same StoreKit test session.
4. Open the paywall.
5. Tap Restore Purchases.

Expected result:

Restore refreshes entitlements and dismisses the paywall when an active annual or lifetime purchase exists. Free capture remains usable before restore.

## 6. Free-Tier Macro Limit

- [ ] Pass
- [ ] Fail

Steps:

1. Clear local StoreKit transactions and app data.
2. Confirm there is no active entitlement.
3. Add three custom macros.
4. Attempt to add a fourth custom macro.
5. Try editing a default macro.
6. Try changing folder customization settings.
7. Start and save a normal iPhone or Watch capture.

Expected result:

Three custom macros are allowed. The fourth custom macro, default-macro editing, and folder customization show the paywall. Capture and daily-note append never show an upgrade prompt.

## 7. Refund Or Revocation Handling

- [ ] Pass
- [ ] Fail

Steps:

1. Purchase the annual product.
2. Use Xcode's StoreKit Transaction Manager to revoke or refund the transaction if the local tool exposes that action.
3. Keep the app running long enough for `Transaction.updates` to be delivered.
4. Relaunch and refresh entitlements.
5. Repeat with the lifetime product if the Transaction Manager supports revocation for local non-consumables.

Expected result:

Annual revocation should close Pro access after entitlement refresh. Lifetime revocation needs extra attention: `EntitlementManager` listens to `Transaction.updates`, but it also persists a lifetime keychain backstop after a verified purchase. If a local lifetime refund leaves Pro access active, file a follow-up before launch rather than treating refund handling as complete.

## 8. No Upgrade Prompt During Active Capture

- [ ] Pass
- [ ] Fail

Steps:

1. Clear transactions and app data.
2. Start a voice or text capture on iPhone.
3. Save the capture.
4. Start a Watch capture with fake demo text.
5. Let the iPhone process and export the note.
6. Repeat while offline or with the phone unavailable if paired-device testing is available.

Expected result:

No paywall appears during capture, processing, retry, ACK, or daily-note append. Upgrade prompts appear only when the user intentionally enters a Pro-gated macro or folder feature.

## 9. Evidence To Record

- Date, Xcode version, simulator device, and StoreKit test session name.
- Product IDs shown in the Transaction Manager.
- Screenshots of annual purchase, lifetime purchase, restore, and free-tier gate.
- Notes about any mismatch between displayed localized prices and `MacroMarkKit/Configuration.storekit`.
