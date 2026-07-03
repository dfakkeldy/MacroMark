# Watch Screenshots Plan

Last updated: 2026-07-03.

Use fake demo content only. Do not capture personal notes, real routes, private locations, contact names, account identifiers, or production customer data.

## Recommendation

Use manual Simulator capture for watchOS screenshots under launch pressure. The current Fastlane screenshot setup targets iPhone and iPad devices in `fastlane/Snapfile` and the `ios screenshots` lane; no paired watchOS screenshot lane is configured. Manual Simulator capture is faster and lower-risk for a solo launch unless a dedicated watch screenshot lane is added later.

## Required Watch Shots

1. Mid-dictation capture
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
     - `Test restore purchases`

4. Saved confirmation
   - Show the confirmation state after a successful capture save.
   - The state should communicate that the note is safely queued/saved without showing a purchase prompt.

## Screenshot Sizes

Use one watch screenshot size consistently across all localizations. Current App Store Connect accepted Apple Watch screenshot sizes include:

| Device family | Size |
| --- | --- |
| Apple Watch Ultra 3 | 422 x 514 |
| Large Apple Watch | 410 x 502 or 416 x 496 |
| Standard Apple Watch | 396 x 484 |
| Smaller Apple Watch | 368 x 448 or 312 x 390 |

Preferred capture target: Apple Watch Ultra 3 at `422 x 514`, because it satisfies the largest current watch screenshot slot and gives the best room for readable text.

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

Recapture iPhone/iPad screenshots if any current screenshot shows:

- Paywall product cards.
- StoreKit prices.
- A Pro-gated macro limit message.
- Subscription trial copy.
- Lifetime purchase copy.

The annual price is now $9.99/year with a 1-month free trial, and the lifetime standard price is now $24.99 with a $16.99 launch intro in App Store Connect. If the existing iPhone/iPad screenshot set does not show pricing or paywall surfaces, no pricing-specific recapture is required.

## References

- Apple: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
