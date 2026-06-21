#!/usr/bin/env bash
#
# ai6 installer — sets up the bidirectional paired-review loop for Claude Code
# and/or OpenCode. Idempotent: safe to re-run after pulling updates.
#
# What it installs:
#   ~/.ai6/ask-glm.sh, ~/.ai6/ask-claude.sh        the review bridges (shared)
#   ~/.config/ai6/config                            your config (created once)
#   ~/.claude/commands/ai6.md                       the /ai6 command (Claude Code)
#   ~/.config/opencode/{agent,command,plugin}/...   the OpenCode side
#
# Each side is installed only if its CLI is present. The OpenCode plugin is
# best-effort (needs @opencode-ai/plugin); the /ai6 command works without it.

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AI6_HOME="${HOME}/.ai6"
readonly CONFIG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly CFG_DIR="${CONFIG_BASE}/ai6"
readonly CLAUDE_CMD_DIR="${HOME}/.claude/commands"
readonly OC_BASE="${CONFIG_BASE}/opencode"

say()  { printf 'ai6: %s\n' "$*"; }
warn() { printf 'ai6: \033[33mWARN\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- shared bridges --------------------------------------------------------
mkdir -p "${AI6_HOME}/lib" "${AI6_HOME}/templates"
install -m 0755 "${REPO}/bin/ask-glm.sh"           "${AI6_HOME}/ask-glm.sh"
install -m 0755 "${REPO}/bin/ask-claude.sh"        "${AI6_HOME}/ask-claude.sh"
install -m 0755 "${REPO}/bin/ai6-init.sh"          "${AI6_HOME}/ai6-init.sh"
install -m 0644 "${REPO}/bin/lib/build-request.sh" "${AI6_HOME}/lib/build-request.sh"
install -m 0644 "${REPO}/bin/lib/run-review.sh"     "${AI6_HOME}/lib/run-review.sh"
# Templates used by ai6-init.sh to scaffold a project's law + pointer.
install -m 0644 "${REPO}/AGENTS.md" "${AI6_HOME}/templates/AGENTS.md"
install -m 0644 "${REPO}/CLAUDE.md" "${AI6_HOME}/templates/CLAUDE.md"
say "installed bridges + init -> ${AI6_HOME}/"

# --- config (never overwrite an existing one) ------------------------------
mkdir -p "${CFG_DIR}"
if [ -f "${CFG_DIR}/config" ]; then
  say "config exists, left untouched -> ${CFG_DIR}/config"
else
  install -m 0644 "${REPO}/config.example" "${CFG_DIR}/config"
  say "created config -> ${CFG_DIR}/config"
fi

# --- Claude Code side ------------------------------------------------------
if have claude; then
  mkdir -p "${CLAUDE_CMD_DIR}"
  install -m 0644 "${REPO}/claude/commands/ai6.md" "${CLAUDE_CMD_DIR}/ai6.md"
  say "installed Claude command -> ${CLAUDE_CMD_DIR}/ai6.md  (run /ai6 in Claude Code)"
else
  warn "'claude' not found on PATH — skipped the Claude Code side."
fi

# --- OpenCode side ---------------------------------------------------------
if have opencode; then
  mkdir -p "${OC_BASE}/agent" "${OC_BASE}/command" "${OC_BASE}/plugin"
  install -m 0644 "${REPO}/opencode/agent/ai6-reviewer.md" "${OC_BASE}/agent/ai6-reviewer.md"
  install -m 0644 "${REPO}/opencode/command/ai6.md"        "${OC_BASE}/command/ai6.md"
  install -m 0644 "${REPO}/opencode/plugin/ai6.js"         "${OC_BASE}/plugin/ai6.js"
  say "installed OpenCode agent/command -> ${OC_BASE}/  (run /ai6 in OpenCode)"

  # The plugin imports @opencode-ai/plugin; it must resolve from the config dir.
  # @opencode-ai/plugin is intentionally unpinned (Rule 4 flagged exception): it
  # must track the installed opencode host version, not a fixed release.
  if [ ! -d "${OC_BASE}/node_modules/@opencode-ai/plugin" ]; then
    if have bun; then
      ( cd "${OC_BASE}" && bun add @opencode-ai/plugin >/dev/null 2>&1 ) \
        && say "installed @opencode-ai/plugin dependency" \
        || warn "bun add @opencode-ai/plugin failed — the ai6_review tool will be skipped; the /ai6 command still works via its bash fallback."
    elif have npm; then
      ( cd "${OC_BASE}" && npm install @opencode-ai/plugin >/dev/null 2>&1 ) \
        && say "installed @opencode-ai/plugin dependency" \
        || warn "npm install @opencode-ai/plugin failed — the ai6_review tool will be skipped; the /ai6 command still works via its bash fallback."
    else
      warn "bun/npm not found — the ai6_review tool will be skipped. The /ai6 command still works via its bash fallback."
    fi
  fi
else
  warn "'opencode' not found on PATH — skipped the OpenCode side."
fi

say "done."
say "Next: in your project root run 'bash ${AI6_HOME}/ai6-init.sh' to scaffold AGENTS.md + CLAUDE.md, then run /ai6."
