#!/usr/bin/env bash
#
# ai6 shared reviewer runner — the single source of truth for HOW a review is
# invoked, so both bridges behave identically under load:
#   - bounded by a per-attempt timeout (a hang can never be permanent),
#   - retried on timeout/transient failure,
#   - optionally serialized across concurrent projects via a global lock,
#   - degraded gracefully to a parseable `VERDICT: ERROR` instead of hanging.
#
# impure: runs subprocesses, takes a global flock, writes the response file.
#
# Tunables (env or ~/.config/ai6/config):
#   AI6_TIMEOUT       seconds per attempt              (default 300)
#   AI6_RETRIES       extra attempts after the first   (default 1)
#   AI6_RETRY_DELAY   seconds between attempts         (default 3)
#   AI6_SERIALIZE     1 = one review at a time across all projects (default 1)
#   AI6_LOCK          lock file for serialization      (default ${XDG_RUNTIME_DIR:-~/.cache/ai6}/ai6-review.lock)
#   AI6_LOCK_TIMEOUT  max seconds to wait for the lock  (default 900)

# ai6_invoke_reviewer RESP STDIN_FILE -- CMD [ARGS...]
#   Runs `timeout CMD ARGS < STDIN_FILE > RESP` with retries and (optionally) a
#   global lock. Always returns 0; RESP always ends with a parseable VERDICT line.
ai6_invoke_reviewer() {
  local resp="$1" stdin_file="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  local -a cmd=( "$@" )

  local timeout_s="${AI6_TIMEOUT:-300}"
  local retries="${AI6_RETRIES:-1}"
  local delay="${AI6_RETRY_DELAY:-3}"
  local serialize="${AI6_SERIALIZE:-1}"
  # Keep the lock in a user-private dir (Rule 8): a shared /tmp path could be a
  # planted symlink that `exec 9>` would follow and truncate.
  local lock="${AI6_LOCK:-${XDG_RUNTIME_DIR:-${HOME}/.cache/ai6}/ai6-review.lock}"
  local lock_timeout="${AI6_LOCK_TIMEOUT:-900}"
  mkdir -p "$(dirname "${lock}")" 2>/dev/null || true

  if [ "${serialize}" = "1" ] && ! command -v flock >/dev/null 2>&1; then
    echo "ai6: AI6_SERIALIZE=1 but 'flock' not found; reviews run in parallel." >&2
    echo "ai6:   (install util-linux on Linux, or 'brew install flock' on macOS)." >&2
  fi

  # Resolve a timeout command: GNU 'timeout', or 'gtimeout' (macOS coreutils). If
  # neither exists, fall back to 'env' (an unbounded passthrough) with a warning,
  # rather than failing every review on a missing dependency.
  local -a tprefix
  if command -v timeout >/dev/null 2>&1; then
    tprefix=( timeout -k 10 "${timeout_s}" )
  elif command -v gtimeout >/dev/null 2>&1; then
    tprefix=( gtimeout -k 10 "${timeout_s}" )
  else
    tprefix=( env )
    echo "ai6: 'timeout' not found; reviews run UNBOUNDED (a hang won't auto-recover)." >&2
    echo "ai6:   install coreutils (macOS: 'brew install coreutils')." >&2
  fi

  # err lives next to the response (a gitignored exchange dir), reused per attempt,
  # so a mid-attempt kill leaves no /tmp litter.
  local attempt=0 rc=0 reason="" err="${resp}.err"
  while : ; do
    attempt=$((attempt + 1))

    if [ "${serialize}" = "1" ] && command -v flock >/dev/null 2>&1; then
      # Hold a global lock so only one review runs at a time across projects. fd 9 is
      # held by THIS shell, so `timeout` killing the reviewer still releases it, and
      # a wedged review can't block others past AI6_TIMEOUT.
      exec 9>"${lock}"
      if flock -w "${lock_timeout}" 9; then
        if "${tprefix[@]}" "${cmd[@]}" < "${stdin_file}" > "${resp}" 2>"${err}"; then
          rc=0
        else
          rc=$?
        fi
        flock -u 9
      else
        rc=200; reason="could not acquire the review lock within ${lock_timeout}s"
      fi
      exec 9>&-
    else
      if "${tprefix[@]}" "${cmd[@]}" < "${stdin_file}" > "${resp}" 2>"${err}"; then
        rc=0
      else
        rc=$?
      fi
    fi

    if [ "${rc}" -eq 0 ]; then rm -f "${err}"; return 0; fi

    if [ "${rc}" -eq 124 ]; then
      reason="reviewer timed out after ${timeout_s}s"
    elif [ -z "${reason}" ]; then
      reason="reviewer exited with code ${rc}: $(head -c 400 "${err}" 2>/dev/null | tr '\n' ' ')"
    fi
    rm -f "${err}"

    [ "${attempt}" -gt "${retries}" ] && break
    sleep "${delay}"
  done

  # Graceful degradation: never hang. Emit a parseable ERROR review.
  {
    echo "## ai6 Review Unavailable"
    echo
    echo "The review could not be completed after ${attempt} attempt(s): ${reason}."
    echo
    echo "This is an ai6 bridge error, not a verdict on the code. The work was NOT"
    echo "reviewed — do not treat it as approved."
    echo
    echo "VERDICT: ERROR"
  } > "${resp}"
  return 0
}
