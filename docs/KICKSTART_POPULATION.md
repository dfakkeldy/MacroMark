# MacroMark — Kickstart Population Package

> **Status:** ✅ APPLIED 2026-06-20; refreshed 2026-07-01. The project was created manually in the Kickstart app
> (the MCP `create_project` endpoint was failing — 7/7 connection drops; all other write
> endpoints worked fine). Launch date set to **Aug 4, 2026**. Applied: project record +
> full press kit, competitors, tracked keywords (with baseline snapshots), an "App
> Launch Checklist" template + "v1.0 Launch" instance (57 items), and a kickoff journal
> entry, plus the live **website** at https://dfakkeldy.github.io/MacroMark/ (GitHub Pages,
> `main /docs`). Kickstart now tracks App Store ID `6785081218`, website/support metadata,
> 20 competitors, and one `en-US` App Store localization. Still open: first visible
> TestFlight build, Accessibility Nutrition Labels, pricing/free-vs-paid confirmation, and
> final competitor screenshot/copy review.
> This file remains the source of truth for App Store Connect / fastlane metadata.
>
> Data sourced from: repo (`README.md`, `MacroMarkKit/Configuration.storekit`,
> `fastlane/README.md`, `MacroMark.xcodeproj/project.pbxproj`), the developer's existing
> "Audiobook Study Player: Echo" Kickstart project (for conventions), and live App Store
> keyword-ranking lookups via `check_keyword_rankings` (US, iOS, 2026-06-20).

---

## 1. Project record  (`create_project` → then `update_project`)

| Field | Value |
|---|---|
| **name** | MacroMark |
| **tagline** | Zero-friction voice capture for your Markdown vault |
| **supportEmailAddress** | dan@kinnokilabs.com |
| **websiteAddress** | https://dfakkeldy.github.io/MacroMark/ (GitHub Pages, `main /docs`) |
| **launchDate** | Aug 4, 2026 (set in app) |
| **appStoreAppID / appStoreURL** | `6785081218` / https://apps.apple.com/app/id6785081218 |

**description** (internal):

> MacroMark is a zero-friction, voice-to-text capture tool for personal knowledge
> management (PKM) power users, centered on Apple Watch. Tap a complication, speak, and
> lower your wrist — the note is saved instantly with an accurate, watch-generated
> timestamp and synced to plain-text Markdown daily notes (YYYY-MM-DD.md) in iCloud Drive,
> ready for Obsidian, Logseq, and other Markdown tools. Highlights: a Liquid Glass watch
> UI, an append-to-daily-note mechanic (one file per day instead of hundreds of
> fragments), and verbal macros (say "Heading One" for "# ", or insert
> {date}/{time}/{location} variables). Built for iOS 26 and watchOS 26 in Swift 6.2 /
> SwiftUI. Freemium: a free tier with limited macros, plus a Pro upgrade (Annual $4.99/yr
> with free trial, or Lifetime $12.99) unlocking unlimited macros, default-macro editing,
> and folder customization.

---

## 2. Press kit  (`update_project`)

| Field | Value |
|---|---|
| **pressKitCompanyName** | KinNoKi Labs |
| **pressKitContactName** | Dan Fakkeldy |
| **pressKitContactEmail** | dan@kinnokilabs.com |
| **pressKitAppPrice** | Free with Pro upgrade — Annual $4.99/yr (free trial) or Lifetime $12.99 |
| **pressKitMinimumOS** | iOS 26.5 / watchOS 26.5 |

> The Xcode project and Kickstart press kit agree on iOS 26.5 / watchOS 26.5 and
> **KinNoKi Labs** as the public company name.

**pressKitKeyFeatures:**

```
* Zero-friction capture: tap the watch complication, speak, lower your wrist — the note saves instantly with an accurate, watch-generated timestamp (no "Done" button, never times out on silence)
* Append-to-daily-note mechanic: every capture for a day appends to a single YYYY-MM-DD.md file instead of cluttering your vault with hundreds of fragments
* Verbal macros: speak trigger words to format text — say "Heading One" for "# ", or insert {date}, {time}, and {location} variables to build workflows
* Liquid Glass Apple Watch UI: large microphone and keyboard buttons for instant input selection, plus one-tap access to "Today's Daily Log"
* PKM-native: writes plain-text Markdown to a dedicated iCloud Documents folder, instantly readable by Obsidian, Logseq, and other Markdown tools
* Background sync: WatchConnectivity queues captures and delivers them to iPhone even in the background
* On-device dictation via SFSpeechRecognizer — no servers, your text stays in your vault
* Freemium: free tier with core capture; Pro unlocks unlimited macros, default-macro editing, and folder customization
```

**pressKitDeveloperBio** _(DRAFT — outward-facing; confirm before publishing)_:

> Dan Fakkeldy is a mail carrier from Canada who builds focused, privacy-respecting Apple
> apps in public under the KinNoKi Labs name. MacroMark grew out of his own need to capture
> fleeting thoughts mid-route without breaking stride — speak into the watch, lower the
> wrist, and the note lands in his Markdown vault. Built for iOS 26 and watchOS 26, in
> public from commit one.

**pressKitMarkdown** (press release) _(DRAFT)_:

> ## KinNoKi Labs launches MacroMark — zero-friction voice capture for your Markdown vault
>
> MacroMark turns the Apple Watch into the fastest way to get a thought into your
> knowledge base. Tap the complication, speak, and lower your wrist: the note is saved
> instantly with an accurate, watch-generated timestamp and synced as plain-text Markdown
> to iCloud Drive — ready for Obsidian, Logseq, and any Markdown tool.
>
> Instead of scattering hundreds of tiny files, MacroMark appends each day's captures to a
> single `YYYY-MM-DD.md` daily note. Verbal macros let you format by voice ("Heading One"
> → `# `) and drop in `{date}`, `{time}`, and `{location}` variables. The watchOS app uses
> a Liquid Glass interface with large microphone and keyboard buttons and one-tap access to
> today's log.
>
> MacroMark is free to start, with a Pro upgrade (Annual $4.99/yr with a free trial, or
> $12.99 Lifetime) that unlocks unlimited macros, default-macro editing, and folder
> customization. Requires iOS 26.5 and watchOS 26.5.

---

## 3. App Store Optimization (ASO) metadata

From `fastlane/README.md`, lightly refined against live keyword data:

| Field | Value | Notes |
|---|---|---|
| **Title** | MacroMark: Zero-Friction Notes | 30-char budget — fits |
| **Subtitle** | Voice memos to Markdown, timestamped | tightened from fastlane's longer version |
| **Keywords** | `pkm,markdown,voice,dictation,obsidian,logseq,apple watch,quick capture,second brain,daily notes,note taking,transcribe` | 100-char field; comma-separated, no spaces after commas to save chars |

---

## 4. Competitors  (`add_competitor`, by integer App Store ID)

Ranked by relevance to MacroMark's exact value prop (voice / quick capture -> Markdown / PKM,
or Apple Watch capture). Seed IDs were verified on 2026-06-20; Kickstart refresh on
2026-07-01 reports 20 tracked competitors, so this table is the seed set rather than the
complete current tracking list.

| # | App | App Store ID | Why it's a competitor |
|---|---|---|---|
| 1 | Drafts (Agile Tortoise) | `1236254471` | The canonical "capture text first, act later" app — closest functional rival |
| 2 | Voice Inbox for Obsidian | `6452678291` | Voice → Obsidian; nearly identical capture-to-PKM premise |
| 3 | Quick Capture - Vault notes | `6737046871` | Quick capture straight into an Obsidian vault |
| 4 | Bear - Markdown Notes (Shiny Frog) | `1016366447` | Leading Markdown notes app with an Apple Watch app |
| 5 | Obsidian - Connected Notes (Dynalist) | `1557175442` | The PKM destination MacroMark feeds into |
| 6 | NotePlan - To-Do List & Notes | `1505432629` | Markdown daily-note app — direct overlap on the append-to-daily-note model |
| 7 | Voicenotes AI Notes & Meetings | `6483293628` | Voice-notes leader with a watch capture flow |
| 8 | Notes for Apple Watch (Kpaw) | `1453148171` | Category leader for "apple watch notes" |
| 9 | Nano Notes | `1445942906` | Popular Apple Watch quick-notes app |
| 10 | Taio - Markdown & Text Actions | `1527036273` | Markdown + text automation (overlaps the macro feature) |
| 11 | Otter Transcribe Voice Notes | `1276437113` | Dominates voice/transcription keywords |
| 12 | Wispr Flow: AI Voice Keyboard | `6497229487` | Current breakout in voice → text input |
| 13 | Funnel - Quick Capture | `6466168248` | Quick-capture inbox app |
| 14 | Supernotes – Notes & Journal | `1567815218` | Markdown notes/journal with sync |

---

## 5. Tracked keywords  (`track_keyword`)

Difficulty (D) / Entry barrier (B) measured live 2026-06-20 (US/iOS), /100.

| Keyword | D | B | Verdict |
|---|---|---|---|
| quick capture | 24 | 10 | ⭐ Best opportunity — low difficulty, highly relevant |
| second brain | 29 | 93 | ⭐ Low difficulty, relevant |
| obsidian | 55 | 39 | ⭐ Relevant, approachable |
| apple watch notes | 57 | 77 | Relevant, defining feature |
| markdown notes | 70 | 6 | Relevant; low barrier despite difficulty |
| dictation | 70 | 100 | Aspirational (Apple/Otter/Speechify dominate) |
| voice to text | 71 | 59 | Aspirational |
| speech to text | 72 | 83 | Aspirational |
| voice notes | 76 | 82 | Aspirational |
| markdown editor | 46 | 0 | ⭐ Strong — low difficulty, zero entry barrier, on-target (Bear/Obsidian/Drafts/Taio rank) |
| logseq | 52 | 39 | ⭐ Relevant niche — Logseq #1, Obsidian #2 |
| daily notes | 64 | 93 | Relevant feature; journaling/planner apps dominate |
| pkm | 69 | 34 | ⚠️ Pokémon intent pollution (Pokémon GO/Masters/TCG top the list) — low value; consider dropping |
| note taking | 88 | 87 | Long-term — Goodnotes/Notability/OneNote/Notion category giants |

---

## 6. Launch checklist  (`create_checklist_template` → `create_checklist_instance`)

Use the default template (`useDefault: true`) for a "v1.0 Launch" instance, then add
MacroMark-specific items. Project-specific pre-launch items to ensure are covered:

- Resolve the open `docs/SETUP_TASKS.md` Xcode steps (SPM package, target membership, StoreKit config)
- Confirm iCloud Documents container ID is provisioned for the production App ID
- App Privacy: declare microphone + speech recognition usage; Privacy Manifest present
- StoreKit: products approved in App Store Connect (`Annual $4.99` autorenew + `Lifetime $12.99` non-consumable), restore-purchases verified
- watchOS complication / `macromark://capture/instant` deep link verified on device
- Screenshots: iPhone + Apple Watch via fastlane snapshot
- Accessibility Nutrition Labels declared after an accessibility pass
- First internal TestFlight build visible in App Store Connect / Kickstart

---

## 7. Application order (once unblocked)

1. `create_project` (name, tagline, description, supportEmailAddress)
2. `update_project` (press kit fields, website + launchDate when known)
3. `add_competitor` ×14
4. `track_keyword` ×14 (default `fetchNow: true` seeds first ranking snapshot)
5. `create_checklist_template` (useDefault) → `create_checklist_instance` "v1.0 Launch"
6. `add_journal_entry` — kickoff note recording this setup
7. `get_optimization_suggestions` + `get_competitor_analysis` — review and iterate
