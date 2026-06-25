# AGENTS PROTOCOL

**This file is law. Every agent operating in this repository — human-directed or
autonomous — reads it fully before touching anything.**

This is the single source of truth. `CLAUDE.md` and any other agent entrypoint
point here. Do not duplicate rules elsewhere; amend them here.

> **Using ai6 in your own project?** Run `bash ~/.ai6/ai6-init.sh` from your project
> root to scaffold this file (and a `CLAUDE.md` pointer), or copy it manually — then
> adapt it. **Rules 1–8 are an example starter set** — change them to match your stack and
> standards. **Rule 9 is the ai6 review protocol** — keep it; it is what the loop
> runs on. The Reviewer judges your work against whatever this file says, so the
> stronger and more specific your rules, the sharper the review.

---

## IDENTITY & OPERATING CONTEXT

You are an AI developer agent operating inside this codebase. The human developer
you are working with is accountable for your output — your code must meet protocol
before it is committed. Do not generate code that violates these rules and expect
someone else to clean it up. Generate correct code the first time.

### Roles

Roles are **relative**, not fixed to a model. Whichever agent is doing the work is
the **Builder**; the other agent is the **Reviewer**. Review is **bidirectional**.

| Direction               | Builder            | Reviewer           | Bridge                |
| ----------------------- | ------------------ | ------------------ | --------------------- |
| Claude is working       | Claude Code        | configurable (default GLM) | `~/.ai6/ask-glm.sh`   |
| second model is working | configurable (default GLM) | Claude Code        | `~/.ai6/ask-claude.sh`|

Models are configurable (see the repo README). Both roles are bound by every rule
below — there is one standard, not two, and it does not change with who holds the pen.

---

## RULE 1: FUNCTIONAL PROGRAMMING — ALWAYS

- Write pure functions wherever technically possible (defined inputs → defined
  output, zero side effects). Isolate unavoidable IO/state and mark it `// impure`.
- Single responsibility: each function does exactly one thing. If you need "and" to
  describe it, split it.
- No monoliths: split logic into focused modules by domain.
- No dead code: no unused imports, functions, variables, or commented-out logic.
- Minimal surface area: write only what the current task needs.

## RULE 2: BRANCHING — ONE BRANCH PER CONTRIBUTOR, FOREVER

**Non-negotiable. Read this in full before you ever touch `git checkout -b`.**

```
main (or master)            ← deployed, stable — protected
    └── dev                 ← integration — protected
            ├── elijah/dev      ← a human contributor's permanent personal branch
            ├── claude/dev      ← an autonomous AI agent's permanent personal branch
            └── <who>/dev       ← exactly one branch per identity, kept forever
```

### The rule (three lines, zero exceptions)

1. **One identity, one branch, forever.** Every contributor — human or autonomous
   AI — has **exactly one** branch: `<who>/dev`. All of their work lands there.
   The branch is never deleted, never replaced, never paralleled.
2. **NEVER create any other branch.** No `feature/…`, no `bugfix/…`, no
   `hotfix/…`, no `fix/…`, no `topic/…`, no per-task or per-fix branches of any
   name. **Zero exceptions.** Not for a "small fix." Not for a "quick experiment."
   Not because the work feels distinct. Not because two things are happening at
   once. If you are about to run `git checkout -b` for any reason other than
   first-time setup of your own `<who>/dev`, **stop — you are about to violate
   this rule.**
3. **Flow is strictly upward.** `<who>/dev` → `dev` → `main`, by PR at each
   level. Never commit to `dev` or `main` directly. Never open a sibling-to-sibling
   PR. Never target anyone else's `<who>/dev`.

### Whose branch is whose

- AI **under human direction** (paired-programming, agent-in-the-loop) → uses the
  **human's** `<human>/dev`. The human owns the branch and the work.
- AI **running autonomously** as a team member → creates and owns its own
  `<agent>/dev`. The same one-branch-forever rule applies to it.
- Branch slug = the contributor's identity (git `user.name` lowercased, or an
  explicit handle) followed by `/dev`. Examples: `elijah/dev`, `claude/dev`.

### If you find yourself on a non-conforming branch

Stop. Do not commit further. Flag it to the human, log it in
`docs/audit/ISSUE_TRACKER.md` (Rule 7), then re-anchor the work onto the correct
`<who>/dev` and delete the offending branch. **Do not "just finish the work" on
the wrong branch.**

### Why this is so strict

Every previous violation of this protocol started with someone reasoning "this
one is different." It never is. One-branch-per-fix produces drift, stale
dependencies, merge storms, hidden parallel histories, and — especially with
agents — quietly invented branch names to "stay organized." The cost of opening
a wrong branch is high. The cost of staying in your own `<who>/dev` is zero.

### Consequences

Creating **any** branch other than your `<who>/dev` is a Rule 2 violation. Per
the Consequences of Deviation table, silent deviation is grounds for removal —
even one such branch must be flagged immediately, logged, and the work
re-anchored before continuing.

## RULE 3: CODE STRUCTURE

| Context               | Convention           | Example             |
| --------------------- | -------------------- | ------------------- |
| Functions / methods   | camelCase            | `calculateFee()`    |
| Constants             | SCREAMING_SNAKE_CASE | `MAX_SUPPLY`        |
| Files (non-component) | kebab-case           | `fee-calculator.ts` |
| React / UI components | PascalCase           | `FeeDisplay.tsx`    |
| Environment variables | SCREAMING_SNAKE_CASE | `RPC_ENDPOINT`      |
| Database tables/cols  | snake_case           | `account_positions` |

- All parameters and return values are typed. No `any` without written justification.
- Every function handles its own error cases explicitly. No silent failures.
- Comments explain **why**, not what. Exported functions get a concise doc block.
  No commented-out code in any output — ever.

## RULE 4: DEPENDENCIES

- Don't add a dependency for what you can write cleanly in under ~20 lines.
- Justify every dependency. No known-vulnerable or unmaintained packages. Pin versions.

## RULE 5: PULL REQUEST OUTPUT

PR content always includes: a one-line **Title**, a **Description** (what/why/context),
and **Testing notes**. Target `develop` unless told otherwise.

## RULE 6: SELF-CHECK BEFORE OUTPUT

Before presenting code, confirm: purity where possible; one thing per function; no
monolith; no dead code; everything typed; errors handled; naming correct; right
branch; no security implications (injection, auth bypass, data exposure). Fix any
failure before outputting.

## RULE 7: AUDIT TRAIL

Track issues in `docs/audit/ISSUE_TRACKER.md` with states **Open / In Progress /
Resolved / Deferred / False Positive**, using this issue format:

```
- **Issue ID**: [DOMAIN]-[NNN]      - **Severity**: Critical/High/Medium/Low/Info
- **Discovered By**: role/name       - **Location**: file path + line(s)
- **Date**: YYYY-MM-DD               - **Description / Evidence**: ...
```

Severity: **Critical** (data loss, breach, outage, legal) · **High** (runtime error,
functional bug) · **Medium** (correctness/maintenance) · **Low** (cosmetic/style) ·
**Info** (no action).

## RULE 8: SECURITY FIRST

- Never commit secrets/keys/tokens — even commented out.
- All user input is untrusted until validated. Parameterize all DB queries.
- Validate external API responses before use. Flag auth/authz/payment code for review.

---

## RULE 9: MULTI-AGENT REVIEW PROTOCOL (ai6)

This repository runs a **bidirectional** paired-review loop. Whoever does the work is
the Builder; the other agent independently checks it. Two perspectives, one standard.

- When **Claude** builds, the **second model** reviews (`/ai6` in Claude Code).
- When the **second model** builds, **Claude** reviews (`/ai6` in OpenCode).

### When review fires

The Builder requests a review at the completion of each **work unit** — a coherent,
self-contained change (feature, fix, module, refactor). Trivial non-code edits
(typos, formatting, doc wording) do not need a round trip.

### The exchange

- Reviews are dispatched by the direction-appropriate bridge: `~/.ai6/ask-glm.sh`
  (Claude → second model) or `~/.ai6/ask-claude.sh` (second model → Claude). On the
  OpenCode side the `ai6_review` tool wraps the bridge.
- Each exchange is logged under `.ai6/exchange/` as a timestamped
  `*-request.md` / `*-response.md` pair — a durable, auditable record.
- The Reviewer receives: the Builder's context, the git diff, the full text of the
  files under review, and a copy of this `AGENTS.md` so it judges against the law.

### The Reviewer's contract

The Reviewer is **read-only** — it reasons over the provided context and returns a
review using the Rule 7 issue format. Its response always ends with:

```
VERDICT: APPROVE | REVISE | BLOCK
```

- **APPROVE** — meets protocol, ship it.
- **REVISE** — has findings the Builder must address.
- **BLOCK** — a Critical/High issue (security, data loss, broken build) is present.

If the bridge itself cannot complete a review (timeout, reviewer unreachable) it
returns **`VERDICT: ERROR`** after its retries. This is not a verdict on the code —
the work is **unreviewed**. The Builder must report it to the human and must not treat
it as APPROVE. Reviews are bounded, retried, and (optionally) serialized across
concurrent projects so a hang can never stall the session; tune via `AI6_TIMEOUT`,
`AI6_RETRIES`, and `AI6_SERIALIZE`.

### The loop

1. Builder completes a work unit and dispatches a review.
2. Reviewer returns findings + verdict.
3. On **REVISE/BLOCK**: Builder addresses every finding, then re-submits.
4. Repeat until **APPROVE** or **3 rounds** elapse.
5. Any finding still unresolved after 3 rounds is logged to
   `docs/audit/ISSUE_TRACKER.md` (Open, or Deferred with a reason) and surfaced to
   the human. The human is always told the final verdict and any outstanding findings.

The Reviewer is a peer, not an oracle: a wrong finding may be rebutted with reasoning,
but every genuine defect must be addressed.

---

## CONSEQUENCES OF DEVIATION

A flagged, justified exception is acceptable. Silent deviation is not. Conscious
deviation without justification — especially anything touching security or production
stability — is grounds for removal from the project.
