#!/usr/bin/env bash
#
# ai6 init — scaffold the files the review loop depends on into the current project:
#   AGENTS.md   the shared law the Reviewer judges against
#   CLAUDE.md   a thin pointer so Claude Code reads AGENTS.md
#
# Without an AGENTS.md at the project root, reviews have no standard to judge by, so
# this seeds one from the ai6 template. Existing files are NEVER overwritten.
#
# impure: reads templates, writes project files.
#
# Usage: run from your project root —  bash ~/.ai6/ai6-init.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TPL="${SCRIPT_DIR}/templates"

# create_if_missing FILENAME: copy the template into the cwd unless it already exists.
create_if_missing() {
  local name="$1"
  if [ -e "${name}" ]; then
    printf 'ai6: %s already exists — left untouched.\n' "${name}"
  elif [ -f "${TPL}/${name}" ]; then
    cp "${TPL}/${name}" "${name}"
    printf 'ai6: created %s from template.\n' "${name}"
  else
    printf 'ai6: template not found at %s — cannot create %s.\n' "${TPL}/${name}" "${name}" >&2
    return 1
  fi
}

create_if_missing AGENTS.md
create_if_missing CLAUDE.md

printf 'ai6: ready. Adapt AGENTS.md (Rules 1-8) to your project, keep Rule 9, then run /ai6.\n'
