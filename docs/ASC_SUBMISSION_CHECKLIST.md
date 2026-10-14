# App Store Connect submission checklist

Re-checked: 2026-10-14. [Readiness](APP_STORE_READINESS.md) holds exact branch,
CI, upload evidence and blockers; [prepared packet](APP_STORE_PACKET.md) holds
copy, product localizations, review instructions and declaration mappings.

## Prepare the free candidate

- [x] Keep all macro/folder features available without purchases; preserve
  legacy product IDs and prior ownership. Do not attach paid products to the
  approved free launch.
- [x] Prepare listing and review copy for the free launch, with existing
  privacy and Terms links.
- [ ] Inspect final archive manifest coverage.
- [ ] Retain Dan's accepted paired capture → phone → Markdown evidence and
  source correspondence; verify any uncovered original-timestamp, deferred
  retry or duplicate-replay cases without repeating settled acceptance.
- [ ] Preserve accepted/saved assets; verify candidate/device coverage and
  complete actual gaps with neutral fixtures and source/build/locale receipts.
- [x] Verify normal exact-head promotion checks and preserve Dan's internal
  acceptance of the application-equivalent candidate. Weekly and main git
  promotion are done (#120, #121). Dan's internal acceptance plus required
  technical checks replaces the nonexistent external-tester gate; this does
  not prove installation of build 83 or completion of the store packet.

The authorized operator owns routine metadata entry and screenshots. Dan
only needs to resolve actual legal/business facts and actions requiring his
account or physical device; do not assign independent preparation back to him.

## At ASC

- [ ] Verify app `6785081218`, selected candidate/build and processing state.
- [ ] Preserve the existing annual product draft and legacy IDs. No creation,
  deletion, new offers, price changes or first-IAP attachment for this launch.
- [ ] Reconcile listing/assets with actual free behavior. Complete privacy,
  age/social-media, rights/export and account fields using verified facts and
  owner decisions where required; do not invent answers.
- [ ] Confirm private review contacts. The app needs no MacroMark login.
- [ ] Declare optional accessibility labels only for tested common tasks.
- [ ] After all actual prerequisites pass, submit the eligible candidate under
  Dan's October 14 authorization and retain the submission receipt. Read back
  the saved manual-release setting first; do not enable automatic public release.
  The existing `release` / `release_train channel:appstore` lane uploads **and
  submits**; do not invoke it as an upload-only operation.

Promotions are now authorized through the normal feature→nightly→weekly→main
ladder, subject to source/check/delivery/acceptance gates. Submission of passing
candidates is authorized; verified candidate, privacy/rights and ASC prerequisites
still govern execution. App Review approval and public release are separate outcomes.
Historical [IAP setup](ASC_IAP_SETUP.md)
and [StoreKit cases](STOREKIT_TEST_PLAN.md) are compatibility references;
[paired-device smoke cases](SMOKE_TEST_CHECKLIST.md) remain relevant.
