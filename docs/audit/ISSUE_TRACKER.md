# ISSUE TRACKER

Tracks issues per **Rule 7** of [`../../AGENTS.md`](../../AGENTS.md).

States: **Open** · **In Progress** · **Resolved** · **Deferred** · **False Positive**

---

## Open

_None yet._

## In Progress

_None yet._

## Resolved

_None yet._

## Deferred

- **Issue ID**: PROC-001
- **Discovered By**: User (Elijah)
- **Date Discovered**: 2026-06-24
- **Source**: Code review of repo history
- **Severity**: Medium
- **Location**: `Ignis-AI-Labs/ai6` git history — every commit from `c17c9af`
  through `980b3b8` (the entire pre-2026-06-24 history)
- **Description**: Rule 2 violation. Every commit on this repo was pushed
  directly to `main` with no `dev` branch, no personal `<who>/dev` branch, and
  no PR flow. The protocol explicitly prohibits this. Silent deviation — never
  flagged in-line.
- **Evidence**: `git log --oneline main` shows a linear history on `main` with
  no merges; `gh api repos/Ignis-AI-Labs/ai6/branches` returned `["main"]` only.
- **Resolution**: Deferred (historical-only). Rewriting public history to
  retroactively route every bootstrap commit through PRs is more disruptive than
  the violation. Going forward, Rule 2 is amended to the personal `<who>/dev` →
  `dev` → `main` model and enforced strictly; this entry is the flag that the
  prior period was non-conforming.

## False Positive

_None yet._
