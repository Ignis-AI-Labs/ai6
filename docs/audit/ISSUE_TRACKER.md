# ISSUE TRACKER

Tracks issues per **Rule 7** of [`../../AGENTS.md`](../../AGENTS.md).

States: **Open** · **In Progress** · **Resolved** · **Deferred** · **False Positive**

---

## Open

- **Issue ID**: SEC-001
- **Discovered By**: ai6 security audit (live single-section §5 scan, 2026-06-27)
- **Date Discovered**: 2026-06-27
- **Source**: §5 AI AND LLM SECURITY audit of ai6 itself, reviewer GLM 5.2
- **Severity**: High
- **Location**: `bin/lib/build-request.sh` (project-context injection into reviewer);
  bridges `bin/ask-glm.sh`, `bin/ask-claude.sh`; OpenCode plugin `opencode/plugin/ai6.js`
- **Description**: ai6 streams untrusted project content (file contents, git diff,
  AGENTS.md) verbatim into the reviewer model with only markdown fencing. Per
  §5.1 (Prompt Injection Defense) CRITICAL controls, no sanitization, no
  secondary classifier, and no input/output guardrails are deployed. A
  prompt-injection payload in a reviewed file or diff could in principle
  manipulate the verdict that gates whether code ships.
- **Evidence**: The §5 audit response identified §5.1.1 (sanitize external data),
  §5.1.3 (secondary classifier), §5.1.6 (guardrails), §5.4.1 (hallucination
  detection), §5.4.2 (confidence indicators), §5.6.3 (layered defense) as FAIL.
- **Partial mitigations already in place**: reviewer agents are strictly
  read-only (no tools); file list is confined to PROJECT_DIR via realpath;
  reviewer for the security scan now explicitly told to treat all project
  context as DATA not instructions (`opencode/agent/ai6-security-reviewer.md`).
- **Planned work**:
  - Extend the same DATA-not-instructions hardening to the general
    `ai6-reviewer` agent (still TODO).
  - ~~Output classifier pass on the parsed verdict~~ — done 2026-06-27 for the
    security path: `ai6_security_aggregate` now validates each per-section
    verdict against the canonical set (`PASS|NEEDS-WORK|BLOCK|ERROR`) and
    collapses anything else (typo, lowercase, trailing punctuation) to ERROR;
    the orchestrator's pre-guard uses the same strict regex. A false-clean
    verdict from a malformed reviewer response is no longer possible.
  - Document this residual risk in the README (still TODO).

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
