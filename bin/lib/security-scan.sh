#!/usr/bin/env bash
#
# ai6 security scan helpers — parse the SECURITY_CHECKLIST.md into its 10
# top-level sections and build per-section review requests. Reused by the
# orchestrator (bin/ai6-security-scan.sh) so the per-section logic and the
# overall scan flow are one source of truth.
#
# impure: reads files, writes per-section request files.

# Find the checklist to use for this run, in precedence order:
#   1. $AI6_SECURITY_CHECKLIST           explicit env override
#   2. <project>/docs/SECURITY_CHECKLIST.md   project-specific
#   3. $AI6_HOME/security/SECURITY_CHECKLIST.md   installed default
# Prints the resolved path on stdout, or returns 1 if none exists.
ai6_security_checklist_path() {
  local p
  for p in \
    "${AI6_SECURITY_CHECKLIST:-}" \
    "${PROJECT_DIR}/docs/SECURITY_CHECKLIST.md" \
    "${AI6_HOME:-$HOME/.ai6}/security/SECURITY_CHECKLIST.md"
  do
    [ -n "${p}" ] && [ -f "${p}" ] && { printf '%s' "${p}"; return 0; }
  done
  return 1
}

# Echo the title of section N (1-indexed) from the checklist at $1.
ai6_security_section_title() {
  local file="$1" n="$2"
  awk -v n="${n}" '/^## [0-9]+\. / { c++; if (c == n) { sub(/^## /, ""); print; exit } }' "${file}"
}

# Extract section N (1-indexed) from the checklist at $1 to stdout (slice from
# the section header through the line before the next `## ` or EOF).
ai6_security_section_extract() {
  local file="$1" n="$2"
  awk -v n="${n}" '
    /^## [0-9]+\. / { c++ }
    c == n { print }
    c == n+1 { exit }
  ' "${file}"
}

# Build a project-context block written to stdout — overview + repo tree + the
# key files a reviewer might want to spot-check (README, AGENTS.md, top configs).
# Trimmed to stay within a sensible per-section budget.
ai6_security_project_context() {
  local proj="${PROJECT_DIR}" fence

  echo "## Project overview"
  echo
  if [ -f "${proj}/README.md" ]; then
    fence="$(ai6_fence "${proj}/README.md")"
    echo "### README.md (first 200 lines)"
    echo "${fence}markdown"
    head -200 "${proj}/README.md"
    echo "${fence}"
    echo
  fi

  echo "### Repository tree (tracked files, paths only)"
  echo '```'
  if git -C "${proj}" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "${proj}" ls-files | head -400
  else
    find "${proj}" -type f \
      -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.ai6/*' \
      | sed "s|^${proj}/||" | head -400
  fi
  echo '```'
  echo

  if [ -f "${proj}/AGENTS.md" ]; then
    fence="$(ai6_fence "${proj}/AGENTS.md")"
    echo "### AGENTS.md (project law)"
    echo "${fence}markdown"
    cat "${proj}/AGENTS.md"
    echo "${fence}"
    echo
  fi

  # Spot-check config files commonly relevant across sections. Workflows live in
  # a directory; expand it so every workflow gets inspected (CI/CD is a primary
  # audit surface).
  local f
  for f in package.json pyproject.toml Cargo.toml foundry.toml hardhat.config.js \
           hardhat.config.ts go.mod requirements.txt Dockerfile docker-compose.yml \
           docker-compose.yaml; do
    [ -f "${proj}/${f}" ] || continue
    _ai6_security_emit_file "${proj}/${f}" "${f}"
  done
  if [ -d "${proj}/.github/workflows" ]; then
    for f in "${proj}/.github/workflows"/*.yml "${proj}/.github/workflows"/*.yaml; do
      [ -f "${f}" ] || continue
      _ai6_security_emit_file "${f}" ".github/workflows/$(basename "${f}")"
    done
  fi
}

# Emit one config file inside a backtick fence. Files are NOT truncated for the
# security audit: a truncated CI step or a hidden compose stage is exactly what an
# auditor needs to see, and silent truncation invites false PASS verdicts.
_ai6_security_emit_file() {
  local path="$1" label="$2" fence
  fence="$(ai6_fence "${path}")"
  echo "### ${label}"
  echo "${fence}"
  cat "${path}"
  echo "${fence}"
  echo
}

# Build the per-section review request. All inputs passed explicitly so the
# function has no hidden coupling to caller globals.
#   $1 = output path for the request
#   $2 = section number (1-based)
#   $3 = section title (human-readable)
#   $4 = path to the checklist file
# Still reads ${PROJECT_DIR} (set by the orchestrator), since the project context
# is necessarily a runtime concept; that single dependency is documented here.
ai6_security_build_request() {
  local out="$1" snum="$2" stitle="$3" checklist="$4"
  {
    echo "# ai6 Security Audit Request — Section ${stitle}"
    echo
    echo "You are auditing a project against one section of THE COMPREHENSIVE"
    echo "SECURITY AUDIT PROTOCOL. Evaluate every checklist item in the section."
    echo
    echo "$(ai6_security_project_context)"
    echo
    echo "## Checklist section to evaluate"
    echo
    local sfence
    sfence="$(ai6_security_section_extract "${checklist}" "${snum}" | ai6_fence -)"
    echo "${sfence}markdown"
    ai6_security_section_extract "${checklist}" "${snum}"
    echo "${sfence}"
    echo
    echo "## Your job"
    echo
    cat <<'RUBRIC'
For every `[ ]` item in the section above, evaluate it against the visible project
context and mark its status. **Do not invent capabilities.** If the evidence isn't
in front of you, mark NEEDS-INFO — never assume PASS.

For each item, output exactly one line in this format:
  - **[STATUS] [TAG] §X.Y.Z** — <item text> — <one-sentence evidence or what's missing>

Where:
  STATUS  = PASS | FAIL | N/A | NEEDS-INFO
  TAG     = the section's own priority tag (CRITICAL/HIGH/MEDIUM/LOW), as inherited
  §X.Y.Z  = the checklist subsection number (e.g. §1.1, §3.5)

After all items in this section, write a one-paragraph summary then the verdict:

SECTION VERDICT: PASS | NEEDS-WORK | BLOCK

Verdict rules:
  - BLOCK     if any [CRITICAL] item is FAIL, OR any item is marked
              [DEPLOYMENT BLOCKER] in the checklist text and FAIL.
  - NEEDS-WORK if any [HIGH]/[MEDIUM]/[LOW] item is FAIL, or any item is NEEDS-INFO.
  - PASS      only if every applicable item is PASS or N/A with justification.

The final line MUST be exactly "SECTION VERDICT: PASS", "SECTION VERDICT: NEEDS-WORK",
or "SECTION VERDICT: BLOCK" — it is parsed by machine.
RUBRIC
  } > "${out}"
}

# Aggregate section responses into one final report. All inputs passed explicitly.
#   $1     = output path for the aggregate report
#   $2     = run stamp (label only)
#   $3     = checklist path (label only)
#   $4     = project dir (label only)
#   $5     = reviewer model id actually used (label only)
#   $6...  = per-section response files, in order
#
# Verdict precedence (strictest wins): ERROR > BLOCK > NEEDS-WORK > PASS.
# ERROR is surfaced as ERROR — never silently demoted — because a non-completed
# section means the audit is incomplete, not "needs work".
ai6_security_aggregate() {
  local out="$1" stamp="$2" checklist="$3" project_dir="$4" model="$5"
  shift 5
  local presp v
  local overall="PASS" has_error=0 has_block=0 has_needs=0
  local -a verdicts=()
  local i=0
  for presp in "$@"; do
    i=$((i+1))
    # Match only an exact canonical verdict line. Any malformed line (typo, case
    # mismatch, trailing token, extra punctuation) yields no match and collapses
    # to ERROR — never silently to PASS. A false-clean verdict is the worst
    # failure mode of a security gate. Note: awk '{print $3}' was insufficient
    # because it strips trailing tokens (e.g. "PASS extra" -> "PASS").
    local v_line
    v_line="$(grep -E '^SECTION VERDICT: (PASS|NEEDS-WORK|BLOCK|ERROR)$' "${presp}" 2>/dev/null | tail -1 || true)"
    if [ -n "${v_line}" ]; then
      v="${v_line#SECTION VERDICT: }"
    else
      v="ERROR"
    fi
    verdicts+=( "${v}" )
    case "${v}" in
      ERROR)      has_error=1 ;;
      BLOCK)      has_block=1 ;;
      NEEDS-WORK) has_needs=1 ;;
    esac
  done
  if   [ "${has_error}" = 1 ]; then overall="ERROR"
  elif [ "${has_block}" = 1 ]; then overall="BLOCK"
  elif [ "${has_needs}" = 1 ]; then overall="NEEDS-WORK"
  fi
  # Defense-in-depth: never emit a clean verdict from an empty input set. The
  # orchestrator guards this, but this function is reusable and a security
  # aggregator must not be able to print PASS on zero parts.
  if [ "${#verdicts[@]}" -eq 0 ]; then overall="ERROR"; fi

  {
    echo "# ai6 Security Audit Report"
    echo
    echo "**Generated:** ${stamp}"
    echo "**Project:** ${project_dir}"
    echo "**Checklist:** ${checklist}"
    echo "**Reviewer model:** ${model}"
    echo
    echo "## Overall verdict: ${overall}"
    echo
    echo "Per-section verdicts (in order):"
    i=0
    for presp in "$@"; do
      i=$((i+1))
      printf '  %2d. %-12s %s\n' "${i}" "${verdicts[$((i-1))]}" "$(basename "${presp}")"
    done
    echo
    if [ "${overall}" = "ERROR" ]; then
      echo "> **AUDIT INCOMPLETE.** One or more sections could not be reviewed (timeout"
      echo "> or reviewer failure). Treat the audit as unfinished — re-run the scan or"
      echo "> raise \`AI6_TIMEOUT\` before relying on it for a deployment decision."
      echo
    fi
    if [ "${overall}" = "BLOCK" ]; then
      echo "> **DEPLOYMENT BLOCKER.** One or more sections contain a CRITICAL"
      echo "> failing item. Do not ship until every BLOCK is resolved."
      echo
    fi
    echo "---"
    echo
    echo "## Per-section detail"
    i=0
    for presp in "$@"; do
      i=$((i+1))
      echo
      echo "### Section $(printf '%02d' "${i}")  —  verdict: ${verdicts[$((i-1))]}"
      echo
      cat "${presp}"
      echo
      echo "---"
    done
  } > "${out}"
}
