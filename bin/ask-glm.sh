#!/usr/bin/env bash
#
# ai6 review bridge — Claude builds, the second model (default: GLM via OpenCode)
# reviews. Hands the current work unit to the Reviewer and prints its review.
#
# impure: shells out to `opencode`, reads git state and files, writes exchange
# artifacts. All side effects live here, isolated from any pure logic.
#
# Usage: ask-glm.sh "<context: what was done and why>" [file ...]
#
# Configurable via env or ${XDG_CONFIG_HOME:-~/.config}/ai6/config:
#   AI6_REVIEWER_MODEL   provider/model for the reviewer (default zai-coding-plan/glm-5.2)
#   AI6_REVIEWER_AGENT   OpenCode agent to use            (default ai6-reviewer)

set -euo pipefail

# Locate the shared request builder relative to this script
# (repo layout: bin/lib/...; installed layout: ~/.ai6/lib/...).
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional config file. Use conditional assignment in it so inline env wins.
AI6_CONFIG="${AI6_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ai6/config}"
# shellcheck source=/dev/null
[ -f "${AI6_CONFIG}" ] && . "${AI6_CONFIG}"

readonly MODEL="${AI6_REVIEWER_MODEL:-zai-coding-plan/glm-5.2}"
readonly AGENT="${AI6_REVIEWER_AGENT:-ai6-reviewer}"
# Physical path (-P): the file-containment filter compares against realpath output,
# so PROJECT_DIR must also be symlink-resolved or every file is wrongly skipped when
# the project root is reached through a symlink.
readonly PROJECT_DIR="$(pwd -P)"
readonly EXCHANGE_DIR="${PROJECT_DIR}/.ai6/exchange"

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/build-request.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/run-review.sh"

if ! command -v opencode >/dev/null 2>&1; then
  echo "ai6: opencode is not installed or not on PATH." >&2
  exit 1
fi

CONTEXT="${1:-No context provided by the Builder.}"
shift || true
FILES=("$@")

mkdir -p "${EXCHANGE_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
REQ="${EXCHANGE_DIR}/${STAMP}-request.md"
RESP="${EXCHANGE_DIR}/${STAMP}-response.md"

ai6_build_request

# --- invoke the reviewer (timeout + retry + serialize + graceful) ----------
# The request is attached as a file to avoid argument-length limits on large diffs.
# NOTE: the message positional MUST come before --file= (the flag is a greedy array).
# --port 0 gives each run its own random server port (isolation across concurrent
# projects). The shared runner bounds, retries, and never hangs.
ai6_invoke_reviewer "${RESP}" /dev/null -- \
  opencode run \
    --agent "${AGENT}" \
    --model "${MODEL}" \
    --dir "${PROJECT_DIR}" \
    --port 0 \
    "Review the attached ai6 review request and respond in the required format." \
    --file="${REQ}"

# --- emit ------------------------------------------------------------------
echo "ai6: review logged at ${RESP}" >&2
cat "${RESP}"
