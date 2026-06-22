#!/usr/bin/env bash
#
# ai6 uninstaller — removes installed bridges, commands, agent, and plugin.
# Your config (~/.config/ai6/config) is kept unless you pass --purge.
#
# Usage: uninstall.sh [--purge]

set -euo pipefail

readonly CONFIG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly AI6_HOME="${HOME}/.ai6"
readonly CFG_DIR="${CONFIG_BASE}/ai6"
readonly CLAUDE_CMD_DIR="${HOME}/.claude/commands"
readonly OC_BASE="${CONFIG_BASE}/opencode"

PURGE="false"
[ "${1:-}" = "--purge" ] && PURGE="true"

say() { printf 'ai6: %s\n' "$*"; }

rm -f "${AI6_HOME}/ask-glm.sh" "${AI6_HOME}/ask-claude.sh" \
      "${AI6_HOME}/ai6-review.sh" "${AI6_HOME}/ai6-init.sh" \
      "${AI6_HOME}/lib/build-request.sh" "${AI6_HOME}/lib/run-review.sh" \
      "${AI6_HOME}/lib/chunk-review.sh" \
      "${AI6_HOME}/templates/AGENTS.md" "${AI6_HOME}/templates/CLAUDE.md"
rmdir "${AI6_HOME}/lib" "${AI6_HOME}/templates" 2>/dev/null || true
rmdir "${AI6_HOME}" 2>/dev/null || true
rm -f "${CLAUDE_CMD_DIR}/ai6.md"
rm -f "${OC_BASE}/agent/ai6-reviewer.md" "${OC_BASE}/command/ai6.md" "${OC_BASE}/plugin/ai6.js"
say "removed bridges, commands, agent, and plugin."

if [ "${PURGE}" = "true" ]; then
  rm -f "${CFG_DIR}/config"
  rmdir "${CFG_DIR}" 2>/dev/null || true
  say "purged config."
else
  say "kept config at ${CFG_DIR}/config (use --purge to remove)."
fi
