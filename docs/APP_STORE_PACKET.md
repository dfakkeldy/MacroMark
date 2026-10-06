# MacroMark prepared App Store packet

Prepared: 2026-10-06 against nightly `80455834`. Draft fields for the intended
v1 release, not proof of saved ASC metadata or accepted paid products. See
[readiness](APP_STORE_READINESS.md) before using the packet.

## Listing fields

Copy-ready text lives in `fastlane/metadata/en-US/`.

| Field | Prepared value |
| --- | --- |
| Name / subtitle | MacroMark / Voice Capture for Markdown |
| Categories / locale | Productivity, Utilities / en-US |
| Keywords | `notes,dictation,watch,obsidian,logseq,daily,journal,memo,transcribe,vault,shortcut,inbox,quick` |
| Marketing | https://dfakkeldy.github.io/MacroMark/ |
| Support | https://dfakkeldy.github.io/MacroMark/#support |
| Privacy | https://dfakkeldy.github.io/MacroMark/privacy.html |
| Terms | https://dfakkeldy.github.io/MacroMark/terms.html |
| Copyright | 2026 KinNoKi Labs — owner to verify identity and rights |

URLs were reachable October 6. A public Terms page does not itself select an
ASC EULA. Confirm the standard/custom license and content-rights declaration
with the owner; do not adopt legal terms by implication. Existing release
notes are prepared for future updates; ASC's first-version surface does not
have What's New.

## App Review notes — paste after candidate verification

```text
MacroMark is a paired Apple Watch and iPhone tool for capturing private notes
and appending them to dated Markdown files. No MacroMark account or demo
credentials are required. An Apple Watch paired with iPhone is needed to
review Watch capture and its complication; iPhone capture and review are also
available.

On iPhone, open the Macros tab and configure the destination. Use the
destination test-note control to verify the Markdown file. On Watch, use the
microphone or text input to capture "Heading One Demo note". Keep iPhone
available for processing, then inspect the phone Inbox and dated Markdown
file. Watch captures can queue while iPhone is unavailable. Apple Speech
depends on device, language and network support. Microphone/speech permission
is requested for voice capture. Location is optional for location macros.

Capture and daily-note append remain free. Pro unlocks unlimited custom
macros, editing default macros and folder customization. Intended paid
options are annual auto-renewable access and a lifetime non-consumable.
Add a fourth custom macro in the Macros tab or select a Pro-gated control to
reach the paywall. Restore Purchases is on the paywall. See products attached
to this version for approved prices and any introductory offer. Declining
upgrade leaves capture available.

MacroMark uses local storage, the user's iCloud/document destination,
WatchConnectivity, Apple Speech and StoreKit. It has no developer-operated
note server, ads, tracking or third-party analytics SDK.
```

Verify navigation labels, actual device behavior and paid gates on the final
build first. Confirm the paid candidate policy; the testing paywall bypass is deliberate
beta configuration, not an accidental defect. Add tested device/OS details
at handoff. Review contacts belong privately in ASC, not this repository.

## IAP field sheet

| Field | Annual | Lifetime |
| --- | --- | --- |
| Type | Auto-renewable subscription | Non-consumable |
| ID | `com.macromark.subscription.annual` | `com.macromark.lifetime` |
| Reference / display name | MacroMark Pro Annual | MacroMark Pro Lifetime |
| Duration | 1 year | Permanent entitlement subject to StoreKit status |
| English description | Unlimited macros and custom folders yearly. | Unlimited macros and custom folders forever. |
| Review image | Current unentitled paywall with annual card | Current unentitled paywall with lifetime card |

Descriptions fit the 55-character localization limit. The app loads product
IDs directly without a group ID. Inspect the existing group first; use the
suggested reference `MacroMark Pro` only if one must be created.

Local test configuration has $9.99/year with a one-month trial and $24.99
lifetime. Older plans propose a $16.99 lifetime launch discount. These are
planning values, not ASC evidence or current price authorization. Do not reuse
the expired September 1 price-change date. Prices, trial dates, territories,
tax category, Family Sharing and agreements require exact owner decisions.
First-time IAPs must be associated with the candidate version for review.

Prepared IAP review note:

```text
Open the Macros tab and add a fourth custom macro or enter a Pro-gated macro
or folder control. The paywall offers annual and lifetime access to the same
Pro features. Capture and daily-note append do not require a purchase.
Restore Purchases is on the paywall.
```

## Declaration worksheet — owner accepts final answers

| Surface | Source evidence | Pending |
| --- | --- | --- |
| App Privacy | All manifests: no tracking, empty collected-data arrays. No developer servers or ad/analytics SDKs found. User storage, optional location, Apple Speech and StoreKit used. | Map actual runtime to Apple's definition; empty manifests do not select Data Not Collected |
| Manifest | UserDefaults `CA92.1`; package requests file modification-date key without FileTimestamp reason | Correct audited coverage and inspect the final archive's privacy report |
| Permissions | Microphone, speech and When In Use location | Confirm denial behavior and purpose strings |
| Accounts | No app account creation/login found | Account deletion appears inapplicable to this version; confirm no new account flow |
| Age / capabilities | Private notes; no public social feed, unrestricted browser, ads, gambling or curated mature content found; IAP present | Complete current questionnaire including social-media question; no guessed age rating |
| Rights / license | MIT source, system frameworks, repo branding/demo assets; Obsidian/Logseq compatibility mentions | Owner confirms asset/mark/content rights and intended EULA |
| Encryption | `ITSAppUsesNonExemptEncryption=false`; no custom crypto found | Owner confirms legal determination for final build |
| Accessibility | System/SwiftUI controls | Optional labels only after common-task tests |
| Business / availability | No current public evidence | Owner confirms notices/agreements, paid offer, storefronts, DSA trader status and release setting |

Apple separates developer collection from on-device-only processing and its
own service collection. Privacy policy already discloses Apple's Speech
services; do not market universally offline dictation. Archive manifest
placement/coverage is a separate check from ASC privacy answers.

## Asset production sheet

| Asset | Existing state | Next capture |
| --- | --- | --- |
| iPhone | Ignored June 27 PNGs: 1320 × 2868 and 1170 × 2532 | Current required Dynamic Island medium category: 1179 × 2556 or 1206 × 2622; verify ASC scaling if reusing another category |
| iPad | Ignored June 27 PNGs: 2064 × 2752 | Current 13-inch layout: successful Inbox, note detail, macro output, destination proof |
| Watch | No final images / no Watch Fastlane lane | Capture, saved/queued confirmation, daily-log review, complication; one accepted size across locales |
| IAP review | No final images found | Actual cards with readable eligible trial, Restore/legal links and no testing bypass |
| Icons | iOS/Watch: 1024 × 1024 RGB PNGs, no alpha | Validate promoted archive; no new artwork required |

Local screenshots are not versioned release assets. The lead Inbox image has
an Incomplete warning and developer launch-task text, also present in current
demo seeds. Recapture useful neutral notes, inspect every image, and preserve
SHA/build/device/date/dimensions. Suggested content: `## Idea: Try a new walk`,
`- [ ] Pick up groceries`, `## Reading: Find the author's next book`. No real
contacts, locations or private captures. Suggested captions: “Capture the
thought”, “Find it in your daily note”, “Speak Markdown”, “See where notes go”.

Capture phone/iPad using the existing lane after source fixes. Capture Watch
manually using [the Watch plan](WATCH_SCREENSHOTS_PLAN.md), one Xcode/session
at a time. Required Watch sizes include 422 × 514, 410 × 502, 416 × 496,
396 × 484, 368 × 448 or 312 × 390. No final images were fabricated or
recaptured in this documentation audit.

## Operator handoff

After source fixes and candidate checks, compare current ASC fields with this
packet after sign-in. An authorized operator can enter text/assets; the owner
reviews legal/business/price/rights answers. Obtain specific authorization
before weekly promotion/external upload, main promotion, submission and
public release. Default to manual release after approval unless explicitly
instructed otherwise.

## Apple references

Re-checked October 6: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[subscriptions](https://developer.apple.com/app-store/subscriptions/),
[IAP information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/),
[submit IAPs](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/),
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/),
[screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Localized IAP display names are limited to 30 characters and descriptions to 45. The prepared annual/lifetime descriptions above fit those limits; this copy change does not verify ASC setup or change product IDs, prices, trial or entitlement policy. [Apple field reference](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information).
