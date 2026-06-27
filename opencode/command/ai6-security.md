---
description: Run the full ai6 security audit — every section of the Comprehensive Security Audit Protocol
---

The user is invoking the **ai6 security audit**. This runs the project against the
*full* Comprehensive Security Audit Protocol (`security/SECURITY_CHECKLIST.md`),
section by section, and writes an aggregated audit report.

**Warn the user up front, in your own words, before invoking:** this is the
exhaustive mandatory-for-production scan; expect ~1-3M reviewer tokens, 10-30+
minutes of runtime, and real cost on their reviewer-model plan. Confirm they want
to proceed — they may want to specify the project root, override the checklist
path (`AI6_SECURITY_CHECKLIST=...`), or budget for it first.

When they confirm, run from the project root via your bash tool:

```bash
bash ~/.ai6/ai6-security-scan.sh --yes
```

(Use `--yes` only because YOU have already obtained explicit user confirmation.
The script will otherwise prompt interactively, which won't work in this agent
context.)

After it completes, read the final `## Overall verdict:` from the report and the
top of any BLOCK-tier sections, then summarize for the user:

- **Overall verdict** (PASS / NEEDS-WORK / BLOCK) — surface this first.
- **Deployment blockers** — every section that came back BLOCK, with the
  specific CRITICAL / `[DEPLOYMENT BLOCKER]` items that failed.
- **Where the full report lives** (`.ai6/audits/<timestamp>-security-audit.md`).

Do not pretend a NEEDS-INFO item is a PASS. Do not auto-close BLOCK items
without the user's explicit say-so. A failed audit is the *point* of running
this scan — present the result honestly so the user knows what to fix.
