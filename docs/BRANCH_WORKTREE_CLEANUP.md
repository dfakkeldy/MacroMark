# MacroMark Branch And Worktree Cleanup

Last synchronized: 2026-07-01

This inventory is a cleanup map, not a deletion log. Do not remove a branch or worktree until its working tree is clean and any uncommitted user files have been saved or explicitly discarded.

## Current Repository Shape

- Open GitHub PRs: none.
- Open GitHub issues: #79-#86, all from the real-world bug hunt.
- GitHub Pages source: `main /docs`.
- `origin/main`: release automation fixes through PR #90.
- `origin/nightly`: v1 product/docs fixes through PR #87, but not PRs #88-#90.
- `origin/weekly`: last promotion merge is PR #17.

The release ladder is therefore split: `main` has newer release automation while `nightly` has newer product/readiness work. This should be reconciled before App Store submission.

## Active Worktree Inventory

| Path | Branch | State | Recommendation |
| --- | --- | --- | --- |
| `/Users/dfakkeldy/.codex/worktrees/2b73/MacroMark` | `codex/docs-sync-appstore-readiness` | Current docs/site worktree, based on `origin/main` for Pages deployment. | Keep until the docs/site PR is merged. |
| `/Users/dfakkeldy/Developer/MacroMark` | `codex/app-store-metadata` | Remote branch is gone. Committed branch content is already represented in `origin/nightly`, but this worktree has uncommitted `AGENTS.md`, `CLAUDE.md`, `.agents/skills/**`, and `skills-lock.json` changes. | Do not delete. Review the agent/skill changes and, if still wanted, isolate them into a separate agent-guidance PR. |
| `/Users/dfakkeldy/.codex/worktrees/6464/MacroMark` | `bug-hunt-loop/2026-06-29-cycle-1` | Remote branch is gone. Working tree clean. Bug-hunt fixes are represented by PR #87 on `origin/nightly`. | Cleanup candidate after confirming no local-only notes are needed. |
| `/Users/dfakkeldy/.codex/worktrees/ci-release-ladder-MacroMark` | `nightly` | Local branch is behind `origin/nightly` by 29 commits. Working tree clean. | Cleanup candidate; recreate from `origin/nightly` when needed instead of keeping a stale branch checked out. |
| `/Users/dfakkeldy/.codex/worktrees/eb9c/MacroMark` | `codex/disable-main-appstore-release` | Remote branch is gone. Working tree clean. Its committed workflow change is represented by PR #90 on `origin/main`. | Cleanup candidate after this docs PR records the release-routing state. |
| `/Users/dfakkeldy/.codex/worktrees/macromark-devlog-automation` | `codex/devlog-automation` | Remote branch is gone. Working tree clean. Devlog automation exists in repo history; this PR brings the AI-review-body helper to `main`. | Cleanup candidate after docs/site PR merges. |
| `/Users/dfakkeldy/Developer/MacroMark-release-train-automation` | `codex/fix-release-train-api-key` | Remote branch is gone. Working tree clean. API-key fix is represented by PR #22 on `origin/main`. | Cleanup candidate. |

## Branches Worth Keeping For Now

- `origin/main`: live Pages and release automation source.
- `origin/nightly`: active v1 integration branch.
- `origin/weekly`: promotion branch, stale but part of the ladder.
- `origin/chore/ci-release-ladder`, `origin/chore/release-train-match-url`, `origin/chore/secret-gitignore`, `origin/codex/v1-roadmap`, `origin/codex/dated-notes-*`, and `origin/claude/*`: still exist remotely; inspect before pruning.

## Separate Save Candidate

The dirty `/Users/dfakkeldy/Developer/MacroMark` worktree contains agent-guidance changes, not app/product docs:

- `AGENTS.md` changes the Xcode build-concurrency guidance to defer to `~/.claude/bin/xcode-build-gate.sh`.
- `CLAUDE.md` now imports `@AGENTS.md` and removes duplicated response rules.
- Several `.agents/skills/**` folders and `skills-lock.json` are untracked.

If these are intentional, save them as a dedicated PR rather than folding them into App Store/site docs.

## Cleanup Order

1. Merge or close the docs/site PR.
2. Create a separate agent-guidance PR from the dirty `/Users/dfakkeldy/Developer/MacroMark` worktree if those changes are still desired.
3. Reconcile `main` and `nightly` release/product divergence.
4. Remove clean, remote-gone worktrees one at a time.
5. Prune deleted remote refs and stale worktree registrations.

Suggested cleanup commands, after manual confirmation:

```bash
git worktree remove /Users/dfakkeldy/.codex/worktrees/6464/MacroMark
git worktree remove /Users/dfakkeldy/.codex/worktrees/ci-release-ladder-MacroMark
git worktree remove /Users/dfakkeldy/.codex/worktrees/eb9c/MacroMark
git worktree remove /Users/dfakkeldy/.codex/worktrees/macromark-devlog-automation
git worktree remove /Users/dfakkeldy/Developer/MacroMark-release-train-automation
git worktree prune
```

Do not run these against `/Users/dfakkeldy/Developer/MacroMark` until the dirty agent/skill changes are saved or intentionally discarded.
