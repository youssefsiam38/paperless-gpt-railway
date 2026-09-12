#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: the job history paperless-gpt keeps survives recreating the container, and the
# instance stays locked across the restart.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077
CREDS_FILE="$TEST_TMP/creds"; export CREDS_FILE
printf 'admin:%s' 'local-test-only-paperless-password' > "$CREDS_FILE"

section "fresh stack"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --no-build
wait_for_code "$BASE_URL/healthz" 200 300 || die "not ready"
assert_eq "the interface answers when signed in" "200" "$(auth_code "$BASE_URL/")"

section "the local database is on the volume"
mounts=$(docker inspect "$(compose ps -q gpt)" --format '{{range .Mounts}}{{.Destination}} {{end}}')
assert_contains "the database directory is mounted" "/app/db" "$mounts"
marker=$(compose exec -T gpt sh -c 'echo persisted > /app/db/.wrapper-test && cat /app/db/.wrapper-test' | tr -d '\r')
assert_eq "a file written into it" "persisted" "$marker"

section "recreate the container on the same volume"
compose down >/dev/null; compose up -d --no-build
wait_for_code "$BASE_URL/healthz" 200 300 || die "not ready after recreate"

section "verify"
marker=$(compose exec -T gpt sh -c 'cat /app/db/.wrapper-test 2>/dev/null' | tr -d '\r')
assert_eq "the database directory survived" "persisted" "$marker"
assert_eq "credentials unchanged" "200" "$(auth_code "$BASE_URL/")"
assert_eq "anonymous still refused" "401" "$(http_code "$BASE_URL/api/documents")"
assert_eq "health route still open" "200" "$(http_code "$BASE_URL/healthz")"
tags=$(auth_body "$BASE_URL/api/tags")
assert_contains "the connected paperless is still reachable" "paperless-gpt" "$tags"
summary
