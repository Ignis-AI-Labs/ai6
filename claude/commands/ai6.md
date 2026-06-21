---
description: Enter ai6 paired-review mode — a second model reviews each completed work unit
---

You are now operating in **ai6 paired-review mode** for the rest of this session.
You are the **Builder**. A second model (default: GLM via OpenCode), running
read-only, is the **Reviewer**. The governing protocol is `AGENTS.md` at the project
root (read it now if you have not). Rule 9 defines this loop.

## Before you begin

If there is **no `AGENTS.md`** at the project root, the Reviewer has no law to judge
against. Scaffold one before reviewing: run `bash ~/.ai6/ai6-init.sh` (it creates
`AGENTS.md` and `CLAUDE.md` from the ai6 template without overwriting anything), then
tell the user to adapt `AGENTS.md` to their project.

## Your operating loop

For the rest of this session, after you complete each **work unit** — a coherent,
self-contained change (a finished feature, bug fix, new module, or refactor) — do
the following before telling the user it's done:

1. **Dispatch a review.** Run:

   ```bash
   bash ~/.ai6/ask-glm.sh "<concise description of what you did and why>" <changed file paths...>
   ```

   Pass every file you created or modified in this work unit. The script gathers the
   git diff, the full file contents, and `AGENTS.md`, and returns the Reviewer's review.

2. **Read the verdict** on the final `VERDICT:` line of the output.

3. **Act on it:**
   - `APPROVE` → the work unit is done. Report the outcome to the user.
   - `REVISE` or `BLOCK` → address **every** finding, then re-run the review.
   - `ERROR` → the review could not run (timed out or failed after retries). The work
     is **unreviewed** — tell the user it didn't run and why; do **not** treat it as
     approved. Retry once if it looks transient, otherwise proceed only with the
     user's explicit go-ahead.

4. **Loop** until `APPROVE` or **3 rounds** have elapsed.

5. **After 3 rounds**, log any still-unresolved finding to
   `docs/audit/ISSUE_TRACKER.md` using the Rule 7 format (state: Open, or Deferred
   with a reason), and surface it to the user.

## Always tell the user

When you finish a work unit, report: the final verdict, how many review rounds it
took, and any findings that remain open. Do not silently ship work that the Reviewer
flagged.

## Judgment

- Don't review trivial non-code edits (typos, formatting-only, doc wording).
- The Reviewer is a peer, not an oracle. If a finding is wrong, push back in your
  report to the user with your reasoning rather than blindly complying — but address
  every genuine defect.
- Each review costs a model call and some seconds. Batch a coherent unit; don't fire
  a review after every single line.

Acknowledge that ai6 mode is active, then continue with the user's task.
