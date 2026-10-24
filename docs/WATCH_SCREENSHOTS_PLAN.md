# Watch Screenshots Plan

Re-checked: 2026-10-24. MacroMark 1.0 is live on the App Store (released
2026-10-23) with published screenshots: iPhone and iPad Inbox, Note detail,
Macros and New Macro, plus one Apple Watch capture screenshot. No IAP review
image was needed for the free launch. The June 27 local drafts are superseded.
Use [the current packet](APP_STORE_PACKET.md) for the asset inventory.

The published Watch set covers shot 1 (capture). Shots 2–4 below are optional
additions for a later update. For 1.1, also consider the Direct Send
Deliveries and Replies screens.

Use fake demo content only. Do not capture personal notes, real routes, private locations, contact names, account identifiers, or production customer data.

## Recommendation

Use manual Simulator capture for watchOS screenshots under launch pressure. The current Fastlane screenshot setup targets iPhone and iPad devices in `fastlane/Snapfile` and the `ios screenshots` lane; no paired watchOS screenshot lane is configured. Manual Simulator capture is faster and lower-risk for a solo launch unless a dedicated watch screenshot lane is added later.

Apple requires Apple Watch screenshots for Apple Watch apps, and the same Apple Watch screenshot size must be used consistently across all localizations. Upload PNG or JPG files only.

## Watch Shots

1. Mid-dictation capture (published with 1.0)
   - Show the Watch capture UI in an active recording/dictation state.
   - Demo phrase: `Remember to review the launch checklist`.
   - Avoid any real address or personal detail.

2. Complication on watch face
   - Show the MacroMark complication on a clean watch face.
   - Use a neutral watch face and default-looking time.
   - If possible, show the complication ready to launch instant capture.

3. Daily-note review
   - Show the Watch daily-log view with fake notes.
   - Suggested fake entries:
     - `# Launch`
     - `Check screenshots`
     - `Pick up groceries`

4. Saved confirmation
   - Show the confirmation state after a successful capture save.
   - The state should communicate that the note is safely queued/saved without showing a purchase prompt.

## Screenshot Sizes

Use one watch screenshot size consistently across all localizations. Apple lists these current App Store Connect Apple Watch screenshot sizes:

| Device family | Size |
| --- | --- |
| Apple Watch Ultra 4 and Ultra 3 | 422 x 514 pixels |
| Apple Watch Ultra 2 and Ultra | 410 x 502 pixels |
| Apple Watch Series 12, Series 11 and Series 10 | 416 x 496 pixels |
| Apple Watch Series 9, Series 8, and Series 7 | 396 x 484 pixels |
| Apple Watch Series 6, Series 5, Series 4, SE 3, and SE | 368 x 448 pixels |
| Apple Watch Series 3, Series 2 and Series 1 | 312 x 390 pixels |

Preferred capture target: Apple Watch Ultra 4 or Ultra 3 at `422 x 514`, because it satisfies the largest current watch screenshot slot and gives the best room for readable text. If the installed Xcode Simulator does not expose Ultra 3, use Ultra 2 at `410 x 502` and keep that exact size for every watch localization.

## Capture Steps

1. Boot an iPhone simulator paired with an Apple Watch simulator if the watch app needs iPhone connectivity.
2. Install MacroMark and the Watch app from Xcode.
3. Use demo mode, seed data, or manual fake captures only.
4. Set the simulator appearance to the App Store screenshot style you want to ship.
5. Capture PNG screenshots from the Simulator screenshot command.
6. Crop only if the final image remains an accepted App Store Connect size.
7. Name files by platform, scenario, and locale, for example `watch-ultra3-mid-dictation-en-US.png`.
8. Upload manually in App Store Connect unless a watch screenshot lane is added.

## iPhone And iPad Recapture Check

The published 1.0 iPhone/iPad set is current. For a later update, recapture
any screenshot that shows:

- Paywall product cards.
- StoreKit prices.
- A Pro-gated macro limit message.
- Subscription trial copy.
- Lifetime purchase copy.
- Trial copy rendered as `P1M` or any other developer-facing period string.

The app is free, so no screenshot should show a price or purchase. The
historical planning values ($9.99/year with a one-month trial, $24.99
lifetime, a proposed $16.99 launch price) were never confirmed by the owner and
are not current offers. The current iPhone required category is Dynamic Island
medium (1179 × 2556 or 1206 × 2622 portrait). Verify actual ASC
scaling/acceptance before replacing the published set.

## References

- Apple: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
