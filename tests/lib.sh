#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for paperless-gpt-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://127.0.0.1:8080}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

# CREDS_FILE holds "username:password" and is never printed.
creds() { cat "${CREDS_FILE:?CREDS_FILE not set}"; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }
auth_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 -u "$(creds)" "$@"; }
auth_body() { curl -s --max-time 60 -u "$(creds)" "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

wait_for_log() {
  local pattern=$1 service=${2:-gpt} timeout=${3:-180} start
  start=$(date +%s)
  while :; do
    compose logs --no-color "$service" 2>/dev/null | grep -q -- "$pattern" && return 0
    [ $(( $(date +%s) - start )) -ge "$timeout" ] && return 1
    sleep 2
  done
}

# run_side_container NAME CONTAINER_PORT ARGS... -> prints the base URL it can be reached on.
# The host port is left to Docker and read back, because a fixed one is a collision waiting to
# happen on a shared machine or a CI runner, and a failed bind is invisible when the run is
# redirected to /dev/null.
run_side_container() {
  local name=$1 cport=$2; shift 2
  docker rm -f "$name" >/dev/null 2>&1 || true
  if ! docker run -d --name "$name" -p "127.0.0.1::${cport}" "$@" >"$TEST_TMP/${name}.run" 2>&1; then
    printf 'could not start %s:\n%s\n' "$name" "$(cat "$TEST_TMP/${name}.run")" >&2
    return 1
  fi
  local hport
  hport=$(docker port "$name" "$cport" 2>/dev/null | head -1 | sed 's/.*://')
  [ -n "$hport" ] || { printf 'no published port for %s\n' "$name" >&2; return 1; }
  printf 'http://127.0.0.1:%s' "$hport"
}

# side_container_logs NAME -- for a failure message, never in the happy path.
side_container_logs() { docker logs "$1" 2>&1 | tail -20; }

# wrapper_image -- the image under test, by service name. `compose config --images` sorts by image
# name rather than service name, so with a second service in the file `head -1` can hand back the
# stand-in instead, and every container started from it then exits 0 with no output.
wrapper_image() { compose config --format json | jq -r '.services.gpt.image'; }

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
