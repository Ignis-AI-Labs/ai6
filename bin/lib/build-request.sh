#!/usr/bin/env bash
#
# ai6 shared request builder — the single source of truth for what the Reviewer
# sees, in BOTH directions. Sourced by ask-glm.sh and ask-claude.sh so the
# security-critical file-containment filter can never drift between them.
#
# impure: reads git state and files, writes the request file.
#
# Contract: the caller must have set CONTEXT, FILES (array), PROJECT_DIR, and REQ
# before calling ai6_build_request.

# Assemble the review request at "${REQ}".
ai6_build_request() {
  # A missing law means a degraded, near-useless review. Warn the human loudly
  # rather than failing silently (Rule 3: no silent failures).
  if [ ! -f "${PROJECT_DIR}/AGENTS.md" ]; then
    echo "ai6: WARNING — no AGENTS.md at ${PROJECT_DIR}. Reviewing without a project law." >&2
    echo "ai6:           Run 'bash ~/.ai6/ai6-init.sh' to scaffold one." >&2
  fi
  {
    echo "# ai6 Review Request"
    echo
    echo "## Builder context (what was done and why)"
    echo
    echo "${CONTEXT}"
    echo

    if git -C "${PROJECT_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
      local diff
      diff="$(git -C "${PROJECT_DIR}" --no-pager diff HEAD 2>/dev/null || true)"
      if [ -n "${diff}" ]; then
        echo "## Git diff (uncommitted, vs HEAD)"
        echo
        echo '```diff'
        echo "${diff}"
        echo '```'
        echo
      fi
    fi

    if [ "${#FILES[@]}" -gt 0 ]; then
      echo "## Files under review (full contents)"
      local f rp
      for f in "${FILES[@]}"; do
        echo
        echo "### ${f}"
        # Untrusted input (Rule 8): the file list comes from the agent. Only read
        # files inside the project root, so a confused or prompt-injected agent
        # can't exfiltrate secrets (e.g. ~/.ssh/id_rsa, .env) to the reviewer model.
        rp="$(realpath -m -- "${f}" 2>/dev/null || true)"
        [ -n "${rp}" ] || rp="${PROJECT_DIR}/${f}"
        case "${rp}" in
          "${PROJECT_DIR}"|"${PROJECT_DIR}"/*) : ;;
          *) echo "_(skipped, outside project root: ${f})_"; continue ;;
        esac
        if [ -f "${rp}" ]; then
          echo '```'
          cat "${rp}"
          echo '```'
        else
          echo "_(file not found: ${f})_"
        fi
      done
      echo
    fi

    if [ -f "${PROJECT_DIR}/AGENTS.md" ]; then
      echo "## Standard to judge against (AGENTS.md)"
      echo
      echo '```markdown'
      cat "${PROJECT_DIR}/AGENTS.md"
      echo '```'
    else
      echo "## ⚠ No AGENTS.md at the project root"
      echo
      echo "No project law was provided. Review against sound general engineering"
      echo "practice, and raise the missing AGENTS.md as a finding so the user can"
      echo "scaffold one with \`bash ~/.ai6/ai6-init.sh\`."
    fi
  } > "${REQ}"
}
