# MacroMark: Editable Macros, Subscriptions & Folder Settings

**Date:** 2026-06-03
**Status:** Draft — pending review

## Overview

Three features delivered together:

1. **Editable macro list** — inline editing of trigger words and replacement text, plus drag-to-reorder.
2. **Subscription model** - StoreKit 2 with a 1-month free annual trial ($9.99/yr) or $24.99 lifetime, gating paid features.
3. **Customizable folder structure** — users choose flat, monthly, or yearly+monthly nesting and a custom date format.

Also fixes default macros that use `{newline}{newline}` to use `{newline}`.

---

## 1. New SPM Package: MacroMarkKit

A shared package for types, logic, and storage consumed by the iOS app, Watch app, and Widget extension.

```
MacroMarkKit/
├── Package.swift
├── Sources/MacroMarkKit/
│   ├── Models/
│   │   ├── Macro.swift
│   │   └── FolderSettings.swift
│   ├── Store/
│   │   ├── ProductIdentifiers.swift
│   │   ├── StoreManager.swift
│   │   └── EntitlementManager.swift
│   ├── Engine/
│   │   └── MacroProcessor.swift
│   └── Storage/
│       └── iCloudStorageManager.swift
├── Tests/MacroMarkKitTests/
│   ├── MacroProcessorTests.swift
│   ├── StoreManagerTests.swift
│   └── FolderSettingsTests.swift
```

### 1.1 Package.swift

- Targets iOS 26.0, watchOS 10.0
- Swift 6.2 tools version
- No external dependencies

### 1.2 Models/Macro.swift (moved + extended)

```swift
@Model
final class Macro {
    var trigger: String = ""
    var replacement: String = ""
    var isDefault: Bool = false
    var isDefaultEdited: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
}
```

**New fields:**
- `isDefault` — `true` for the 21 built-in macros. Users can delete defaults but the originals remain available via "Restore Default Macros".
- `isDefaultEdited` — flips to `true` when a paid user edits a default macro's trigger or replacement. Prevents free users from editing defaults.
- `sortOrder` — integer for manual reordering. Macros displayed in `sortOrder` ascending, then `createdAt` ascending.

### 1.3 Models/FolderSettings.swift

```swift
struct FolderSettings: Codable, Equatable {
    enum FolderStructure: String, Codable, CaseIterable {
        case flat
        case monthly
        case yearlyMonthly
    }

    var structure: FolderStructure = .flat
    var dateFormat: String = "yyyy-MM-dd"
}
```

Stored in `UserDefaults` under key `folderSettings` via `@AppStorage` + JSON coding.

**Folder structure examples (date: 2026-06-03):**

| Structure | Path |
|-----------|------|
| `.flat` | `2026-06-03.md` |
| `.monthly` | `2026-06/03.md` |
| `.yearlyMonthly` | `2026/06/03.md` |

**Date format:** `dateFormat` is a Unicode date format string. Default `yyyy-MM-dd` produces `2026-06-03`. Users can change it to e.g. `MM-dd-yyyy` for `06-03-2026`.

---

## 2. Subscription Model (StoreKit 2)

### 2.1 Products

| Product ID | Price | Type | Trial |
|------------|-------|------|-------|
| `com.macromark.subscription.annual` | $9.99/yr | Auto-renewable subscription | 1-month free introductory offer |
| `com.macromark.lifetime` | $24.99 | Non-consumable IAP | $16.99 launch intro via temporary/scheduled App Store Connect price change |

### 2.2 Store/ProductIdentifiers.swift

```swift
enum ProductIdentifiers {
    static let annualSubscription = "com.macromark.subscription.annual"
    static let lifetime = "com.macromark.lifetime"
    static let all: Set<String> = [annualSubscription, lifetime]
}
```

### 2.3 Store/StoreManager.swift

- `@Observable @MainActor` class
- Loads products via `Product.products(for:)` on init
- Exposes `products: [Product]`, `purchaseState: PurchaseState`
- `purchase(_ product: Product) async throws` — uses `product.purchase()`
- Listens for transaction updates via `Transaction.updates`
- Syncs entitlement status after each transaction

### 2.4 Store/EntitlementManager.swift

- `@Observable @MainActor` class
- Checks `Transaction.currentEntitlements` for active annual subscription or lifetime unlock
- `var isSubscribed: Bool` — true if trial, active subscription, or lifetime purchase
- `var isInTrial: Bool` — true during 1-month introductory period
- Stores lifetime unlock in keychain (survives reinstall) via a simple flag

### 2.5 Free Tier Limits

| Action | Free | Paid |
|--------|------|------|
| Use default macros | Yes | Yes |
| Delete default macros | Yes | Yes |
| Reorder macros | Yes | Yes |
| Add custom macros | Max 3 | Unlimited |
| Edit default macro trigger/replacement | No | Yes |
| Edit custom macro trigger/replacement | Yes | Yes |
| Folder structure settings | Flat only | All options |

### 2.6 Paywall Flow

When a free-tier limit is hit, a sheet presents `SubscriptionPaywallView`:

1. Shows current limit message (e.g., "You've reached the 3-macro free limit")
2. Lists the two products with prices and trial info
3. Purchase button → `StoreManager.purchase()` → entitlement check → dismiss sheet
4. Restore purchases button → `AppStore.sync()`
5. Dismiss button returns user to previous state with features gated

---

## 3. Folder Structure in iCloudStorageManager

### 3.1 Changes to iCloudStorageManager

- Reads `FolderSettings` from `@AppStorage`
- `appendText` and `readText` resolve path using `FolderSettings`
- Creates intermediate directories as needed (e.g., `2026/06/` for yearlyMonthly)
- Gated behind `EntitlementManager.isSubscribed` — free users always get `.flat`

### 3.2 Path Resolution

```swift
func fileURL(for date: Date, settings: FolderSettings) -> URL {
    let formatter = Date.FormatStyle.dateTime
    let filename = date.formatted(...) + ".md"  // uses settings.dateFormat

    switch settings.structure {
    case .flat:
        return baseDir.appending(path: filename)
    case .monthly:
        let month = date.formatted(Date.FormatStyle().month(.twoDigits))
        return baseDir.appending(path: "\(date.formatted(...))\(month)").appending(path: filename)
    case .yearlyMonthly:
        let year = date.formatted(Date.FormatStyle().year())
        let month = date.formatted(Date.FormatStyle().month(.twoDigits))
        return baseDir.appending(path: "\(year)").appending(path: "\(month)").appending(path: filename)
    }
}
```

Existing notes remain in their current location. Only new notes use the new structure. No migration — users who change settings accept this trade-off.

---

## 4. MacroManagerView Changes

### 4.1 Inline Editing

Replace the read-only `HStack` rows with editable fields:

- Tap a macro row → navigates to `MacroEditView` (new file) or toggles inline editing
- `MacroEditView` shows `TextField` for trigger and `TextField` for replacement
- Save updates the model. If `isDefault && !isSubscribed`, show paywall instead.

### 4.2 Reordering

- List uses `onMove` modifier with `EditButton`
- Drag handle appears in edit mode
- On move, update `sortOrder` for all affected macros

### 4.3 Subscription Gates

- "Add" button always visible, but saving the 4th custom macro triggers paywall
- Edit button on default macros shows a lock badge for free users; tapping opens paywall
- Folder settings row shows a lock badge for free users

### 4.4 New Views

| View | Purpose |
|------|---------|
| `MacroEditView.swift` | Edit trigger + replacement for a single macro |
| `SubscriptionPaywallView.swift` | Paywall with product cards, purchase/restore buttons |
| `FolderSettingsView.swift` | Folder structure picker + date format field |

---

## 5. Default Macro Fix

Change all `{newline}{newline}` to `{newline}` in the `defaultMacros` computed property:

| Macro | Old Replacement | New Replacement |
|-------|----------------|-----------------|
| Quote | `{newline}{newline}> ` | `{newline}> ` |
| Bullet | `{newline}{newline}- ` | `{newline}- ` |
| Numbered | `{newline}{newline}1. ` | `{newline}1. ` |
| Task | `{newline}{newline}- [ ] ` | `{newline}- [ ] ` |
| New Journal Entry | `{newline}{newline}## {date} at {time}{newline}` | `{newline}## {date} at {time}{newline}` |
| Horizontal Rule | `{newline}{newline}---{newline}` | `{newline}---{newline}` |

The `{newline}` variable already inserts a single `\n`, so `{newline}{newline}` was inserting two blank lines. One is the correct behavior.

---

## 6. MacroMarkApp Changes

- Import `MacroMarkKit`
- On init, call `StoreManager.shared.loadProducts()` to pre-fetch products
- Observe `EntitlementManager.shared.isSubscribed` for the environment

---

## 7. Test Plan

### 7.1 MacroMarkKitTests

- **MacroProcessorTests** — existing tests ported to new package
- **StoreManagerTests** — mock StoreKit session, verify product loading, purchase flow, trial detection
- **FolderSettingsTests** — verify path resolution for all structures, date format rendering

### 7.2 UI Tests

- Add 4th macro → paywall appears
- Edit default macro (free) → paywall appears
- Edit default macro (subscribed) → save succeeds
- Reorder macros → order persists
- Change folder settings → verify file path changes

---

## 8. Build Order

1. **Create MacroMarkKit package** — scaffold SPM package, add to Xcode project
2. **Move shared code** — Macro.swift, MacroProcessor.swift, iCloudStorageManager.swift into package
3. **Add new model fields** — `isDefault`, `isDefaultEdited`, `sortOrder` to Macro
4. **Fix default macros** — `{newline}{newline}` → `{newline}`
5. **Implement StoreKit layer** — ProductIdentifiers, StoreManager, EntitlementManager
6. **Build paywall** — SubscriptionPaywallView
7. **Implement editable macros** — MacroEditView, inline editing in MacroManagerView
8. **Implement folder settings** — FolderSettings model, FolderSettingsView, iCloudStorageManager updates
9. **Add subscription gates** — wire EntitlementManager checks into MacroManagerView
10. **Test** — run unit + UI tests, verify all gates

---

## 9. Open Questions & Assumptions

- Product IDs must be created in App Store Connect before submission. Development uses StoreKit testing config file (`.storekit`).
- Existing notes are not migrated when folder structure changes. This is documented in the UI.
- Watch app continues to use flat storage locally (its storage is transient — notes are sent to iOS immediately).
- Lifetime purchases are tracked via keychain flag + `Transaction.currentEntitlements` check, not a server-side receipt validator. This is appropriate for the $24.99 one-time purchase, but refund/revocation behavior should be tested before public launch because the keychain backstop intentionally preserves a durable unlock.
