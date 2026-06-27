#!/usr/bin/env bash
#
# ai6 security scan — run the project against the full COMPREHENSIVE SECURITY
# AUDIT PROTOCOL (security/SECURITY_CHECKLIST.md), section by section, and
# write a single aggregated audit report.
#
# Exhaustive by design. This is the "must-run" net before any production push.
# Each of the 10 top-level checklist sections becomes one reviewer pass, using
# the same bounded/retried/serialized invoker as a normal /ai6 review.
#
# impure: reads project files, spawns reviewer model calls, writes audit
# artifacts under .ai6/audits/.
#
# Usage:
#   ai6-security-scan.sh                  # interactive — prompts for confirmation
#   ai6-security-scan.sh --yes            # skip the prompt; the CALLER guarantees
#                                          it has already obtained explicit human
#                                          confirmation (the slash commands do this).
#                                          DO NOT pass --yes from autonomous loops
#                                          without a human-in-the-loop check first —
#                                          a full scan can burn 1-3M reviewer tokens.
#
# Tunables (env or ~/.config/ai6/config):
#   AI6_REVIEWER_MODEL      provider/model to use as the reviewer
#   AI6_SECURITY_CHECKLIST  override the checklist path (otherwise project's
#                           docs/SECURITY_CHECKLIST.md, otherwise installed default)

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AI6_HOME="${AI6_HOME:-$HOME/.ai6}"

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/build-request.sh"   # provides ai6_fence
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/run-review.sh"      # provides ai6_invoke_reviewer
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/security-scan.sh"   # provides ai6_security_*

AI6_CONFIG="${AI6_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ai6/config}"
# shellcheck source=/dev/null
[ -f "${AI6_CONFIG}" ] && . "${AI6_CONFIG}"

readonly MODEL="${AI6_SECURITY_MODEL:-${AI6_REVIEWER_MODEL:-zai-coding-plan/glm-5.2}}"
# Use the security-reviewer agent regardless of the user's AI6_REVIEWER_AGENT
# (which is set for normal /ai6 reviews and would silently shadow our fallback).
# Override only via the dedicated AI6_SECURITY_AGENT env var.
readonly AGENT="${AI6_SECURITY_AGENT:-ai6-security-reviewer}"
readonly PROJECT_DIR="$(pwd -P)"
readonly AUDIT_DIR="${PROJECT_DIR}/.ai6/audits"

CONFIRM_FLAG=""
[ "${1:-}" = "--yes" ] && CONFIRM_FLAG="yes"

if ! command -v opencode >/dev/null 2>&1; then
  echo "ai6: opencode is not installed or not on PATH." >&2
  exit 1
fi

CHECKLIST="$(ai6_security_checklist_path || true)"
if [ -z "${CHECKLIST}" ]; then
  echo "ai6: no security checklist found." >&2
  echo "ai6:   tried \$AI6_SECURITY_CHECKLIST, ${PROJECT_DIR}/docs/SECURITY_CHECKLIST.md, ${AI6_HOME}/security/SECURITY_CHECKLIST.md" >&2
  exit 1
fi

# grep -c returns 1 on zero matches; under set -e that'd kill us with no useful
# error. Tolerate the zero case and turn it into a clear error message.
N_SECTIONS="$(grep -cE '^## [0-9]+\. ' "${CHECKLIST}" || true)"
readonly N_SECTIONS
if [ "${N_SECTIONS}" -eq 0 ]; then
  echo "ai6: checklist at ${CHECKLIST} has no '## N.' top-level sections — nothing to scan." >&2
  echo "ai6:   (a project override at docs/SECURITY_CHECKLIST.md must follow the same structure as the shipped checklist)." >&2
  exit 1
fi

# --- confirmation gate -----------------------------------------------------
print_warning() {
  cat >&2 <<EOF
================================================================
                    ai6 SECURITY AUDIT
================================================================
This runs the FULL Comprehensive Security Audit Protocol against this project.

  Project:    ${PROJECT_DIR}
  Checklist:  ${CHECKLIST}
  Sections:   ${N_SECTIONS} top-level (one reviewer pass per section)
  Reviewer:   ${MODEL}

WARNING — this is exhaustive and token-heavy by design.
  - Expect roughly 1-3 million reviewer-model tokens for a typical project.
  - Runtime can be 10-30+ minutes (each section is a full reviewer pass).
  - Cost scales with your reviewer-model pricing; check your plan.

It is also non-negotiable for production. The whole point of this scan is to
catch the items a partial review would miss. If you can't afford to run it,
you can't afford to ship to production.

Output: an aggregated report at .ai6/audits/<timestamp>-security-audit.md plus
the per-section requests/responses, all gitignored.
EOF
}

print_warning
if [ "${CONFIRM_FLAG}" != "yes" ]; then
  printf 'Type "yes" to start the full audit (anything else aborts): ' >&2
  read -r answer || answer=""
  case "${answer}" in
    yes|YES|y|Y) : ;;
    *) echo "ai6: aborted by user." >&2; exit 130 ;;
  esac
fi

# --- prep ------------------------------------------------------------------
mkdir -p "${AUDIT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
RESP="${AUDIT_DIR}/${STAMP}-security-audit.md"

# Per-pass invoker — same shape as the normal review bridge, just different
# agent/system focus. ai6_invoke_reviewer always returns 0 and writes a
# parseable response (or a VERDICT: ERROR fallback).
ai6_invoke_one() {
  ai6_invoke_reviewer "$2" /dev/null -- \
    opencode run \
      --agent "${AGENT}" \
      --model "${MODEL}" \
      --dir "${PROJECT_DIR}" \
      --port 0 \
      "Audit the project against the attached security-checklist section." \
      --file="$1"
}

# --- the scan: one pass per top-level section ------------------------------
echo "ai6: scanning ${N_SECTIONS} sections of $(basename "${CHECKLIST}")..." >&2
PARTS=()
i=1
while [ "${i}" -le "${N_SECTIONS}" ]; do
  TITLE="$(ai6_security_section_title "${CHECKLIST}" "${i}")"
  REQ="${AUDIT_DIR}/${STAMP}-section$(printf '%02d' "${i}")-request.md"
  PRESP="${AUDIT_DIR}/${STAMP}-section$(printf '%02d' "${i}")-response.md"
  echo "ai6: [$(printf '%2d' "${i}")/${N_SECTIONS}] ${TITLE}" >&2
  ai6_security_build_request "${REQ}" "${i}" "${TITLE}" "${CHECKLIST}"
  ai6_invoke_one "${REQ}" "${PRESP}" || true
  # Ensure a CANONICAL verdict line exists. The aggregator will already collapse
  # an unrecognized token to ERROR, but tightening here means a missing-or-broken
  # verdict reliably resolves to ERROR right at the source.
  grep -qE '^SECTION VERDICT: (PASS|NEEDS-WORK|BLOCK|ERROR)$' "${PRESP}" 2>/dev/null \
    || printf '\nSECTION VERDICT: ERROR\n' >> "${PRESP}"
  v="$(grep -E '^SECTION VERDICT:' "${PRESP}" | tail -1 | awk '{print $3}')"
  echo "ai6:        -> ${v}" >&2
  PARTS+=( "${PRESP}" )
  i=$(( i + 1 ))
done

# --- aggregate -------------------------------------------------------------
ai6_security_aggregate "${RESP}" "${STAMP}" "${CHECKLIST}" "${PROJECT_DIR}" "${MODEL}" "${PARTS[@]}"
echo "ai6: audit report written to ${RESP}" >&2
overall="$(grep -m1 -E '^## Overall verdict:' "${RESP}" | awk '{print $4}')"
echo "ai6: overall verdict: ${overall}" >&2
cat "${RESP}"
