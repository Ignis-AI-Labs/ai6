# ai6

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-supported-d97757.svg)](https://claude.com/claude-code)
[![OpenCode](https://img.shields.io/badge/OpenCode-supported-000000.svg)](https://opencode.ai)
[![Model-agnostic](https://img.shields.io/badge/models-bring%20your%20own-success.svg)](./docs/CONFIGURATION.md)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

**Two AI coding agents, one shared law, reviewing each other's work.**

ai6 wires a second model into your coding agent as a read-only reviewer. You build
with one model; the other independently reviews every finished unit of work against a
shared standard and hands back a verdict — `APPROVE`, `REVISE`, or `BLOCK`. It runs
in **both directions** and works with **whatever models you already have**.

The idea is simple: a single model grades its own homework. Two strong models, each
catching what the other misses, judged against the *same* written law, get you much
closer to senior-engineer-level review — for free, in the loop, before anything ships.

```
You: build a feature in Claude Code
  └─ Claude finishes → hands the diff to GLM → GLM reviews against AGENTS.md
       → "BLOCK: SQL injection at auth.py:5" → Claude fixes it → re-review → APPROVE
```

---

## Why it works

- **One law, not two.** Both agents read the same `AGENTS.md`. The review is grounded
  in *your* rules, so it's substantive — not two models arguing about style.
- **A real second perspective.** The reviewer is a *different model* with no stake in
  the code it's judging. It's read-only: it reasons and reports, it can't edit.
- **Bidirectional.** Build in Claude Code and your configured reviewer (GLM by
  default) reviews; build in OpenCode and Claude reviews. Roles are relative to
  whoever holds the pen, and the reviewer model is yours to choose.
- **Auditable.** Every request/response is logged to `.ai6/exchange/`.

## See it in action

A reviewer catching a real bug — abridged from an actual ai6 run:

```
## Review Summary
A get_user(name) lookup that builds its SQL by concatenating untrusted input —
a textbook injection in auth code. Automatic BLOCK.

## Findings
- Severity: Critical
- Location: auth.py:5  —  q = "SELECT * FROM users WHERE name = '" + name + "'"
- Description: SQL injection. `' OR '1'='1` returns arbitrary rows; this is
  auth code, so it directly violates Rule 8 (parameterize all queries).
- Suggestion: conn.execute("SELECT * FROM users WHERE name = ?", (name,))

VERDICT: BLOCK
```

The Builder then fixes every finding and re-submits, looping until `APPROVE` — so
the bug never reaches your branch. ai6 even reviews itself: this repo was hardened
across four rounds of its own loop before release (it caught a secret-exfiltration
path, a silent installer failure, and a symlink bug along the way).

## Works with any model you have

ai6 is **model-agnostic**. It passes the model explicitly on every call, so use
whatever your OpenCode and Claude plans give you — GLM, Claude, GPT, DeepSeek,
anything OpenCode lists. See what you've got and point ai6 at it:

```bash
opencode models        # list every provider/model your plan can reach
# then set AI6_REVIEWER_MODEL / AI6_CLAUDE_MODEL — see docs/CONFIGURATION.md
```

## Requirements

- [Claude Code](https://claude.com/claude-code) and/or [OpenCode](https://opencode.ai)
  on your `PATH` (install whichever side(s) you want — ai6 sets up each one it finds).
- Providers authenticated the normal way for each tool. ai6 doesn't touch credentials.
- `bun` or `npm` (only for the optional OpenCode `ai6_review` tool).

## Install

```bash
git clone https://github.com/Ignis-AI-Labs/ai6.git
cd ai6
./install.sh
```

The installer is idempotent and only sets up the sides whose CLI it finds. It places:

- `~/.ai6/ask-glm.sh`, `~/.ai6/ask-claude.sh` — the review bridges
- `~/.config/ai6/config` — your settings (created once, never overwritten)
- `~/.claude/commands/ai6.md` — the `/ai6` command for Claude Code
- `~/.config/opencode/{agent,command,plugin}/…` — the OpenCode side

Then copy this repo's [`AGENTS.md`](./AGENTS.md) into your project root and adapt it.

## Usage

1. Put an `AGENTS.md` at your project root (start from this repo's — Rules 1–8 are an
   example; **Rule 9 is the ai6 protocol, keep it**).
2. In your session, run **`/ai6`** to enter paired-review mode.
3. Build normally. After each work unit, the Builder dispatches a review, addresses
   findings, loops up to 3 rounds, and reports you the final verdict.

That's it. The Reviewer judges against your `AGENTS.md`; you stay in control.

## How it works

Two layers — a "skill" (the `/ai6` command: the workflow) and "hands" (the bridges
that actually call the other model). Each review request bundles your context note,
the git diff, the files, and `AGENTS.md`, and comes back ending in a parsable
`VERDICT:` line. Full detail in [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).

Reviewers are strictly read-only, and the file list is confined to your project root
so a misbehaving agent can't ship secrets like `~/.ssh/id_rsa` to the reviewer. One
caveat: the `git diff` is sent as-is — keep secrets out of uncommitted changes when
you dispatch a review.

## Configuration

Set your models, agent, and bridge path via `~/.config/ai6/config` or env vars. Full
table and examples in [`docs/CONFIGURATION.md`](./docs/CONFIGURATION.md).

## Uninstall

```bash
./uninstall.sh          # remove ai6 (keeps your config)
./uninstall.sh --purge  # also remove ~/.config/ai6/config
```

## FAQ

**Does the reviewer ever change my code?** No. Reviewers are strictly read-only.

**Do I need both Claude Code and OpenCode?** Only for both directions. Either side
works on its own.

**Is this expensive?** Each review is one extra model call per work unit (not per
line). Batch coherent units; the `/ai6` command already nudges that.

**Can I use the same model on both sides?** Yes, but the value comes from two
*different* models — each catches the other's blind spots.

## Contributing

This repo dogfoods itself: it has an `AGENTS.md`, and contributions are expected to
pass an ai6 review. PRs welcome.

## License

MIT © Ignis AI Labs. See [LICENSE](./LICENSE).
