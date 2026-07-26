# Gemini Startup Guide for MacroMark

Read `AGENTS.md` first; it is the canonical repository guide. Read `CLAUDE.md`
only for its concise product context.

- Preserve the ACK and deletion durability invariant for every capture.
- Read `ARCHITECTURE.md` for major architecture work and the audit/remediation
  documents only when their reliability areas are in scope.
- Follow established Swift, SwiftUI, and concurrency patterns in touched code.
- Do not add third-party dependencies without explicit authorization.
- Run the relevant build or focused tests for code changes; instruction-only
  edits do not require an app build.
