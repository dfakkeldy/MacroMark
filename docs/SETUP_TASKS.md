# MacroMark — Xcode Setup Tasks

Complete these steps in order after adding the local SPM package.

> Status update, 2026-07-01: this file is an early project-setup checklist from
> 2026-06-03. Keep it for historical Xcode setup context, but use
> `docs/APP_STORE_READINESS.md` for current App Store/TestFlight release gates.
> The App Store Connect app record now exists as `6785081218`; the remaining
> release work is StoreKit verification, TestFlight upload/distribution,
> screenshots, privacy answers, accessibility labels, and paired-device smoke
> testing.

---

## 1. Add MacroMarkKit Local Package

- [ ] Open `MacroMark.xcodeproj` in Xcode
- [ ] File → Add Package Dependencies → **Add Local…** (bottom-left button)
- [ ] Select the `MacroMarkKit/` folder at the project root
- [ ] In the "Add to Target" sheet, check **MacroMark** (iOS app target)
- [ ] Click "Add Package"

---

## 2. Remove Old Source Files From Target

These files were moved into MacroMarkKit. Remove them from the app target (do NOT delete the files — just uncheck target membership):

- [ ] `MacroMark/Models/Macro.swift` → Select file → File Inspector → Uncheck "MacroMark" target
- [ ] `MacroMark/Engine/MacroProcessor.swift` → Select file → File Inspector → Uncheck "MacroMark" target
- [ ] `MacroMark/Storage/iCloudStorageManager.swift` → Select file → File Inspector → Uncheck "MacroMark" target

---

## 3. Add New Source Files To Target

These new views were created and exist on disk but need Xcode target membership:

- [ ] Drag `MacroMark/Settings/MacroEditView.swift` into the Xcode project navigator (under `MacroMark/Settings/` group)
  - Check "Copy items if needed" → **uncheck** (file is already in the right place)
  - Check **MacroMark** target membership

- [ ] Drag `MacroMark/Settings/SubscriptionPaywallView.swift` into Xcode
  - Same settings as above

- [ ] Drag `MacroMark/Settings/FolderSettingsView.swift` into Xcode
  - Same settings as above

---

## 4. Configure StoreKit Testing

- [ ] Edit Scheme (Product → Scheme → Edit Scheme… or ⌘<)
- [ ] Select **Run** → **Options** tab
- [ ] Under "StoreKit Configuration", select `MacroMarkKit/Configuration.storekit`
- [ ] Close the scheme editor

---

## 5. Verify Build

- [ ] Product → Clean Build Folder (⌘⇧K)
- [ ] Product → Build (⌘B)
- [ ] Fix any compilation errors:

| Error | Fix |
|-------|-----|
| "No such module 'MacroMarkKit'" | Package not added to target — redo Step 1 |
| "Duplicate definition of 'Macro'" | Old `Macro.swift` still in target — redo Step 2 |
| "Cannot find 'MacroEditView'" | File not added to target — redo Step 3 |

---

## 6. Test On Device

- [ ] Run on iPhone (⌘R)
- [ ] Verify macros appear in the list
- [ ] Tap a macro → should open edit view
- [ ] Try adding a 4th custom macro → should show paywall
- [ ] Try editing a default macro (free) → should show paywall
- [ ] Tap "Folder Structure" → should show paywall
- [ ] Run on Apple Watch
- [ ] Verify liquid glass UI elements are rendering correctly
- [ ] Tap the large Microphone button → should start dictation mode
- [ ] Tap the large Keyboard button → should start text entry mode
- [ ] Tap "Today's Daily Log" button → should display daily log

---

## 7. StoreKit Testing (Local)

- [ ] With StoreKit configuration active, test purchasing:
  - Tap a gated feature → Paywall appears
  - Tap the annual or lifetime product → Purchase completes
  - Verify entitlement is granted (lock icons disappear, gates open)
- [ ] Test restore purchases
- [ ] Test trial flow (annual subscription with 1-month free intro offer)

---

## 8. App Store Connect (Before Release)

- [x] Create App ID and listing in App Store Connect (`6785081218`)
- [ ] Create **Auto-Renewable Subscription**: `com.macromark.subscription.annual`
  - Price: $9.99 USD / year
  - Introductory Offer: 1-month free trial
- [ ] Create **Non-Consumable IAP**: `com.macromark.lifetime`
  - Price: $24.99 USD standard price
  - Launch intro: $16.99 USD via App Store Connect temporary/scheduled price change; non-consumables do not support introductory offers
- [ ] Follow the current detailed setup in `docs/ASC_IAP_SETUP.md`
- [ ] Complete App Store privacy answers and Accessibility Nutrition Labels
- [ ] Upload screenshots and metadata
- [ ] Submit a processed TestFlight/App Store build for review

---

*Generated 2026-06-03*
