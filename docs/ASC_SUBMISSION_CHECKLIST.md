# App Store Connect submission checklist

Re-checked: 2026-10-06. [Readiness](APP_STORE_READINESS.md) holds exact branch,
CI, upload evidence and blockers; [prepared packet](APP_STORE_PACKET.md) holds
copy, product localizations, review instructions and declaration mappings.

## Prepare before sign-in

- [ ] Confirm the intended paid candidate policy before changing the deliberate
  beta bypass. Repair in-app privacy/Terms links, lifetime revocation and trial
  eligibility/copy on nightly; validate annual expiry separately.
- [ ] Review file-timestamp manifest coverage and final archive privacy report.
- [ ] Test purchase, restore, expiry/revocation and free-tier gates using an
  unentitled path; normal simulator auto-entitlement cannot prove them.
- [ ] Verify core paired capture → phone → Markdown, original timestamp,
  deferred retry and duplicate replay against the candidate.
- [ ] Recapture phone/iPad/Watch and IAP review assets with neutral demo notes.
- [x] Prepare English listing, URLs, product localizations and review instructions.
- [x] Verify public homepage/support/privacy/terms: HTTP 200, October 6.

No source changes, builds, uploads, account changes or promotions were made
by this documentation audit. Device behavior, ASC declarations, source
configuration and upload processing are separate states.

## At the next ASC session

An authorized operator can fill text and assets. Do not assign every field,
screenshot or test to Dan.

- [ ] Inspect app `6785081218`, version/review state and newer metadata first.
- [ ] Verify selected build/source and processing/beta status. The October 5
  internal `1.0 (75)` receipt is not external or App Review approval.
- [ ] Inspect annual `com.macromark.subscription.annual` and lifetime
  `com.macromark.lifetime`; fill incomplete prepared review/localization
  fields under authorization and associate first-time IAPs with the version.
- [ ] Obtain owner decisions for paid offer/trial dates, territories, rights/EULA,
  privacy, age/social-media questionnaire, export, DSA and outstanding
  business/agreement declarations. No invented answers or price changes.
- [ ] Declare optional accessibility labels only for tested common tasks.
- [ ] Confirm review contacts privately in ASC; the account-free app needs
  no MacroMark demo password.
- [ ] Confirm weekly external gate and main candidate before authorizing
  submission; no feature bypass for green CI.
- [ ] Confirm manual release after review unless explicitly authorized otherwise.
  `release` / `release_train channel:appstore` upload and submit.

## Consolidated owner handoff

1. Sign in when back at the computer and confirm account notices plus the
   prepared legal, business, rights/export and paid-offer decisions.
2. Once the candidate and weekly acceptance are ready, authorize the exact
   promotion/upload/submission/public-release operation.

No sign-in is requested while independent preparation continues. Do not reuse
an expired launch discount date. [IAP setup](ASC_IAP_SETUP.md),
[StoreKit cases](STOREKIT_TEST_PLAN.md) and [paired-device smoke cases](SMOKE_TEST_CHECKLIST.md)
provide the detailed operator instructions; the packet links official Apple
requirements.
