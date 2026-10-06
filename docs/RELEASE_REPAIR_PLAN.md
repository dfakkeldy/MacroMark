# MacroMark scoped release repair plan

Source re-checked: 2026-10-06, nightly `80455834`. Read-only investigation;
no fixes, purchase sessions, Xcode/simulator work or store operations occurred.
This plan preserves the existing annual/lifetime business model and limits
work to release defects, policy selection and missing test evidence.

## Confirmed current source defects

| Finding | Exact source | Minimal repair proposal | Required evidence |
| --- | --- | --- | --- |
| In-app privacy link absent | No privacy/terms URL or Link in app Swift views. `SubscriptionPaywallView.swift:52–70` contains Restore and terms text only; `MacroManagerView.swift` has no accessible legal section. | Add an always-accessible Privacy link in the Macros/settings surface and Privacy/Terms links on the paywall using existing public URLs. Do not choose a new EULA or rewrite legal terms. | UI traversal from free capture, paywall reachability and both link destinations; verify with VoiceOver/basic accessibility |
| Offer promise ignores eligibility | `SubscriptionPaywallView.swift:94–96` displays free trial whenever `introductoryOffer` exists; no `isEligibleForIntroOffer` query anywhere in source. Apple distinguishes configured offer from customer eligibility. | Query eligibility when products load/change, and show trial promise only for eligible customers and the configured free-trial mode. Show actual annual renewal price to everyone; derive duration from value/unit. | Eligible first customer, ineligible prior-trial customer, no offer, loading/error and price/duration display cases |
| Lifetime cannot revoke | `EntitlementManager.swift:32,38,53–56` loads/ORs/sets the lifetime flag; `refreshEntitlements` resets annual state only at `69–70`. No lifetime clear or revocationDate handling exists. | Handle verified revoked lifetime transactions, clear in-memory access and both synchronizable/legacy keychain records, and prevent the unconditional OR from regranting revoked access. Reconcile launch/restore against verified StoreKit state; preserve legitimate offline access deliberately rather than silently discarding the backstop. | Buy → revoke while app running; revoke while closed → relaunch; restore after revoke; valid lifetime offline/relaunch; annual+lifetime coexistence and repurchase |
| FileTimestamp manifest coverage missing | `DailyLogFilePath.swift:41` requests `.contentModificationDateKey`; all manifests lack FileTimestamp. Package copies its manifest at `Package.swift:23`. | The date key is never consumed and order uses filenames: remove this unused key, then audit remaining listed timestamp APIs, or declare accurate reasons if timestamp access is intentionally retained. Inspect the archive, not repository presence alone. | Existing path traversal/symlink/index-order tests plus final archive manifest placement/combined privacy report |

Apple's current list does not classify `FileManager.attributesOfItem(atPath:)`
or the `.type` key alone as a timestamp API. The symlink-only read at lines
33–35 therefore does not invalidate removing the unused modification-date
key as the minimal source option; linked-source/archive audit still follows.

The lifetime consequence is source-confirmed: after a verified lifetime
purchase sets the flag true, a later refresh without that product never sets
it false. Apple omits refunded/revoked products from current entitlements, so
refresh alone cannot clear this implementation's cached access. Physical
purchase/revocation reproduction has not run; the beta bypass currently masks
visible changes to access.

## Deliberate configuration and unverified checks

- **Beta policy:** `StoreAccessPolicy.swift:4–8` explicitly documents the
  paywall hiatus. `StoreAccessPolicyTests` at `MacroMarkKitTests.swift:231–278`
  asserts the deliberate default and Boolean behavior when disabled. Treat
  selection of paid release policy as a decision gate, not a surprise defect.
  If paid gates are selected, update the policy and its default-policy test
  together; do not silently change the business model or beta access.
- **Simulator policy:** `EntitlementManager.swift:20–26` auto-entitles
  simulators; this is development configuration. Provide an explicit,
  narrowly scoped unentitled test argument/path or use physical StoreKit
  testing. Do not claim default simulator screenshots prove paid gates.
- **Trial formatting:** `period.debugDescription` is source-confirmed debug
  formatting, but actual `P1M` rendering has not been observed. Test readable
  localization; do not label a particular unseen screen output as a defect.
- **Annual expiry/grace:** annual refresh checks expirationDate > now.
  Ordinary expiry is untested; current-entitlements can include billing grace
  periods. Verify ASC grace configuration before calling the grace case a
  present user defect or choosing a policy change.
- **Local fixture:** `MacroMarkKit/Configuration.storekit` is referenced in
  the scheme's LaunchAction (`MacroMark.xcscheme:78–80`). No SKTestSession or
  real purchase test appears in existing suites. Its loadability/product
  response still requires Xcode/StoreKit validation; JSON syntax or matching
  IDs alone cannot establish valid local StoreKit behavior.
- **Core paired capture:** WAL/retry/deduplication code and package coverage
  exist; there is no new paired-device result in this source-only follow-up.
  Root owns sequential simulator/image work. Historical bug-hunt findings are
  not repeated as current defects without reproduction.

## Existing coverage and minimal additions

Current suites cover ProductIdentifiers, two StoreAccessPolicy Boolean tests,
and DailyLogFilePath traversal, symlinks, hidden/non-Markdown filtering and
filename order. They do not test real purchase, restore, revocation, renewal,
trial eligibility or paywall legal links. UI tests check launch and draft
screenshots only.

Keep additions in existing targets: policy and period/eligibility formatting
cases in MacroMarkKitTests where pure; app-hosted StoreKitTest purchase/cache
cases in MacroMarkTests; link and reachable unentitled-paywall cases in
MacroMarkUITests. Use only small concrete constructor/closure seams where
needed to control inputs, not a new service framework. First validate the
local StoreKit fixture; then test real ASC sandbox products after sign-in.

The last draft-head hosted CI at `ffa352e8` succeeded:
[37398381229](https://github.com/dfakkeldy/MacroMark/actions/runs/37398381229),
October 6 01:20Z. iOS build-for-testing and package checks passed;
app-hosted iOS tests were **skipped**. This does not prove purchase behavior.
No local Xcode or simulator command ran in this investigation.

## Official Apple evidence

[Configured introductory offer](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/introductoryoffer)
is distinct from [customer eligibility](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer).
[Current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
exclude revoked/refunded products; [revocationDate](https://developer.apple.com/documentation/storekit/transaction/revocationdate)
identifies revocation. See [privacy/API category definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and
[subscription presentation](https://developer.apple.com/app-store/subscriptions/).
