#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test. Run `docker compose build` first (CI does), or set PAPERLESS_GPT_RAILWAY_IMAGE.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_PASSWORD='local-test-only-paperless-password'
LOCAL_TOKEN='local-test-only-paperless-token'
umask 077
CREDS_FILE="$TEST_TMP/creds"; export CREDS_FILE
printf 'admin:%s' "$LOCAL_PASSWORD" > "$CREDS_FILE"

section "fresh stack"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/healthz" 200 300 && pass "health route answers" || { compose logs --no-color gpt | tail -40; die "never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "start-up"
wait_for_log "opening the public listener" gpt 120 || true
logs=$(compose logs --no-color gpt)
assert_contains "authentication was enabled" "authentication enabled for user" "$logs"
assert_contains "the connection was reported by name, not by value" "connecting to paperless-ngx at" "$logs"
assert_contains "only the password's length was reported" "password length ${#LOCAL_PASSWORD}" "$logs"
assert_contains "only the token's length was reported" "token length ${#LOCAL_TOKEN}" "$logs"
assert_not_contains "password not in logs" "$LOCAL_PASSWORD" "$logs"
assert_not_contains "paperless token not in logs" "$LOCAL_TOKEN" "$logs"
# shellcheck disable=SC2016  # a bcrypt prefix, not a shell expansion
assert_not_contains "password hash not in logs" '\$2a\$' "$logs"

section "anonymous visitors are refused"
# Upstream registers around thirty /api routes and none of them checks a credential. Without the
# front door every one of these reads or rewrites the connected archive.
assert_eq "web interface refused" "401" "$(http_code "$BASE_URL/")"
assert_eq "document list refused" "401" "$(http_code "$BASE_URL/api/documents")"
assert_eq "tag list refused" "401" "$(http_code "$BASE_URL/api/tags")"
assert_eq "settings read refused" "401" "$(http_code "$BASE_URL/api/settings")"
assert_eq "settings write refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{}' "$BASE_URL/api/settings")"
assert_eq "prompt write refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{}' "$BASE_URL/api/prompts")"
assert_eq "suggestion jobs refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{}' "$BASE_URL/api/jobs/suggestions")"
assert_eq "ocr jobs refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{}' "$BASE_URL/api/documents/1/ocr")"
assert_eq "wrong password refused" "401" "$(http_code -u "admin:wrong-password-entirely" "$BASE_URL/api/documents")"
assert_eq "wrong username refused" "401" "$(http_code -u "nobody:$LOCAL_PASSWORD" "$BASE_URL/api/documents")"
assert_eq "health route stays open for the platform probe" "200" "$(http_code "$BASE_URL/healthz")"
assert_eq "health route publishes a status word and nothing else" "ok" "$(curl -s --max-time 20 "$BASE_URL/healthz")"

section "the application is not reachable except through the front door"
# curl still prints 000 through -w when it cannot connect, so `|| true` rather than `|| echo`
assert_eq "internal port is not published" "000" "$(http_code --max-time 5 "http://127.0.0.1:8090/api/documents" || true)"

section "signed in"
assert_eq "web interface served" "200" "$(auth_code "$BASE_URL/")"
# The tag list is fetched from the connected paperless with the configured token, so a tag defined
# only over there arriving here proves the proxy, the credential and the connection all work.
tags=$(auth_body "$BASE_URL/api/tags")
assert_contains "tags come from the connected paperless" "paperless-gpt" "$tags"
# The document list is upstream's own filtered view; against the stand-in it is empty, and what
# matters here is that the route answers with valid JSON rather than a proxy error.
docs=$(auth_body "$BASE_URL/api/documents")
assert_eq "the document route answers with json" "array" "$(jq -r 'type' <<<"$docs" 2>/dev/null || echo notjson)"

section "an unconfigured instance says so rather than failing"
# The template ships a placeholder URL so the first deploy goes green and the deployer is told what
# to fill in, instead of watching a healthcheck time out with nothing to look at.
img=$(wrapper_image)
UNCONF=$(run_side_container paperless-gpt-unconfigured 18081 \
  -e "PAPERLESS_GPT_AUTH_PASSWORD=$LOCAL_PASSWORD" \
  -e PAPERLESS_BASE_URL=https://paperless.example.com -e PORT=18081 "$img") \
  || die "could not start the unconfigured instance"
wait_for_code "$UNCONF/healthz" 200 120 \
  || { side_container_logs paperless-gpt-unconfigured; die "the unconfigured instance never answered"; }
assert_eq "the health route is still green" "200" "$(http_code "$UNCONF/healthz")"
assert_eq "and the page is still behind the password" "401" "$(http_code "$UNCONF/")"
page=$(curl -s --max-time 20 -u "$(creds)" "$UNCONF/" || true)
assert_contains "the page explains what is missing" "not connected yet" "$page"
assert_contains "and names both variables" "PAPERLESS_API_TOKEN" "$page"
assert_contains "the log says the application was not started" "not starting the application" "$(docker logs paperless-gpt-unconfigured 2>&1)"
docker rm -f paperless-gpt-unconfigured >/dev/null

section "graceful shutdown (SIGTERM)"
t1=$(date +%s); compose stop -t 30 gpt; dur=$(( $(date +%s)-t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q gpt)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start gpt; wait_for_code "$BASE_URL/healthz" 200 300 && pass "restarted" || die "did not restart"

section "fail-fast validation"
run_img() { docker run --rm "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img; then fail "should fail without a password"; else pass "exits without PAPERLESS_GPT_AUTH_PASSWORD"; fi
assert_contains "explains why a password is required" "anyone who finds the URL can read your documents" "$(cat "$TEST_TMP/ff.log")"
if run_img -e PAPERLESS_GPT_AUTH_PASSWORD=short; then fail "should reject a short password"; else pass "rejects a short password"; fi
assert_contains "states the length rule" "at least 12 characters" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "PAPERLESS_GPT_AUTH_PASSWORD=$LOCAL_PASSWORD" -e LISTEN_INTERFACE=0.0.0.0:8090; then fail "should refuse to unbind from loopback"; else pass "refuses a non-loopback listener"; fi
assert_contains "explains the loopback rule" "read and write access to your document archive" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "PAPERLESS_GPT_AUTH_PASSWORD=$LOCAL_PASSWORD" -e PORT=8090; then fail "should refuse a port collision"; else pass "refuses a port collision with the application"; fi
assert_contains "explains the collision" "cannot share a port" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "PAPERLESS_GPT_AUTH_PASSWORD=$LOCAL_PASSWORD" -e PAPERLESS_BASE_URL=paperless.example.com -e PAPERLESS_API_TOKEN=x; then fail "should reject a scheme-less URL"; else pass "rejects a PAPERLESS_BASE_URL without a scheme"; fi
assert_not_contains "no secret echoed" "$LOCAL_PASSWORD" "$(cat "$TEST_TMP/ff.log")"

section "the opt-out is deliberate and loud"
OPEN=$(run_side_container paperless-gpt-open 18083 -e PAPERLESS_GPT_ALLOW_PUBLIC=true -e PORT=18083 "$img") \
  || die "could not start the open instance"
wait_for_code "$OPEN/healthz" 200 120 \
  || { side_container_logs paperless-gpt-open; die "the open instance never answered"; }
assert_eq "an open instance serves anonymously" "200" "$(http_code "$OPEN/")"
assert_contains "and says so in the log" "Authentication is disabled" "$(docker logs paperless-gpt-open 2>&1)"
docker rm -f paperless-gpt-open >/dev/null

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version io.paperless-gpt-railway.upstream.version io.paperless-gpt-railway.caddy.version; do
  assert_contains "label $l" "\"$l\"" "$labels"
done
assert_contains "upstream licence shipped" "MIT License" "$(compose exec -T gpt head -1 /usr/share/licenses/paperless-gpt-railway/PAPERLESS-GPT-LICENSE | tr -d '\r')"
assert_contains "Caddy licence shipped" "Apache License" "$(compose exec -T gpt sed -n '2p' /usr/share/licenses/paperless-gpt-railway/CADDY-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep paperless-gpt-railway-test | sed 's/^/mem_/'; } | tee -a "$METRICS"
summary
