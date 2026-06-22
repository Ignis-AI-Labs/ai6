# Architecture

ai6 is small on purpose. It is two ideas:

1. **One shared law.** Both agents read the same `AGENTS.md`. There is one standard,
   not two — so the review can't devolve into stylistic bickering between models.
2. **A bidirectional handoff.** Whoever builds, the other reviews, against that law,
   read-only, returning a machine-parsable verdict.

## Two layers

| Layer | What it is | Where it lives |
| --- | --- | --- |
| **Brains** (the "skill") | The *workflow*: when to review, the loop, how to read the verdict. Pure instructions. | `/ai6` command — Claude Code (`~/.claude/commands/ai6.md`) and OpenCode (`~/.config/opencode/command/ai6.md`). |
| **Hands** (the bridge) | The *execution*: actually invoking the other model, building the request, logging the exchange. | `~/.ai6/ask-glm.sh`, `~/.ai6/ask-claude.sh`, `~/.ai6/ask-openai.sh` (generic OpenAI-compatible). On OpenCode, the `ai6_review` tool (plugin) wraps the bridge. |

The command is the reliable core (zero dependencies). The OpenCode plugin is an
optional upgrade that turns the bridge into a first-class `ai6_review` tool so the
Builder can't forget to call it.

## The two directions

```
Claude builds ─▶ ai6-review.sh ─┬─▶ ask-glm.sh    ─▶ opencode run         ─▶ second model reviews
 (dispatcher selects a bridge)  ├─▶ ask-claude.sh ─▶ claude -p (read-only) ─▶ Claude reviews
                                │   (when opencode is absent, or forced via AI6_FORWARD_BRIDGE)
                                └─▶ ask-openai.sh ─▶ curl /v1/chat/completions ─▶ any model reviews
                                    (local Ollama/llama.cpp or cloud; via AI6_FORWARD_BRIDGE)
 ◀──────────────────────────── the chosen Reviewer's verdict ────────────────────────────────

GLM builds ─▶ ai6_review tool ─▶ ask-claude.sh ─▶ claude -p (read-only) ─▶ Claude reviews
 ◀──────────────────────────── Reviewer's verdict ──────────────────────────────────────────
```

When Claude is the Builder, the `/ai6` command calls `ai6-review.sh`, a dispatcher
that selects the bridge: the second model via OpenCode (`ask-glm.sh`) by default;
Claude reviewing Claude (`ask-claude.sh`) when OpenCode isn't installed; or a generic
OpenAI-compatible bridge (`ask-openai.sh` → curl to any `/v1/chat/completions`: local
Ollama/llama.cpp or a cloud API) when selected via `AI6_FORWARD_BRIDGE`. See
[`CONFIGURATION.md`](./CONFIGURATION.md#forward-review-routing-who-reviews-claude).

## The request

Each bridge builds one request containing:

- the Builder's context note (what changed and why),
- the `git diff` vs `HEAD` (when the project is a git repo),
- the full contents of the files under review,
- a copy of the project's `AGENTS.md` (the law to judge against).

It is sent to the read-only Reviewer, whose reply ends with
`VERDICT: APPROVE | REVISE | BLOCK`. Both the request and response are written to
`.ai6/exchange/` as a timestamped pair — a durable, auditable record of the
conversation between the two models.

## Why read-only reviewers

The Reviewer is given everything inline and has no write/edit/exec tools (OpenCode
agent: all tools disabled; Claude: `--disallowedTools Write Edit NotebookEdit Bash`).
It can only reason and report. That keeps reviews deterministic, free of permission
prompts, and incapable of altering the work they're judging.
