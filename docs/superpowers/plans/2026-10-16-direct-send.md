# Direct Send implementation plan

**Goal:** Deliver watch text directly to GitHub and/or a webhook without relying
on the phone after setup.

**Architecture:** MacroMarkKit owns capture routing, an atomic text outbox,
validated versioned settings, request construction and GitHub transactions. Watch
code owns WatchConnectivity phone delivery, OS background uploads and lifecycle.
The iPhone configures destinations; the widget reads shared pending state.

**Tech stack:** Swift 6, SwiftUI, Swift Testing, Foundation URLSession, Keychain,
WatchConnectivity and WidgetKit. No new dependencies or SwiftData schema changes.

**Spec:** ../specs/2026-10-16-direct-send-design.md

## Constraints and review focus

- Keep v1.0 isolated and preserve free access and the existing audio ACK path.
- Snapshot route and capture-day offset; never fall back from Direct to Phone.
- Persist before deleting; corrupt/unwritable queues must fail closed.
- Track partial fan-out success through relaunch and changed setup.
- Reconcile existing background tasks before creating another upload.
- Keep all credentials in versioned Keychain entries, not outbox/widget storage.
- Webhook UUIDs require receiver deduplication; HTTP acceptance is not bot completion.
- Local Apple builds/tests use the scheduling wrapper. Do not override its hours.

## Tasks

1. [ ] Add focused Swift Testing cases in MacroMarkKit/Tests/MacroMarkKitTests
   for immutable routes/dates, migration, partial completion, atomic-save failure
   and backoff. Implement CapturedNote, TextDeliveryQueue and configuration models
   in MacroMarkKit/Sources/MacroMarkKit/Delivery. Verify with package tests.
2. [ ] Add HTTP contract tests for GitHubRoute, WebhookRoute and GitHubDeviceFlow.
   Implement injectable URLSession requests, SHA/conflict/UUID handling and
   bounded sign-in polling. Verify all package tests.
3. [ ] Integrate versioned Keychain setup, PhoneRoute, atomic text outbox and
   background webhook task recovery into the watch. Preserve phone/audio behavior
   and add watch ACK/migration regressions. Build watch and iOS targets.
4. [ ] Add iPhone Direct Send settings/device-code sign-in and a durable setup
   acknowledgment. Add watch pending/error/reply views and an App Group-backed
   pending/replies complication. Verify target configuration and builds.
5. [ ] Reread privacy/user/developer documentation against the implementation.
   Run relevant tests, review the final diff, push a PR to nightly, inspect hosted
   CI and fix introduced failures. Keep the PR held while the v1.0 gate or a
   concrete integration blocker remains. Report live service/device proof
   separately from local/hosted checks.

Execution remains in the current session under Dan's standing implementation
authorization. The supplied spec and project preferences take precedence over
additional skill approval handoffs.
