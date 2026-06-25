# Gemini Startup Guide for MacroMark

Read `AGENTS.md` first. It is the canonical repo-wide instruction file for MacroMark and contains the Swift, SwiftUI, SwiftData, reliability, build, and Xcode MCP rules.

Then read `CLAUDE.md` for the higher-level workflow notes: product context, the durability-first capture pipeline, documentation sync expectations, branch guidance, and preferred build/test commands.

## Session Checklist

- Preserve MacroMark's core reliability guarantee: no watch-side note or recording should be ACKed or deleted until the iPhone has durably processed it and exported it, or has safely queued it for retry.
- Check `ARCHITECTURE.md` before major refactors.
- Check `CODE_AUDIT.md`, `REMEDIATION_PLAN.md`, and `IMPLEMENTATION_PLAN.md` before touching sync, storage, macro processing, StoreKit/entitlements, logging, or watch transfer behavior.
- Use Swift 6.2+ patterns, SwiftUI with `@Observable`, async/await, `Task.sleep(for:)`, `FormatStyle`, and `os.Logger`.
- Avoid third-party dependencies unless the user explicitly approves them.
- Build the relevant iOS and watchOS schemes, and run focused tests when the change touches core logic.
