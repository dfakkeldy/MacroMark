# MacroMark App Store Readiness

Re-checked: 2026-10-14. This refresh records weekly and main git promotion of
the accepted free-launch candidate after
[PR #120](https://github.com/dfakkeldy/MacroMark/pull/120) merged into `weekly`
and [PR #121](https://github.com/dfakkeldy/MacroMark/pull/121) merged into
`main`. It records GitHub promotion receipts and the release coordinator's October 14
official read-only TestFlight check. Current selected App Store build, metadata
completeness and review/release state have not been read back. Dan's October 14
grant authorizes submission of eligible passing candidates; it does not resolve
missing factual evidence, authorize new agreements or enable automatic release.

**Submission authority is granted; actual prerequisites remain.** The October 6 owner decision is a fully free
launch. Full macro/folder access remains enabled for all users; legacy
StoreKit ownership is preserved. Weekly and main both carry that candidate:
weekly merge `af950006662dfed56afce34bcd76b986cb55b6f1` (reviewed head
`5f1dc4718caa6711cf5267f987338dab1bd19236`); main merge
`aeafeda1b649fe8952ce1a7f23ac8a6eabe6c86f` (head
`abd4ae522e6c3c860d66298b73b31f9ed9790ca8`; per #121, byte-identical to
weekly). Complete the factual candidate/store packet and verify the selected
build and persisted manual-release setting before submitting. No repeated
generic submission approval is required; no submission or public release is
claimed here. Use the [prepared packet](APP_STORE_PACKET.md) and
[submission checklist](ASC_SUBMISSION_CHECKLIST.md).

## Verified release state

| Surface | Exact state | Evidence and limit |
| --- | --- | --- |
| Promoted Nightly app payload | `085fa70dad8ca0299da18a8411be8916f231f34a` | Release application source; later documentation-only Nightly commits do not change it; payload promoted to weekly in #120 |
| weekly | `af950006662dfed56afce34bcd76b986cb55b6f1` | Merged 2026-10-14T03:35:02Z via #120; reviewed head `5f1dc4718caa6711cf5267f987338dab1bd19236`; payload matches nightly `085fa70…` |
| main | `aeafeda1b649fe8952ce1a7f23ac8a6eabe6c86f` | Merged 2026-10-14T03:50:00Z via #121; head `abd4ae522e6c3c860d66298b73b31f9ed9790ca8`; per #121, tree is byte-identical to weekly `af950006…` |
| Weekly promotion CI | [38505654154](https://github.com/dfakkeldy/MacroMark/actions/runs/38505654154), success | Required checks on exact reviewed head `5f1dc471`; from #120 PR body |
| Main promotion CI | [38507144366](https://github.com/dfakkeldy/MacroMark/actions/runs/38507144366), success | Required `Build gate + tests` on exact head `abd4ae522`; verified via GitHub Actions API |
| Verified internal TestFlight | `1.0 (83)` | October 14 official read-only service check: processed, internal, unexpired; actual [ship 38396977539](https://github.com/dfakkeldy/MacroMark/actions/runs/38396977539) used app source `085fa70d`. Current selected App Store build/state remains unverified |
| Main post-merge CI | [38508282631](https://github.com/dfakkeldy/MacroMark/actions/runs/38508282631), success | Passed at actual merge head `aeafeda1`; separate from device acceptance and store state |
| Historical internal ship | [37306349729](https://github.com/dfakkeldy/MacroMark/actions/runs/37306349729), job `111750878037`, October 5 | Payload nightly `80455834`, automation main `59b96a15`, Xcode 26.6 (`17F113`), 50 package tests; signed IPA uploaded, `1.0 (75)` processed, internal distribution succeeded |
| External beta / App Review / public store | Not verified; not opened by #120 or #121 | Internal TestFlight processing does not establish external approval, App Review approval, or public availability |

The scheduled main workflow replaces nightly's Fastlane files with main's
release automation. Its October 5 run did **not** run app-hosted iOS/UI tests.
Nightly contains a stricter release workflow that requires them, but that is
not yet the active scheduled main workflow.

All three live branch protections require up-to-date `Build gate + tests`
(`strict=true`), zero approvals, and do not enforce protection for admins. No
additional active branch rulesets were returned. These settings were only
read. Ordinary CI can skip iOS tests for unavailable/timed-out simulators.

Keep `feature/* → nightly → weekly → main`. Dan approved his internal
acceptance plus required technical checks in place of nonexistent external
testers. External eligibility/Beta App Review is needed only for claims of
external distribution; no new tester requirement is introduced.
Weekly dispatch builds the workflow ref, so dispatching it from nightly would
bypass the payload ladder. The current release grant authorizes normal promotions through actual gates. Do not
backport features or change protections/pipelines to obtain green CI.

## Source blockers and remaining evidence

| Gate | Current evidence / next action | State |
| --- | --- | --- |
| Free-launch access | `StoreAccessPolicy.paywallDisabled = true` grants all macro/folder features without purchases | **Approved free release policy**; preserve existing product IDs and ownership |
| In-app privacy / subscription terms | Settings now exposes Privacy Policy; paywall exposes existing Privacy and Terms URLs (HTTP 200 on 6 Oct) | **Implemented; candidate UI visibility and link-opening acceptance pending** |
| Legacy StoreKit UI | Simulator auto-entitles; historical trial UI remains behind inaccessible purchase gates during free launch | **Not a free-launch gate**; no new paid offer or purchase claim in listing |
| Lifetime revocation | Lifetime flag/keychain is set and never cleared on revocation, although Apple excludes revoked transactions from current entitlements | **Legacy paid-path finding**; full free access does not depend on cached ownership; review before any future paid policy |
| Manifest coverage | Four manifests: empty collection, tracking false; app/Watch/package UserDefaults `CA92.1`; unused `.contentModificationDateKey` request removed; filename order/filtering preserved | **Source coverage gap removed; final linked-API/archive report still pending** |
| Core capture → durable Markdown | WAL, retry, deduplication, original timestamps and visible export status in source | Dan accepted paired capture on source `96c2c13`; build 83 application/configuration/tests match that source (only instructions differ). Preserve that acceptance and verify uncovered cases |
| Screenshots | Current neutral phone/iPad simulator drafts captured and inspected; Watch finals incomplete | Preserve previously accepted/saved assets; verify current candidate/device coverage and complete actual gaps |
| ASC configuration | Free launch; existing annual draft is preserved | Weekly (#120) and main (#121) have the accepted candidate. Listing/assets and questionnaires remain pending. Internal TestFlight `1.0 (83)` verified by the October 14 service check; selected store build/fields remain unverified. No IAP attachment for this free launch |

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
2. Preserve accepted capture behavior and existing assets. Verify their
   candidate correspondence and complete only actual image or behavior gaps;
   serialize any necessary native work.
3. At the next sign-in, inspect existing ASC fields/products before entering
   prepared material. The operator can do data entry; owner decides legal,
   business, free availability, rights and release scope.
4. Weekly git promotion (#120) and main git promotion (#121) of the accepted
   candidate are complete. Submit only after the actual candidate/store
   prerequisites pass under Dan's October 14 grant; do not ask for that grant
   again. `release` and `release_train channel:appstore` upload **and submit**;
   they are not archive-only commands. Verify the persisted manual-release
   setting and retain the actual submission result. Do not enable automatic
   public release.

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
