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

## Notes

- The shipped OpenCode reviewer agent (`ai6-reviewer`) declares a default `model:`,
  but the bridge always overrides it via `--model`, so **`AI6_REVIEWER_MODEL` is the
  knob that matters** — you do not need to edit the agent file.
- ai6 does not manage provider credentials. Authenticate your providers the normal
  way (`opencode auth login`, Claude Code sign-in); ai6 uses whatever is configured.
- The two directions are independent. You can run Claude-builds-only or
  OpenCode-builds-only; install whichever CLIs you use.
