# MacroMark App Store Readiness

Last synchronized: 2026-07-02

This is the current shipping checklist for getting MacroMark from repository state to App Store submission. It combines live Kickstart/App Store Connect refresh data, the repository release ladder, and the App Store pre-flight gates.

## Current Facts

- App Store app ID: `6785081218`
- App Store URL: `https://apps.apple.com/app/id6785081218`
- Planned launch date in Kickstart: 2026-08-04
- Kickstart progress: 9/107 tasks complete
- ASO score: 89/100
- Localizations: `en-US` only, 83% complete
- TestFlight: `buildCount: 0`, `feedbackCount: 0`
- Reviews: 0
- Editorial nominations: 0
- Accessibility Nutrition Labels: 0 declarations
- GitHub Pages source: `main /docs`
- Live homepage: HTTP 200 on 2026-07-01
- Live `privacy.html`: returned 404 before the 2026-07-01 sync because the page had not reached `main /docs`; verify again after the reconciliation and Pages rebuild.

## Next Ten Steps

1. **Land the reconciliation PR.** Bring the release automation/docs line from `origin/main` together with the v1 product line from `origin/nightly`, then promote through `weekly` and `main` when the release ladder is ready.
2. **Produce the first visible internal TestFlight build.** Dispatch the nightly release train after secrets/profiles are confirmed, then verify Fastlane logs show upload, processing, and internal distribution success. Kickstart must refresh from `buildCount: 0` to at least one processed build.
3. **Validate signing and Fastlane secrets.** Confirm `APP_STORE_CONNECT_API_KEY_JSON` or component API-key secrets, `MATCH_PASSWORD`, `MATCH_GIT_SSH_KEY`, `MATCH_GIT_URL`, and App Store profiles for the iOS app, Watch app, and widget extension.
4. **Finish StoreKit verification.** Confirm the annual subscription and lifetime non-consumable exist in App Store Connect, then test local purchase, restore, entitlement persistence, free-tier limits, and Pro gates.
5. **Complete privacy submission fields.** Match the app privacy answers to the privacy manifests and actual runtime behavior. Confirm microphone, speech recognition, location, UserDefaults, file timestamp, and iCloud/file access disclosures are correct.
6. **Declare Accessibility Nutrition Labels.** Run an accessibility pass before declaring labels; the current App Store Connect refresh reports zero declarations.
7. **Generate and upload screenshots.** Use the Fastlane screenshot lane and validate the resulting assets against current UI, no debug data, and required device sizes.
8. **Run a paired iPhone + Apple Watch smoke test.** Cover offline Watch capture, reconnect, daily-log review by date, destination proof/test note, partial transcription warning, macro expansion, and retry/deferred export behavior.
9. **Finalize metadata and review information.** Check title/subtitle/keywords, description, support/marketing/privacy URLs, copyright, age rating, export compliance, app review notes, and any hardware/location instructions.
10. **Submit a potentially final build for review.** Only after TestFlight smoke passes and metadata is complete, attach the processed build, submit IAP products if needed, and use manual release unless an explicit launch plan says otherwise.

## Known Follow-Ups From Kickstart

- Terms of service exists in the repo/site sync, but still needs confirmation in the app and App Store Connect surfaces.
- Pricing tiers and free-vs-paid boundary are due 2026-07-02.
- App Store description is due 2026-07-02.
- In-app feedback entry point and review-prompt rules are due 2026-07-03.
- Competitor screenshot/copy reviews are due or overdue and should feed the separate marketing-plan PR.

## Do Not Treat As Done Yet

- A green resolver or compile-only release workflow is not proof that TestFlight has a build.
- A checked-in privacy page is not proof the live URL works; verify the deployed Pages URL after merge.
- Fastlane metadata in the repo is not proof App Store Connect fields are complete; refresh or inspect ASC before submission.
- Release automation narrowing to nightly internal testers is routing, not upload proof.
