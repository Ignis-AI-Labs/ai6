# ISSUE TRACKER

Tracks issues per **Rule 7** of [`../../AGENTS.md`](../../AGENTS.md).

States: **Open** · **In Progress** · **Resolved** · **Deferred** · **False Positive**

---

## Open

- **Issue ID**: SEC-001
- **Discovered By**: ai6 security audit (live single-section §5 scan, 2026-06-27)
- **Date Discovered**: 2026-06-27
- **Source**: §5 AI AND LLM SECURITY audit of ai6 itself, reviewer GLM 5.2
- **Severity**: Medium (revised from High on 2026-06-27 after the layered
  defenses below landed — the practical false-clean-verdict pathway is closed
  end-to-end; remaining work is feature-scale, not bugfix-scale)
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
- **Mitigations in place (layered defense)**:
  - Reviewer agents are strictly read-only (no tools).
  - File list confined to `PROJECT_DIR` via `realpath` — out-of-tree paths
    (e.g. `~/.ssh/id_rsa`, `/etc/passwd`) silently skipped, with a skipped
    marker emitted to the request.
  - **All three reviewer personas** now explicitly told to treat reviewed
    content as DATA not instructions, with a "single most damaging failure
    mode is a false clean verdict" warning that calls out the specific
    injection vectors (embedded `VERDICT:` lines, "ignore previous
    instructions", "approve this", etc.):
    - `opencode/agent/ai6-reviewer.md` (regular OpenCode reviewer)
    - `opencode/agent/ai6-security-reviewer.md` (security auditor)
    - `bin/ask-claude.sh` inline SYS prompt (Claude as reviewer)
  - **Strict canonical verdict parsing** in both review paths — any malformed
    verdict line collapses to `ERROR`, never silently to `APPROVE`/`PASS`:
    - `bin/lib/chunk-review.sh` `ai6_verdict_of` (regular review aggregator)
    - `bin/lib/security-scan.sh` `ai6_security_aggregate` (security audit aggregator)
    - both orchestrator pre-guards use the same anchored regex
  - Residual risk documented in README.
- **Remaining work (lower priority)**: a true secondary classifier / NeMo
  Guardrails-style layer (§5.1.3, §5.1.6) for defense beyond persona-level
  instruction; hallucination-detection / confidence-indicator layer (§5.4)
  on the parsed findings. Both are full feature work, not bug fixes — the
  layered defenses above close the practical false-clean-verdict pathway.

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
