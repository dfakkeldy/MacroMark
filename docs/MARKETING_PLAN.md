# MacroMark Marketing Plan

Last synchronized: 2026-07-01

MacroMark is a pre-launch freemium/subscription productivity utility: free Apple Watch and iPhone capture for Markdown daily notes, with MacroMark Pro planned for power-user limits and customization. This plan is intentionally light on high-contact social work and heavy on reusable assets, App Store readiness, and a calm weekly public record.

## App Profile

| Attribute | Value |
| --- | --- |
| Category | Productivity |
| Platforms | iOS and watchOS |
| Lifecycle stage | Pre-launch, planned launch 2026-08-04 |
| Monetization | Free download; Pro annual subscription planned at $4.99/year; lifetime unlock planned at $12.99 |
| Audience | Markdown daily-note users, Apple Watch users, Obsidian/Logseq users, field workers, walkers/commuters, PKM power users |
| Current traction | No TestFlight builds or customer reviews visible in the 2026-07-01 Kickstart refresh |
| Current ASO | 89/100 score; one `en-US` localization; title short; no Custom Product Pages, In-App Events, or Promoted IAP configured |

## Positioning

Primary line:

> Apple Watch quick capture for your Markdown daily notes.

Supporting proof:

- Tap the Watch, speak or type, and append to a dated Markdown file.
- Plain text stays in user-controlled iCloud Drive.
- Durable Watch-to-iPhone delivery keeps captures retryable.
- Spoken macros turn voice triggers into Markdown structure, dates, times, reusable text, and optional location.
- No account, no third-party analytics in the v1.0 plan.

Avoid positioning MacroMark as an AI meeting recorder, a full notes database, a general dictation keyboard, or an Obsidian replacement.

## Strategic Goals

1. Get to a credible first App Store submission without preventable metadata, privacy, screenshot, or TestFlight blockers.
2. Give the product page a sharp default story before spending effort on split testing or paid campaigns.
3. Build a small, reviewable launch surface through GitHub Pages, devlog updates, App Store metadata, and low-contact outreach.

## Recommended Features: Eligible Now

### High Priority

#### App Store Assets

- **Why:** Screenshots and the first three product-page beats matter before MacroMark has enough traffic for A/B tests.
- **Effort:** Significant, but required for launch.
- **Impact:** Improves product-page conversion and prevents App Review/metadata churn.
- **Action:** Use the existing screenshot pipeline to produce a sequence around Watch capture, durable retry, date review, Markdown daily-note append, spoken macros, destination proof, and Pro customization.

#### Introductory Offer

- **Why:** The annual subscription needs a low-friction trial path, and the planned pricing already mentions a free trial.
- **Effort:** Quick win in App Store Connect once products are configured.
- **Impact:** Helps convert curious users without undermining the lifetime option.
- **Action:** Configure the annual subscription trial, then verify StoreKit purchase, restore, trial, lifetime, and free-tier behavior locally before upload.

#### Promoted IAP

- **Why:** MacroMark Pro is a simple unlock story. Showing it on the product page can make the business model clear without hiding the free capture promise.
- **Effort:** Moderate; requires finalized IAP metadata and review screenshot.
- **Impact:** Clarifies Pro value and supports App Store discovery for the paid tier.
- **Action:** Promote the Pro unlock only after products, pricing, paywall copy, and restore behavior are confirmed.

#### Featuring Nomination

- **Why:** MacroMark has a focused Apple-platform angle: Apple Watch, Shortcuts/App Intents, privacy-respecting plain text, and a real solo-builder workflow.
- **Effort:** Quick win.
- **Impact:** High upside, no traffic threshold.
- **Action:** Submit a nomination when screenshots, TestFlight proof, and the v1 story are stable. Angle it around Apple Watch productivity, Markdown workflows, and privacy/no-account capture.

#### Weekly Build-In-Public Devlog

- **Why:** The repo already has an automated devlog pipeline, and the best current marketing surface is the work itself.
- **Effort:** Low ongoing cost.
- **Impact:** Builds trust, gives press/users a source of truth, and creates reusable launch copy.
- **Action:** Keep one weekly source-of-truth update on GitHub Pages, then manually adapt only the best parts to one or two official accounts.

## Medium Priority

#### Pre-Order

- **Why:** Pre-launch apps can collect intent before release, but only if the product page is credible.
- **Effort:** Moderate.
- **Impact:** Useful after screenshots, privacy URLs, pricing, and launch date are locked.
- **Action:** Do not turn on pre-order until a processed TestFlight build exists and the first product-page assets are final.

#### Offer Codes

- **Why:** Useful for reviewers, friendly testers, and small partner outreach.
- **Effort:** Low to moderate.
- **Impact:** Good for hand-picked distribution; not an email campaign yet.
- **Action:** Prepare a small reviewer/tester batch after StoreKit products are approved.

#### In-App Event

- **Why:** Productivity apps can use lightweight feature spotlight events, but MacroMark should not invent a challenge loop just for App Store tooling.
- **Effort:** Moderate.
- **Impact:** Better shortly after launch or with a meaningful update.
- **Action:** Plan a launch-month event around "Turn your Watch into a Markdown capture button" only after the app is live or pre-order is active.

## Not Recommended Yet

| Feature | Minimum Needed | Current State | Revisit When |
| --- | --- | --- | --- |
| Product Page Optimization | About 1,000 impressions/week | Pre-launch, no visible build/reviews | App Store page has enough traffic for a meaningful test |
| Custom Product Pages | About 5,000 impressions/month or distinct paid campaigns | Single focused audience, no paid campaigns | There is enough traffic to split by Obsidian users, field workers, or Apple Watch users |
| Win-Back Offers | About 100+ churned subscribers | No subscribers yet | There is real churn to recover |
| Promotional Offers | Active subscriber base with churn risk | No subscribers yet | MacroMark has at-risk subscribers |
| Search Ads | Final product page, screenshots, tested keywords, and a live build | Still pre-launch | After product-page basics and first conversion signals |

## Launch Calendar

| Date Range | Focus | Actions |
| --- | --- | --- |
| Jul 1-7 | Proof and metadata | Get first internal TestFlight build visible; finish StoreKit product setup; verify privacy/terms/support URLs on Pages; review competitor screenshots and copy |
| Jul 8-14 | Assets and reviewer path | Capture App Store screenshots; write final App Store description; configure promoted IAP metadata; prepare small offer-code/reviewer list |
| Jul 15-21 | Public story | Publish a useful devlog update; draft feature/behind-the-scenes demo assets; prepare featuring nomination; confirm support path |
| Jul 22-28 | Submission rehearsal | Run paired iPhone/Watch smoke test; complete accessibility labels; finalize review notes, age rating, export compliance, and privacy answers |
| Jul 29-Aug 4 | Launch | Submit final launch build; prepare launch posts; update Pages CTA to the live App Store listing after approval |

## Implementation Order

1. Finish TestFlight, StoreKit, privacy, and screenshot blockers.
2. Update the default product page: title, subtitle, keywords, screenshots, description, support/marketing/privacy URLs.
3. Configure introductory offer and promoted IAP.
4. Submit featuring nomination.
5. Keep the weekly devlog running and adapt one short post from it manually.
6. Prepare a small, direct outreach list for people who already care about Markdown, Apple Watch capture, Obsidian, Logseq, or PKM.
7. Revisit custom product pages, product page optimization, and Search Ads only after traffic exists.

## Measurement

Track these first, in order:

- First visible TestFlight build and tester invites.
- App Store product-page completion.
- Screenshot upload completion.
- Pre-order or launch page visits.
- Product page views to downloads.
- Download to first successful capture.
- First successful capture to retained day-two usage.
- Free to Pro conversion.
- Support/contact themes.

Do not optimize paid acquisition before the first successful-capture and day-two retention signals are credible.
