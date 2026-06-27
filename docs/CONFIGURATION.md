# Configuration

ai6 is **model-agnostic**. It never hardwires you to a specific model or provider —
on every review it passes the model explicitly, so it works with **whatever you
already have set up and paid for** in OpenCode and Claude Code. Pick any model your
plans can reach.

## Where settings live

Settings are read from environment variables, with an optional config file at
`~/.config/ai6/config` (created by the installer from `config.example`). The file is
sourced by the bridges. Inline env vars override the file, which overrides the
built-in defaults.

| Variable             | Used by         | Default                  | Meaning                                            |
| -------------------- | --------------- | ------------------------ | -------------------------------------------------- |
| `AI6_REVIEWER_MODEL` | `ask-glm.sh`    | `zai-coding-plan/glm-5.2`| The reviewer model when **Claude builds** (OpenCode `provider/model`). |
| `AI6_REVIEWER_AGENT` | `ask-glm.sh`    | `ai6-reviewer`           | The OpenCode review agent (read-only persona).      |
| `AI6_CLAUDE_MODEL`   | `ask-claude.sh` | `opus`                   | The reviewer model when the **other model builds** (a `claude --model` value). |
| `AI6_BRIDGE`         | OpenCode plugin | `~/.ai6/ask-claude.sh`   | Path to the reverse bridge the `ai6_review` tool calls. |
| `AI6_TIMEOUT`        | both bridges    | `300`                    | Seconds per review attempt before it's killed.     |
| `AI6_RETRIES`        | both bridges    | `1`                      | Extra attempts after the first on timeout/failure. |
| `AI6_RETRY_DELAY`    | both bridges    | `3`                      | Seconds between attempts.                           |
| `AI6_SERIALIZE`      | both bridges    | `1`                      | `1` = only one review runs at a time across all projects. |
| `AI6_LOCK_TIMEOUT`   | both bridges    | `900`                    | Max seconds to wait for the serialization lock.    |
| `AI6_PLUGIN_TIMEOUT_MS` | OpenCode plugin | derived               | Override the plugin's backstop (ms). Must be set in OpenCode's environment (the plugin reads `process.env`, not the config file). |
| `AI6_MAX_CHARS`      | both bridges    | `200000`                 | Approx max request size per pass; larger reviews auto-split so files are never truncated. |
| `AI6_SECURITY_MODEL` | `/ai6-security` | `${AI6_REVIEWER_MODEL}`  | Reviewer model for the security audit. Defaults to your normal reviewer model; override only if you want the audit to use a different/stronger model. |
| `AI6_SECURITY_AGENT` | `/ai6-security` | `ai6-security-reviewer`  | OpenCode agent persona for the audit. The default carries the section-aware audit rubric and the DATA-not-instructions hardening — change at your own risk. |
| `AI6_SECURITY_CHECKLIST` | `/ai6-security` | _(see precedence below)_ | Path (absolute recommended) to a checklist file. Overrides both the project checklist and the installed default — when set and the file exists. **Note:** if the path is set but does not exist, the resolver silently falls through to the next precedence level rather than erroring; check your env var if you expect an override to take effect. |

## Pick your models

**See what you actually have available:**

```bash
opencode models      # every provider/model your OpenCode plan can reach
claude --help        # the --model values Claude Code accepts (aliases like opus/sonnet, or full ids)
```

**Then set them** — edit `~/.config/ai6/config`:

```bash
# Reviewer when Claude builds — ANY model OpenCode lists. Examples:
: "${AI6_REVIEWER_MODEL:=zai-coding-plan/glm-5.2}"   # Z.AI
# : "${AI6_REVIEWER_MODEL:=anthropic/claude-sonnet-4-6}"
# : "${AI6_REVIEWER_MODEL:=openai/gpt-5}"
# : "${AI6_REVIEWER_MODEL:=openrouter/deepseek/deepseek-chat}"

# Reviewer when the other model builds — a claude --model value:
: "${AI6_CLAUDE_MODEL:=opus}"
```

Or override for a single run without touching the file:

```bash
AI6_REVIEWER_MODEL=openai/gpt-5 bash ~/.ai6/ask-glm.sh "context" file.ts
```

## Reliability under concurrency

Running reviews across several projects at once can stall the underlying CLIs (shared
daemon, API rate limits, CPU/memory). ai6 is built so a stall can never become a
permanent hang:

- **Timeout** — every attempt is wrapped in `timeout AI6_TIMEOUT`. A wedged review is
  killed, not waited on forever. Requires GNU `timeout` (Linux coreutils; on macOS
  `brew install coreutils` provides `gtimeout`, which ai6 detects). If neither exists,
  ai6 warns once and runs unbounded rather than failing.
- **Retry** — on timeout/transient failure it retries `AI6_RETRIES` times (with
  `AI6_RETRY_DELAY` between) before giving up.
- **Serialize** — with `AI6_SERIALIZE=1` (default) a global `flock` lets only one
  review run at a time across all projects, so they queue instead of contending. Set
  `AI6_SERIALIZE=0` to allow full parallelism if your setup can handle it. Requires
  `flock` (preinstalled on Linux via util-linux; on macOS `brew install flock`). If
  it's missing, ai6 warns once and falls back to parallel — the timeout still applies.
- **Isolation** — each `opencode run` uses `--port 0` (its own random server port),
  and temp/exchange files are per-run, so concurrent reviews don't collide.
- **Graceful give-up** — if a review still can't complete, the bridge returns
  `VERDICT: ERROR` (never a hang). The work is reported as **unreviewed**, not
  approved. The OpenCode `ai6_review` tool also honors cancellation and has its own
  backstop so it can't freeze a session.

Tuning tips: bump `AI6_TIMEOUT` for large diffs/slow models; raise `AI6_RETRIES` on
flaky networks; keep `AI6_SERIALIZE=1` if you routinely run many projects at once.

## Full-file visibility on large reviews

A reviewer can only judge what it actually sees. If a work unit's payload (all files +
diff + `AGENTS.md`) is bigger than the model's context window, the tail would be
silently dropped — and a verdict on a half-seen file is worthless. ai6 prevents that:

- The request size is estimated against `AI6_MAX_CHARS` (default 200 000 bytes).
- If it fits, it's one pass — unchanged behavior.
- If not, the files are **split into multiple passes** that each stay under budget.
  Every pass carries full file contents, `AGENTS.md`, and the diff scoped to just
  that pass's files, so the reviewer sees each file **in full**.
- Each pass is reviewed independently and the verdicts are **aggregated** — the
  strictest wins (`ERROR` > `BLOCK` > `REVISE` > `APPROVE`) — with every part's
  findings included in the response.
- A single file larger than the budget is reviewed alone with a warning (raise
  `AI6_MAX_CHARS` if your model's window is large enough to take it in one piece).

Set `AI6_MAX_CHARS` to match your reviewer model: lower it for smaller-context models,
raise it for large-context ones to avoid unnecessary splitting.

## Security audit mode (`/ai6-security`)

ai6 ships an exhaustive **security audit** scan that's distinct from the regular
review loop. Run it with the **`/ai6-security`** slash command in either Claude
Code or OpenCode.

### What it does

It runs your project against the entire Comprehensive Security Audit Protocol
(`security/SECURITY_CHECKLIST.md`), section by section — one reviewer pass per
top-level section. For each section it evaluates every checklist item and marks
it `PASS` / `FAIL` / `N/A` / `NEEDS-INFO` with evidence citations, then returns a
per-section verdict. All section verdicts are aggregated into a single overall
verdict under strictest-wins precedence:

| Overall verdict | Meaning |
|---|---|
| **`PASS`** | Every applicable item is PASS or N/A with justification. |
| **`NEEDS-WORK`** | At least one HIGH/MEDIUM/LOW item is FAIL, or any item is NEEDS-INFO. |
| **`BLOCK`** | At least one CRITICAL item failed, or a `[DEPLOYMENT BLOCKER]` item failed. |
| **`ERROR`** | One or more sections could not be reviewed (timeout, reviewer failure). The audit is **incomplete** — re-run or raise `AI6_TIMEOUT`. |

A malformed verdict line from the reviewer collapses to `ERROR` rather than
silently being treated as a clean verdict — a false-clean is the worst failure
mode of a security gate.

### When to run it

**Mandatory for production.** This is the gate against shipping a CRITICAL gap.
Run it before any non-trivial production push, after any architecture change, and
on the self-run scanning cadence per `§10.4` of the checklist.

### Cost up front

This is **exhaustive and token-heavy by design** — and the script will say so before
it starts. Expect roughly:
- **1–3 million reviewer-model tokens** for a typical project (~10 sections × full
  context per pass).
- **10–30+ minutes** of wall-clock runtime.
- Real cost on your reviewer-model plan — check it.

The orchestrator prints all of this and prompts for explicit confirmation before
the first reviewer call fires. The slash command requests confirmation in-agent
first, then passes `--yes` to skip the script's interactive prompt — never invoke
`bash ~/.ai6/ai6-security-scan.sh --yes` from an autonomous loop without a
human-in-the-loop check.

### Where the output goes

- Final aggregated report: `.ai6/audits/<timestamp>-security-audit.md`
- Per-section request and response: `.ai6/audits/<timestamp>-sectionNN-*.md`
- `.ai6/audits/` is gitignored by ai6's `.gitignore`.

The aggregated report leads with the overall verdict and a per-section breakdown,
then includes the full per-section detail with every item's status and evidence.

### Choosing the checklist

The checklist used for the scan is resolved in this precedence order:

1. **`$AI6_SECURITY_CHECKLIST`** — absolute path you've set explicitly (highest).
2. **`<project>/docs/SECURITY_CHECKLIST.md`** — per-project override checked into
   your repo. Adapt the shipped checklist for your stack, add domain-specific
   sections, or trim sections that don't apply.
3. **`~/.ai6/security/SECURITY_CHECKLIST.md`** — the multi-section Comprehensive
   Security Audit Protocol shipped with ai6 (the default).

The orchestrator parses sections by the `## N. NAME` header pattern, so any
override must follow that structure. An empty or structurally-invalid checklist
fails fast with a clear error rather than silently scanning nothing.

### Scoping a partial scan

The orchestrator always runs every top-level section in the chosen checklist. To
scope a partial scan (run only one or two sections — useful for tightening a
specific area without re-paying the full token cost), point
`AI6_SECURITY_CHECKLIST` at a smaller checklist file that contains only the
sections you want. The file just needs the same `## N. NAME` structure the
orchestrator's own parser uses. Example, **section-aware** so it's immune to
line-number drift when the shipped checklist is edited:

```bash
# Scan only §5 (AI/LLM Security). Change c==5 to pick a different section;
# the awk matches the same `## N. ` header pattern the orchestrator parses,
# so this works for any section including the last (no "next section" needed).
TMP_CL="$(mktemp -d)/cl.md"
awk '/^## [0-9]+\. /{c++} c==5' ~/.ai6/security/SECURITY_CHECKLIST.md > "$TMP_CL"
AI6_SECURITY_CHECKLIST="$TMP_CL" bash ~/.ai6/ai6-security-scan.sh
```

To scan a contiguous range (e.g. §3–§5), use `c>=3 && c<=5`. **Do not** use
line-number-based extraction (`sed -n '438,514p'`) — checklist edits will silently
shift the lines, and the orchestrator would still label the section by its
position in your custom file, producing a misleadingly authoritative audit.

### Models, agent, and overrides

- Defaults to the same reviewer model your regular `/ai6` reviews use
  (`AI6_REVIEWER_MODEL`). Override per-scan with `AI6_SECURITY_MODEL` if you want
  the audit to use a different / stronger model.
- The `ai6-security-reviewer` OpenCode agent carries a strict per-item rubric
  (`PASS|FAIL|N/A|NEEDS-INFO`), a strict per-section verdict format, and explicit
  DATA-not-instructions hardening so a hostile file can't talk the reviewer into a
  fake `SECTION VERDICT: PASS`. Don't change the agent unless you have a replacement
  with the same rubric.

### Reading a failed audit honestly

- **Address every `FAIL` finding** before re-running — the audit gives you exact
  evidence citations.
- **A `NEEDS-INFO`** means the reviewer couldn't tell from the project context
  whether the control is in place. Either provide evidence (point the next scan at
  the relevant docs) or treat it as a real gap.
- **Do not auto-close `BLOCK` items** without addressing them. If you genuinely
  need to defer one, log it in `docs/audit/ISSUE_TRACKER.md` per Rule 7 with the
  reasoning (deferred + justification + planned remediation).
- A `BLOCK` is the point of running this scan. Treat it as one.

## Notes

- The shipped OpenCode reviewer agent (`ai6-reviewer`) declares a default `model:`,
  but the bridge always overrides it via `--model`, so **`AI6_REVIEWER_MODEL` is the
  knob that matters** — you do not need to edit the agent file.
- ai6 does not manage provider credentials. Authenticate your providers the normal
  way (`opencode auth login`, Claude Code sign-in); ai6 uses whatever is configured.
- The two directions are independent. You can run Claude-builds-only or
  OpenCode-builds-only; install whichever CLIs you use.
- The git diff in a review is scoped to the files you submit; add related files to the
  review list when their diff context matters.
