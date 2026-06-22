#!/usr/bin/env bash
#
# ai6 forward-review dispatcher — the single entrypoint the /ai6 command calls when
# CLAUDE is the Builder. It selects the right review bridge and hands off to it,
# unchanged. This keeps the command agnostic about WHICH model reviews: that choice
# lives here, in code, instead of being hardwired into the workflow instructions.
#
# Selection (first match wins):
#   1. AI6_FORWARD_BRIDGE set        -> use exactly that bridge (a name in this dir,
#                                       or an absolute path to a custom bridge).
#   2. `opencode` is on PATH         -> ask-glm.sh   (the second model reviews).
#   3. otherwise                     -> ask-claude.sh (Claude reviews Claude; no
#                                       extra dependency, so the loop still runs).
#
# impure: sources the config file and exec's a bridge that shells out to a model CLI.
#
# Usage: ai6-review.sh "<context: what was done and why>" [file ...]
#   (identical contract to the bridges it dispatches to.)

set -euo pipefail

# Repo layout: bin/ai6-review.sh with bridges beside it; installed layout:
# ~/.ai6/ai6-review.sh with bridges in the same dir. Resolve bridges relative to here.
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional config file. Conditional assignment inside it means inline env still wins.
AI6_CONFIG="${AI6_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ai6/config}"
# shellcheck source=/dev/null
[ -f "${AI6_CONFIG}" ] && . "${AI6_CONFIG}"

# Decide which bridge handles this review. Echoes the chosen bridge (name or path).
ai6_choose_bridge() {
  if [ -n "${AI6_FORWARD_BRIDGE:-}" ]; then
    printf '%s\n' "${AI6_FORWARD_BRIDGE}"
  elif command -v opencode >/dev/null 2>&1; then
    printf '%s\n' "ask-glm.sh"
  else
    printf '%s\n' "ask-claude.sh"
  fi
}

# Resolve a bridge selector to a path: absolute as-is, otherwise relative to this dir.
ai6_bridge_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s\n' "${SCRIPT_DIR}/$1" ;;
  esac
}

BRIDGE="$(ai6_choose_bridge)"
BRIDGE_PATH="$(ai6_bridge_path "${BRIDGE}")"

# No silent failure (Rule 3): if the chosen bridge isn't runnable, say which and why.
if [ ! -x "${BRIDGE_PATH}" ]; then
  echo "ai6: review bridge not found or not executable: ${BRIDGE_PATH}" >&2
  if [ -n "${AI6_FORWARD_BRIDGE:-}" ]; then
    echo "ai6:   (set by AI6_FORWARD_BRIDGE='${AI6_FORWARD_BRIDGE}')" >&2
  fi
  exit 1
fi

# Transparency: this branch is reached only by auto-fallback — ai6_choose_bridge picks
# ask-claude.sh with an empty AI6_FORWARD_BRIDGE only when opencode is absent. Tell the
# human the review is same-host (Claude judging Claude), a weaker second perspective,
# so they can weigh the verdict accordingly.
if [ "${BRIDGE}" = "ask-claude.sh" ] && [ -z "${AI6_FORWARD_BRIDGE:-}" ]; then
  echo "ai6: opencode not on PATH — routing review to the Claude reviewer (${AI6_CLAUDE_MODEL:-opus}); this is Claude reviewing Claude, not a second model." >&2
fi

exec "${BRIDGE_PATH}" "$@"
