# App Store Connect submission checklist

Re-checked: 2026-10-06. [Readiness](APP_STORE_READINESS.md) holds exact branch,
CI, upload evidence and blockers; [prepared packet](APP_STORE_PACKET.md) holds
copy, product localizations, review instructions and declaration mappings.

## Prepare the free candidate

- [x] Keep all macro/folder features available without purchases; preserve
  legacy product IDs and prior ownership. Do not attach paid products to the
  approved free launch.
- [x] Prepare listing and review copy for the free launch, with existing
  privacy and Terms links.
- [ ] Inspect final archive manifest coverage.
- [ ] Verify paired capture → phone → Markdown, original timestamp, deferred
  retry and duplicate replay against the selected candidate.
- [ ] Recapture clean phone/iPad/Watch assets with neutral fixture notes and
  matching source/build/device/locale receipts.
- [ ] Verify normal exact-head checks and nightly internal delivery, then
  weekly external installation/launch acceptance before main promotion.

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
- [ ] Keep final App Review submission/public release held. The existing
  `release` / `release_train channel:appstore` lane uploads **and submits**;
  do not invoke it as an upload-only operation.

Promotions are now authorized through the normal feature→nightly→weekly→main
ladder, subject to source/check/delivery/acceptance gates. Store submission and
public release remain separate authorization. Historical [IAP setup](ASC_IAP_SETUP.md)
and [StoreKit cases](STOREKIT_TEST_PLAN.md) are compatibility references;
[paired-device smoke cases](SMOKE_TEST_CHECKLIST.md) remain relevant.
