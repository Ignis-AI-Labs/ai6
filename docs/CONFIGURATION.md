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

## Notes

- The shipped OpenCode reviewer agent (`ai6-reviewer`) declares a default `model:`,
  but the bridge always overrides it via `--model`, so **`AI6_REVIEWER_MODEL` is the
  knob that matters** — you do not need to edit the agent file.
- ai6 does not manage provider credentials. Authenticate your providers the normal
  way (`opencode auth login`, Claude Code sign-in); ai6 uses whatever is configured.
- The two directions are independent. You can run Claude-builds-only or
  OpenCode-builds-only; install whichever CLIs you use.
