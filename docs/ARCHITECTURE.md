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
| **Hands** (the bridge) | The *execution*: actually invoking the other model, building the request, logging the exchange. | `~/.ai6/ask-glm.sh`, `~/.ai6/ask-claude.sh`. On OpenCode, the `ai6_review` tool (plugin) wraps the bridge. |

The command is the reliable core (zero dependencies). The OpenCode plugin is an
optional upgrade that turns the bridge into a first-class `ai6_review` tool so the
Builder can't forget to call it.

## The two directions

```
Claude builds ───▶  ~/.ai6/ask-glm.sh  ──▶  opencode run --agent ai6-reviewer  ──▶  GLM reviews
   (Reviewer's verdict ◀──────────────────────────────────────────────────────────────┘)

GLM builds ──▶  ai6_review tool ──▶  ~/.ai6/ask-claude.sh  ──▶  claude -p (read-only)  ──▶  Claude reviews
   (Reviewer's verdict ◀──────────────────────────────────────────────────────────────────┘)
```

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
