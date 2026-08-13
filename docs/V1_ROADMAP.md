# MacroMark v1.0 Roadmap

Generated: 2026-06-25
Last synchronized: 2026-07-01

MacroMark v1.0 is the trust-and-capture release: Apple Watch quick capture for Markdown daily notes, with enough reliability, visibility, setup proof, and launch polish that users can trust it with fleeting thoughts.

This roadmap is based on:
- Competitor review research in `docs/competitive-analysis.md`.
- Reliability findings in `CODE_AUDIT.md`, `REMEDIATION_PLAN.md`, and `IMPLEMENTATION_PLAN.md`.
- Current launch setup in `docs/KICKSTART_POPULATION.md` and `docs/SETUP_TASKS.md`.

## Implementation Status - 2026-07-01

Implemented in the v1 integration line:
- Export status model and retryable pipeline state for processed notes.
- Inbox export status, needs-attention filtering, detail status, and manual retry.
- App Intents for instant capture, typed capture, daily-log review, and append text.
- Daily-note formatting controls for timestamp style, separators, and optional headings.
- Destination setup proof with active destination, test note, and last successful export details.
- Bounded speech authorization, chunk transcription, and location waits, with visible partial-transcription warnings.
- Stale Watch ACK reconciliation for queued notes/audio after lost acknowledgements.
- Launch privacy artifacts: app and Watch privacy manifests, privacy policy page, terms page, homepage privacy/support anchors, and local fastlane metadata.

Verified so far:
- Package tests and generic iOS/watchOS builds passed in Tasks 1-6 as recorded in `.superpowers/sdd/task-*-report.md`.
- Task 7 watch build and watch tests passed after a simulator boot retry.
- Task 8 text checks cover the privacy manifests and metadata files without running Xcode builds.

Still manual or pending before App Store submission:
- StoreKit annual/lifetime product loading, purchase, and restore need local StoreKit verification.
- Screenshots, App Store Connect privacy answers, Accessibility Nutrition Labels, and a paired iPhone/Apple Watch smoke test remain release gates.
- Kickstart/App Store Connect refresh on 2026-07-01 shows App Store ID `6785081218`, optimization score 89/100, one `en-US` localization, zero Accessibility Nutrition Label declarations, zero customer reviews, zero editorial nominations, and zero processed TestFlight builds.
- GitHub Pages is configured as `main /docs`. The homepage is live, but `privacy.html` returned 404 before this sync because the privacy and terms pages existed on `nightly` but had not reached `main`.
- `origin/main` contains the current release-train automation through PR #90, while `origin/nightly` contains newer v1 product/docs work through PR #87. Reconcile this branch split before final release.
- The current App Store checklist and next ten shipping steps live in `docs/APP_STORE_READINESS.md`.

## v1.0 Positioning

**Primary promise:** Tap the Watch, speak, lower your wrist, and the note safely lands in a dated Markdown file.

**Target users:** Apple Watch users, PKM users, Obsidian/Logseq users, daily-note users, and people who capture while walking, working, commuting, or otherwise away from a keyboard.

**What v1.0 is not:** A full notes database, AI meeting recorder, general dictation keyboard, or Markdown editor.

## Release Principles

1. **No silent loss.** A captured note must remain retryable until iPhone-side durability and configured export are complete or safely queued.
2. **Trust is visible.** Users should be able to see whether a capture is pending, delivered, processing, exported, deferred, or failed.
3. **The Markdown file is the source of perceived success.** "Saved" should mean the user can find the note in the expected daily note or see why it is still retrying.
4. **Capture stays fast.** Setup, upgrade prompts, review prompts, and correction flows must not interrupt the capture moment.
5. **v1.0 stays narrow.** Ship the capture bridge well; defer full editor, AI summaries, collaboration, and broad destination automation.

## Milestone 1: Reliability Core

**Goal:** Eliminate launch-blocking data-loss and crash risks before adding polish.

### Scope

- ACK watch payloads only after SwiftData save and configured export have succeeded or are safely queued for retry.
- Return distinct iCloud append outcomes: appended, deferred, failed.
- Treat un-materialized iCloud daily files as deferred exports, not dropped appends.
- Keep Watch-side payloads queued until iPhone durability and export safety are proven.
- Add retry processing for deferred exports.
- Lock the `MacroProcessor` regex cache.
- Invalidate macro regex cache after add, edit, delete, move, and restore-default mutations.
- Remove watchOS semaphore waits from audio capture paths.
- Preserve idempotency for replayed note, audio, and ACK messages.

### Acceptance Criteria

- A note captured while iCloud append is deferred remains queued and retries later.
- A note is not ACKed to the Watch before export success or safe retry state.
- Replayed payloads do not duplicate user-visible Markdown entries.
- Concurrent macro processing does not race or crash.
- Editing a macro trigger immediately affects future captures.
- Watch audio enqueue does not block cooperative threads.

### Verification

- Package tests for macro processing, cache invalidation, and concurrent processing.
- App tests or focused integration tests for ACK-after-export, deferred export retry, and idempotency.
- iOS generic build succeeds.
- watchOS generic build succeeds.

## Milestone 2: Capture Status And Recovery

**Goal:** Make the reliability model understandable to users.

### Scope

- Show capture/export states in the iPhone inbox:
  - Pending
  - Delivered
  - Processing
  - Exported
  - Deferred, retrying
  - Failed, needs attention
- Add an "Unexported" or "Needs Attention" filter on iPhone.
- Show pending/offline captures on Watch with enough context to reassure the user.
- Add manual retry or resend where a retry is safe.
- Add a support/debug export for queued payload metadata, excluding secrets.

### Acceptance Criteria

- A user can tell whether a capture has reached the Markdown file.
- Deferred exports explain that the app is waiting for iCloud materialization or destination availability.
- Failed exports offer a retry path instead of appearing as completed.
- Watch pending captures do not become invisible or permanent zombies after lost ACKs.

### Verification

- Manual walkthrough for offline Watch capture, reconnect, deferred export, retry, and failure messaging.
- Unit tests for status transitions where practical.

## Milestone 3: Daily Note Review By Date

**Goal:** Let users confirm and browse what MacroMark captured for a selected day.

The date picker work currently in progress belongs in this milestone.

### Scope

- Add a date picker for selecting a daily note date.
- Display captures/log content for the selected date.
- Support Today as the default selection.
- Provide clear empty, loading, unavailable, and error states.
- Reflect export state when selected-date content is incomplete or still retrying.
- Keep this as a review/readback surface, not a full Markdown editor.

### Acceptance Criteria

- A user can answer: "I captured this yesterday; can I find it today?"
- Selecting a date with no captures shows a calm empty state.
- Selecting a date whose iCloud file is unavailable or still downloading shows a retryable state.
- Today's Daily Log on Watch and the iPhone date picker agree on date boundaries and file naming.

### Verification

- Manual test across today, yesterday, a date with no captures, and a date with deferred exports.
- Unit tests for date-to-filename formatting and selected-date filtering if the logic is factored outside views.

## Milestone 4: App Intents And Shortcuts

**Goal:** Make fast capture available from system surfaces without opening the app manually.

### Scope

- App Intent: start instant capture.
- App Intent: start typed capture.
- App Intent: append provided text to today's note.
- App Intent: open today's daily log.
- If the selected-date review architecture supports it cleanly, add an intent to open a specific date.
- Document supported Shortcut actions in README and the website.

### Acceptance Criteria

- Users can trigger core capture flows from Shortcuts/Siri where platform APIs allow.
- Intent execution never bypasses durability rules.
- Intent failures return understandable errors.

### Verification

- Manual Shortcuts execution on device or simulator where supported.
- iOS build gate.
- watchOS build gate when Watch entry points are affected.

## Milestone 5: Destination Setup Proof

**Goal:** Reduce setup confusion for iCloud, Markdown, and Obsidian-style workflows.

### Scope

- Show the exact active export destination.
- Show the exact daily-note filename pattern.
- Add "write a test note" for the configured destination.
- Show the last successful export path and timestamp.
- Explain iCloud Drive behavior and Obsidian/Logseq expectations in setup copy.
- Make folder customization understandable and gated consistently with Pro.

### Acceptance Criteria

- A new user can prove the destination works before relying on Watch capture.
- If iCloud is unavailable, the app shows fallback/pending behavior without implying success.
- The setup flow avoids account gates and does not force users into non-local services.

### Verification

- Manual first-run setup on a clean install.
- Manual test note append to the configured destination.
- Privacy-sensitive path logging remains behind `os.Logger` privacy controls or debug-only output.

## Milestone 6: Daily Note Formatting

**Goal:** Make exported Markdown feel intentional, scannable, and compatible with daily-note workflows.

### Scope

- Configurable timestamp prefix.
- Configurable separator between captures.
- Optional append-under-heading behavior.
- Optional tags or spoken tag helpers.
- Frontmatter-safe append rules.
- Macro preview/test mode for validating spoken trigger output before relying on it.

### Acceptance Criteria

- Users can configure a daily-note shape without writing scripts.
- Appends do not corrupt YAML frontmatter.
- Macro preview shows the exact Markdown that will be inserted.
- Existing defaults still produce clean `YYYY-MM-DD.md` notes with accurate origin timestamps.

### Verification

- Unit tests for formatter output, heading append, separators, frontmatter behavior, and macro preview.
- Manual export to at least one Obsidian-readable daily note.

## Milestone 7: Transcription Integrity

**Goal:** Never silently save incomplete or misleading speech output.

### Scope

- Mark partial transcription when any audio chunk fails.
- Join long-recording chunks with a safe separator.
- Surface warning badges in the inbox, detail view, and selected-date review.
- Preserve or retry raw audio until transcription/export is confirmed where feasible.
- Add timeouts for speech authorization and `{location}` resolution.
- Avoid unbounded continuations during WAL replay.
- Use clear error copy for speech unavailable, location unavailable, partial transcript, and retry states.

### Acceptance Criteria

- A partial transcript is visibly marked.
- Long recordings do not disappear when one chunk fails.
- WAL replay cannot hang forever on speech or location.
- Users know whether a capture is complete, partial, or waiting for retry.

### Verification

- Unit or integration tests with a mocked transcriber chunk failure.
- Manual long-recording test.
- Manual `{location}` timeout test.

## Milestone 8: Launch Monetization And App Store Readiness

**Goal:** Ship v1.0 with clear value, fair monetization, and App Store-ready assets.

### Scope

- Keep core capture and review useful in the free tier.
- Pro unlocks power features:
  - Unlimited macros.
  - Default macro editing.
  - Folder customization.
  - Advanced formatting/customization if implemented for v1.0.
- Keep the lifetime purchase option prominent.
- Finish StoreKit products:
  - `com.macromark.subscription.annual`
  - `com.macromark.lifetime`
- Validate restore purchases and entitlement behavior.
- Complete App Store metadata, screenshots, privacy policy, privacy manifest, and TestFlight readiness.
- Update README and GitHub Pages to match v1.0 scope.

### Acceptance Criteria

- Upgrade prompts do not interrupt capture.
- Free users can understand and trust the core workflow.
- Pro gates are consistent and recover correctly after restore purchases.
- App Store Connect metadata matches the product users will receive.
- TestFlight build has no P0/P1 reliability issues.

### Verification

- StoreKit local purchase, restore, annual trial, and lifetime purchase tests.
- App Store privacy manifest review.
- iOS generic build succeeds.
- watchOS generic build succeeds.
- `swift test --package-path MacroMarkKit` succeeds.
- TestFlight smoke test on paired iPhone and Apple Watch.

## Release Phases

### Phase 0: Stabilize Active Work

- Land the in-progress date picker work cleanly.
- Confirm it reads from the same date/file model used by export.
- Avoid overlapping edits to the date-picker files until the active work is merged.

### Phase 1: No Data Loss

- Complete Milestone 1.
- Complete the status foundation needed by Milestone 2.
- Do not start App Store submission work until this phase passes.

### Phase 2: Prove The Promise

- Complete Milestones 2, 3, 5, 6, and 7.
- Run real-device tests for offline Watch capture, reconnect, date review, destination setup proof, and partial transcription.

### Phase 3: Fast Capture Everywhere

- Complete Milestone 4.
- Verify App Intents and Shortcuts do not bypass durability or export-state rules.

### Phase 4: Ship

- Complete Milestone 8.
- Produce App Store screenshots around the v1.0 story:
  1. Tap Watch, speak, lower wrist.
  2. Capture survives offline.
  3. Browse notes by date.
  4. Notes append to `YYYY-MM-DD.md`.
  5. Speak Markdown with macros.
  6. Prove the destination works.
  7. Customize macros and folder with Pro.

## v1.0 Release Gates

v1.0 is not ready until all gates pass:

- No known P0 or P1 data-loss issues remain.
- Watch capture works offline and reconciles after reconnect.
- iPhone export state matches actual Markdown output.
- Date picker can display today, yesterday, empty dates, and unavailable/deferred dates.
- Deferred iCloud appends retry without duplicate Markdown entries.
- Macro edits affect future captures immediately.
- Partial transcription is visible.
- StoreKit purchase and restore flows work.
- Privacy manifest and App Store privacy answers match actual data use.
- iOS and watchOS generic builds succeed.
- `swift test --package-path MacroMarkKit` succeeds.
- At least one TestFlight smoke test passes on paired physical devices.

## Final v1.0 Verification Notes

- Package tests: passed on 2026-06-28 with `swift test --package-path MacroMarkKit`.
- iOS generic build: passed on 2026-06-28 with the Debug `MacroMark` scheme.
- watchOS generic build: passed on 2026-06-28 with the Debug `MacroMark Watch App` scheme.
- Fastlane release automation: `origin/main` now contains the release-train API-key, signing-profile, and nightly-only internal TestFlight workflow fixes through PRs #88-#90. `origin/nightly` has not yet received those main-only release automation commits.
- TestFlight visibility: Kickstart refresh on 2026-07-01 still reports `buildCount: 0`, so no processed TestFlight build is visible yet.
- StoreKit local purchase/restore test: not run yet; release remains blocked until annual, lifetime, purchase, restore, and free capture paths pass locally.
- Paired-device smoke test: not run yet; release remains blocked until this passes on the tested iPhone and Apple Watch models.
- Public GitHub Pages privacy/support/terms URLs: this sync brings the pages to the `main /docs` Pages source; verify live `privacy.html` and `terms.html` again after merge and rebuild.
- Known v1.1 deferrals: none selected yet.

## Deferred To v1.1+

- AI summaries or rewriting.
- Full Markdown editing.
- Collaboration.
- Non-iCloud cloud destinations.
- Attachments and media capture beyond any already-supported v1.0 paths.
- Advanced automation marketplace.
- Analytics dashboards.
- Localization beyond launch metadata unless required before submission.

## Public Messaging

Use this as the v1.0 through-line in README, GitHub Pages, screenshots, and App Store copy:

> Apple Watch quick capture for your Markdown daily notes.

Supporting claims must stay tied to shipped behavior:
- Watch-first capture.
- Plain-text Markdown daily notes.
- No account.
- Durable queue and retry.
- Browse captures by date.
- Spoken Markdown macros.
- Setup proof for the destination.
