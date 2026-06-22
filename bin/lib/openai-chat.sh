#!/usr/bin/env bash
#
# ai6 OpenAI-compatible chat call — the single external command ask-openai.sh hands to
# the shared runner. Reads a review request on stdin, sends it to an OpenAI-compatible
# /chat/completions endpoint, and writes ONLY the reviewer's reply to stdout (so the
# runner captures a clean review). Diagnostics go to stderr.
#
# impure: network IO. Exits non-zero on any transport/API error so the runner degrades
# to a parseable `VERDICT: ERROR` instead of emitting a bogus review (Rule 3).
#
# Env (set/exported by ask-openai.sh):
#   AI6_OPENAI_BASE_URL    required — endpoint base, e.g. http://localhost:11434/v1
#   AI6_OPENAI_MODEL       required — model id at that endpoint
#   AI6_OPENAI_API_KEY     optional — bearer token (local servers need none)
#   AI6_OPENAI_SYS         system prompt (the reviewer contract)
#   AI6_OPENAI_TEMPERATURE optional — sampling temperature (default 0; must be JSON-numeric)

set -euo pipefail

readonly BASE="${AI6_OPENAI_BASE_URL:?AI6_OPENAI_BASE_URL not set}"
readonly MODEL="${AI6_OPENAI_MODEL:?AI6_OPENAI_MODEL not set}"
readonly SYS="${AI6_OPENAI_SYS:-You are a rigorous, read-only code reviewer.}"
# Omit-colon default: an UNSET temperature becomes 0, but an explicitly EMPTY one stays
# empty so it can be dropped from the request (reasoning models that reject a custom
# temperature can run with AI6_OPENAI_TEMPERATURE= set empty).
readonly TEMP="${AI6_OPENAI_TEMPERATURE-0}"
readonly URL="${BASE%/}/chat/completions"

# All failures exit non-zero with one consistent prefix (Rule 3) so the runner degrades to
# VERDICT: ERROR. Defined before first use (the temperature check / payload build).
fail() { echo "ai6: openai-chat: ${1}" >&2; exit 1; }

# Validate temperature here, not inside jq: a non-numeric value would make `jq tonumber`
# die with a raw, prefixless jq error under set -e. Empty is allowed (field omitted).
if [ -n "${TEMP}" ] && ! printf '%s' "${TEMP}" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  fail "AI6_OPENAI_TEMPERATURE must be a non-negative number or empty (got: ${TEMP})"
fi

# Build the body with jq, not string concatenation: the user content is a large markdown
# document (diff + full files) full of quotes, backticks and braces. jq guarantees correct
# JSON escaping, so untrusted file content can't break out of the request or inject fields
# (Rule 8). --rawfile slurps stdin (the request) as one string. temperature is included
# only when TEMP is non-empty.
payload="$(jq -n \
  --arg model "${MODEL}" \
  --arg sys "${SYS}" \
  --arg temp "${TEMP}" \
  --rawfile user /dev/stdin \
  '{model:$model, stream:false,
    messages:[{role:"system",content:$sys},{role:"user",content:$user}]}
   + (if $temp == "" then {} else {temperature: ($temp | tonumber)} end)')"

# Send the body on curl's stdin (--data-binary @-), NEVER as an argv argument: a single
# argv string is capped at ~128 KiB on Linux (MAX_ARG_STRLEN, not raisable), well under
# ai6's AI6_MAX_CHARS budget, so an argv body would E2BIG on large reviews — defeating the
# chunk-review feature. A bearer token (cloud only) is passed via --config on a
# process-substituted fd, so it never appears in argv / `ps` either. No --max-time: the
# shared runner already wraps this in `timeout AI6_TIMEOUT`, the single bound on a review.
if [ -n "${AI6_OPENAI_API_KEY:-}" ]; then
  resp="$(printf '%s' "${payload}" | curl -sS "${URL}" \
    -H 'Content-Type: application/json' --data-binary @- \
    --config <(printf 'header = "Authorization: Bearer %s"\n' "${AI6_OPENAI_API_KEY}"))" \
    || fail "HTTP request to ${URL} failed."
else
  resp="$(printf '%s' "${payload}" | curl -sS "${URL}" \
    -H 'Content-Type: application/json' --data-binary @-)" \
    || fail "HTTP request to ${URL} failed."
fi

# A truly empty body at curl exit 0 (HTTP 204, an empty-bodied error, a reset after
# headers) would otherwise leak through as an empty review at exit 0, breaking this
# script's contract. Fail it explicitly so the runner degrades to VERDICT: ERROR.
[ -z "${resp}" ] && fail "empty response body from ${URL}"

# An OpenAI-compatible error comes back as {"error": ...} (some servers send it with HTTP
# 200), so detect it explicitly rather than trust the status code. Surface any error (or
# empty completion, or unparseable body) on stderr and exit non-zero so the runner degrades
# to VERDICT: ERROR. `empty` from jq means "no problem".
err="$(printf '%s' "${resp}" | jq -r '
  if .error then (.error | if type=="object" then (.message // tostring) else tostring end)
  elif (.choices[0].message.content // "") == "" then "empty response (no choices[0].message.content)"
  else empty end' 2>/dev/null || echo "unparseable response from ${URL}")"

[ -n "${err}" ] && fail "${err}"

printf '%s' "${resp}" | jq -r '.choices[0].message.content'
