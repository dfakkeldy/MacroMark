# MacroMark App Store Readiness

Re-checked: 2026-10-06. This audit covers source, GitHub checks and shipping
receipts, public URLs, and prepared materials. It does not authorize promotion,
upload, submission, pricing changes, or agreement acceptance.

**Hold App Store submission.** The October 6 owner decision is a fully free
launch. Full macro/folder access remains enabled for all users; legacy
StoreKit ownership is preserved. The current candidate still needs the
nightly, weekly and main ladder and final candidate evidence. Use the [prepared packet](APP_STORE_PACKET.md) and
[submission checklist](ASC_SUBMISSION_CHECKLIST.md).

## Verified release state

| Surface | Exact state | Evidence and limit |
| --- | --- | --- |
| nightly | `80455834a3126973a195c74d6a605ce95105831c` | Current audited integration source |
| weekly | `af37371ca19d111dd65806471a8841f97163a6a7` | Missing 43 nightly commits; one main flow-back commit ahead of main |
| main | `59b96a15c23f7621c9948a78718905ac27ad3748` | Missing 43 nightly commits |
| Nightly exact-head CI | [36335804831](https://github.com/dfakkeldy/MacroMark/actions/runs/36335804831), success | iOS build-for-testing, Watch build, package checks; app-hosted iOS unit test step **skipped** |
| Real ship receipt | [37306349729](https://github.com/dfakkeldy/MacroMark/actions/runs/37306349729), job `111750878037`, October 5 | Payload nightly `80455834`, automation main `59b96a15`, Xcode 26.6 (`17F113`), 50 package tests; signed IPA uploaded, `1.0 (75)` processed, internal distribution succeeded |
| External beta / App Review / public store | Not verified by this public packet | Internal distribution does not establish external approval, installation, App Review approval, or availability |

The scheduled main workflow replaces nightly's Fastlane files with main's
release automation. Its October 5 run did **not** run app-hosted iOS/UI tests.
Nightly contains a stricter release workflow that requires them, but that is
not yet the active scheduled main workflow.

All three live branch protections require up-to-date `Build gate + tests`
(`strict=true`), zero approvals, and do not enforce protection for admins. No
additional active branch rulesets were returned. These settings were only
read. Ordinary CI can skip iOS tests for unavailable/timed-out simulators.

Keep `feature/* → nightly → weekly → main`: internal testers, then weekly
external acceptance/Beta App Review as applicable, then main App Store.
Weekly dispatch builds the workflow ref, so dispatching it from nightly would
bypass the payload ladder. Promotions need separate authorization. Do not
backport features or change protections/pipelines to obtain green CI.

## Source blockers and remaining evidence

| Gate | Current evidence / next action | State |
| --- | --- | --- |
| Free-launch access | `StoreAccessPolicy.paywallDisabled = true` grants all macro/folder features without purchases | **Approved free release policy**; preserve existing product IDs and ownership |
| In-app privacy / subscription terms | Settings now exposes Privacy Policy; paywall exposes existing Privacy and Terms URLs (HTTP 200 on 6 Oct) | **Implemented; candidate UI visibility and link-opening acceptance pending** |
| Legacy StoreKit UI | Simulator auto-entitles; historical trial UI remains behind inaccessible purchase gates during free launch | **Not a free-launch gate**; no new paid offer or purchase claim in listing |
| Lifetime revocation | Lifetime flag/keychain is set and never cleared on revocation, although Apple excludes revoked transactions from current entitlements | **Legacy paid-path finding**; full free access does not depend on cached ownership; review before any future paid policy |
| Manifest coverage | Four manifests: empty collection, tracking false; app/Watch/package UserDefaults `CA92.1`; unused `.contentModificationDateKey` request removed; filename order/filtering preserved | **Source coverage gap removed; final linked-API/archive report still pending** |
| Core capture → durable Markdown | WAL, retry, deduplication, original timestamps and visible export status in source | **Configured / partly automated**; no fresh paired physical-device acceptance in this audit |
| Screenshots | Current neutral phone/iPad simulator drafts captured and inspected; Watch finals incomplete | **Draft assets**; clean status bars and candidate/device coverage before store upload |
| ASC configuration | Free launch; existing annual draft is preserved | **Pending** final candidate selection, listing/assets and current questionnaires; no IAP attachment for this free launch |

Open June issues #79–#86 are not automatically eight current blockers. The
intended bookmark cleanup, WAL ordering, duplicate-audio/retry guards, mixed
text-input handling, cancelled-log handling and explicit-save changes were
found in nightly. The old bug-hunt ledger's “fixed locally / PR pending” is not
current shipping evidence; reproduce on the candidate before closing issues.

## Source and store inventory

- App ID `6785081218`, version `1.0`. Checked-in build counter `2` is not the
  current uploaded build: Fastlane increments from TestFlight.
- App targets: iOS/iPadOS 26.5 and watchOS 26.5; source Swift 6. Package platform
  declarations do not lower these targets. The last receipt used Xcode 26.6;
  final archive must satisfy the current Xcode 26/version 26 SDK requirement.
- Bundle IDs: `com.danfakkeldy.macromark`, `.watchkitapp`, and
  `.watchkitapp.MacroMarkWidget`.
- iCloud: CloudKit and CloudDocuments, `iCloud.com.danfakkeldy.macromark`.
  iOS background mode `remote-notification`; no Always Location or background
  audio mode. Verify intended CloudKit notification use and archive
  entitlements before review; no entitlements changed here.
- No app account, developer note server, ad/analytics SDK or external package
  dependency found. Notes/queues are local; export is to user storage. Apple
  Speech may use Apple services; do not promise universal offline/on-device
  transcription. Location is optional and When In Use.
- `ITSAppUsesNonExemptEncryption=false`; no custom encryption found. This is
  source evidence, not the owner's legal declaration.
- iOS and Watch icons are 1024 × 1024 opaque RGB PNGs. Last signed upload passed
  validation; validate the eventual promoted archive again.
- English metadata is prepared in `fastlane/metadata/en-US/`. Homepage,
  privacy and terms returned HTTP 200 on October 6; homepage contains support
  contact. Pages is `main /docs`, so a nightly docs PR does not update the site.

## Next execution sequence

1. Review prepared docs/copy and resolve scoped source blockers on nightly
   with focused tests and independent review. The [repair plan](RELEASE_REPAIR_PLAN.md)
   separates defects from beta policy and unobserved tests.
2. Serially capture phone/iPad/Watch images; verify core capture,
   deferred retry and replay against a current candidate, without cosmetic
   expansion or unrelated features.
3. At the next sign-in, inspect existing ASC fields/products before entering
   prepared material. The operator can do data entry; owner decides legal,
   business, free availability, rights and release scope.
4. When authorized, promote through weekly external acceptance and main.
   `release` and `release_train channel:appstore` upload **and submit**; they
   are not harmless archive-only commands. Use manual public release unless
   the owner explicitly chooses otherwise.

## Apple references

Re-checked October 6: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[subscriptions](https://developer.apple.com/app-store/subscriptions/),
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/),
[required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api),
[API category definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/),
[upcoming requirements](https://developer.apple.com/news/upcoming-requirements/).

## 6 October continuation

The legal-link and unused timestamp-request diffs passed independent source
review. The local package test attempt failed at ad-hoc signing of a generated
test bundle with Finder/resource-fork metadata; no test assertion ran in that
attempt and no signing credentials/settings were changed. Exact source-head `cc2cd9c` hosted CI 37410745965 passed iOS build-for-testing,
Watch compilation and 50 package tests; nine app tests were skipped because no
iPhone simulator was available on that runner. Previous documentation head
`cba47d32` passed those nine app tests, which does not substitute for patch-head
execution. Local native builds remain resource-gated. These receipts preceded the free-launch
decision. Historical trial/lifetime findings are future paid-policy concerns,
not free-launch blockers; existing ownership and store records remain intact.
