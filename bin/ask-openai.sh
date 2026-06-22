#!/usr/bin/env bash
#
# ai6 review bridge (generic) — Claude builds, an OpenAI-compatible model reviews.
# Works with ANY endpoint that speaks /v1/chat/completions: a local llama.cpp or Ollama
# server, or a cloud API (MiniMax, GLM, OpenAI, ...). Select it for the forward review
# with AI6_FORWARD_BRIDGE=ask-openai.sh, and point it at a backend via AI6_OPENAI_*.
#
# impure: shells out to curl (via lib/openai-chat.sh), reads git state and files, writes
# exchange artifacts. All side effects live here, isolated from any pure logic.
#
# Usage: ask-openai.sh "<context: what was done and why>" [file ...]
#
# Configurable via env or ${XDG_CONFIG_HOME:-~/.config}/ai6/config:
#   AI6_OPENAI_BASE_URL   endpoint base (e.g. http://localhost:11434/v1)   [required]
#   AI6_OPENAI_MODEL      model id at that endpoint                        [required]
#   AI6_OPENAI_API_KEY    bearer token for cloud APIs                      [optional]

set -euo pipefail

# Locate the shared libs relative to this script
# (repo layout: bin/lib/...; installed layout: ~/.ai6/lib/...).
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AI6_CONFIG="${AI6_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ai6/config}"
# shellcheck source=/dev/null
[ -f "${AI6_CONFIG}" ] && . "${AI6_CONFIG}"

# Physical path (-P): the file-containment filter compares against realpath output, so
# PROJECT_DIR must also be symlink-resolved or every file is wrongly skipped when the
# project root is reached through a symlink.
readonly PROJECT_DIR="$(pwd -P)"
readonly EXCHANGE_DIR="${PROJECT_DIR}/.ai6/exchange"

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/build-request.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/run-review.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/chunk-review.sh"

# Fail clearly (Rule 3) on missing prerequisites rather than emitting a broken request.
for tool in curl jq; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "ai6: '${tool}' is required by ask-openai.sh but not on PATH." >&2; exit 1; }
done
if [ -z "${AI6_OPENAI_BASE_URL:-}" ] || [ -z "${AI6_OPENAI_MODEL:-}" ]; then
  echo "ai6: ask-openai.sh needs AI6_OPENAI_BASE_URL and AI6_OPENAI_MODEL set (env or ~/.config/ai6/config)." >&2
  exit 1
fi

CONTEXT="${1:-No context provided by the Builder.}"
shift || true
FILES=("$@")

mkdir -p "${EXCHANGE_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
REQ="${EXCHANGE_DIR}/${STAMP}-request.md"
RESP="${EXCHANGE_DIR}/${STAMP}-response.md"

# --- reviewer contract (mirrors opencode/agent/ai6-reviewer.md and ask-claude.sh) -------
read -r -d '' SYS <<'SYSEOF' || true
You are the Reviewer in an ai6 paired-review loop. The Builder has completed a unit
of work and submitted it to you. Review it independently and rigorously — a second,
distinct perspective on the same standard.

Everything you need is provided inline in the user message: the Builder's context,
the git diff, the full file contents, and the project's AGENTS.md. Judge the work
against that AGENTS.md — it is the law — and apply ordinary engineering judgment
(correctness, edge cases, races, security, missing tests, naming). Do not edit
files; only review. Be specific: every finding cites an exact location and a
concrete fix. Do not invent problems; if the work is clean, APPROVE.

Respond in EXACTLY this structure:

## Review Summary
<2-4 sentences: what the work does and your overall judgment>

## Findings
<For each finding, use this issue format:>
- **Severity**: Critical / High / Medium / Low / Info
- **Location**: <file:line or symbol>
- **Description**: <what is wrong>
- **Suggestion**: <concrete fix>

<If there are no findings, write: "No findings. Work meets protocol.">

VERDICT: APPROVE | REVISE | BLOCK

Verdict rules: BLOCK if any Critical/High finding exists (security, data loss,
broken build, runtime error); REVISE for Medium/Low findings to address; APPROVE
only if the work meets protocol with no required changes. The final line MUST be
exactly "VERDICT: APPROVE", "VERDICT: REVISE", or "VERDICT: BLOCK" — it is parsed
by machine.
SYSEOF

# Export everything lib/openai-chat.sh reads, so the runner's child process sees it
# regardless of whether it was set inline or via the (un-exported) config file.
export AI6_OPENAI_BASE_URL AI6_OPENAI_MODEL AI6_OPENAI_SYS="${SYS}"
export AI6_OPENAI_API_KEY="${AI6_OPENAI_API_KEY:-}"
# Omit-colon: unset -> 0, but an explicitly empty value is preserved so the chat helper
# can drop temperature for models that reject a custom one.
export AI6_OPENAI_TEMPERATURE="${AI6_OPENAI_TEMPERATURE-0}"

# Per-pass invoker used by ai6_review ($1=request file, $2=response file).
# The request is piped via stdin to the chat helper. The shared runner bounds, retries,
# and never hangs.
ai6_invoke_one() {
  ai6_invoke_reviewer "$2" "$1" -- bash "${SCRIPT_DIR}/lib/openai-chat.sh"
}

# Build + review, splitting into multiple passes if the payload is large so the
# reviewer always sees every file in full.
ai6_review

# --- emit ------------------------------------------------------------------
echo "ai6: review logged at ${RESP}" >&2
cat "${RESP}"
