# AI-6 has merged into Shadow Clone

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

**This repository is archived.** AI-6's paired-review bridge (the
`/ai6-*` slash commands, the `ask-glm.sh` / `ask-claude.sh` bridges, the
OpenCode reviewer persona) has been absorbed into
**[Shadow Clone](https://github.com/Ignis-AI-Labs/shadow-clone)** as
the `/sc-echo` paired-review subsystem.

Shadow Clone is the active project. All future development happens
there.

## Where things went

| AI-6 surface | Shadow Clone equivalent |
|---|---|
| `/ai6` (turn on paired review) | `/sc-echo` |
| `/ai6-security` (full security audit) | `/sc-audit` |
| `bin/ai6-init.sh` | `bridge/sc-init.sh` |
| `bin/ask-glm.sh` / `bin/ask-claude.sh` | `bridge/ask-glm.sh` / `bridge/ask-claude.sh` |
| `claude/commands/ai6*.md` | `commands/sc-echo.md`, `commands/sc-audit.md` |
| `opencode/agent/ai6-reviewer.md` | `bridge/agent/sc-echo-reviewer.md` |

The bridge architecture, the `<<<UNTRUSTED-*>>>` / `<<<TRUSTED-*>>>`
boundary contract, the verdict format (`APPROVE` / `REVISE` / `BLOCK`
/ `ERROR`), the 3-round cap, and the issue-tracker fallback are all
preserved. Most users won't notice anything except the `sc-` prefix.

## How to migrate

If you have AI-6 installed and want Shadow Clone instead:

```bash
# Optional but clean — remove the AI-6 install first
bash ~/.ai6/uninstall.sh   # if you still have the AI-6 clone around

# Then follow the Shadow Clone install
git clone --depth 1 --branch v0.2.8 https://github.com/Ignis-AI-Labs/shadow-clone.git
cd shadow-clone
bash bridge/install.sh
bash scripts/sc-doctor.sh
```

`/sc-echo` works the same way `/ai6` used to: turn it on, every
completed work unit gets reviewed before you tell the user it's done.

For users who never had AI-6 installed, just follow the
[Shadow Clone install guide](https://github.com/Ignis-AI-Labs/shadow-clone#install).

## History

The full pre-archive source tree (slash commands, bridges, reviewer
persona, install scripts, docs, security tests) is preserved at tag
**`archive/pre-shadow-clone-migration`**. To browse or check out:

```bash
git fetch --tags
git checkout archive/pre-shadow-clone-migration
```

## License

[MIT](./LICENSE). Unchanged.
