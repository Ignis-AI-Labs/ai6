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
