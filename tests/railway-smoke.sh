#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional: CREDS_FILE=/path/to/file holding "username:password"
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and routing"
# Railway's edge serves 404 for a few seconds while a deployment takes over, so wait rather than
# racing the cutover when this runs straight after a deploy.
wait_for_code "$BASE_URL/healthz" 200 420 || true
assert_eq "health route answers over https" "200" "$(http_code "$BASE_URL/healthz")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/healthz" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/healthz")"

section "the instance is not open to the internet"
assert_eq "web interface refused" "401" "$(http_code "$BASE_URL/")"
assert_eq "document list refused" "401" "$(http_code "$BASE_URL/api/documents")"
assert_eq "tag list refused" "401" "$(http_code "$BASE_URL/api/tags")"
assert_eq "settings write refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{}' "$BASE_URL/api/settings")"
assert_eq "ocr jobs refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{}' "$BASE_URL/api/documents/1/ocr")"
assert_eq "wrong password refused" "401" "$(http_code -u "admin:wrong-password-entirely" "$BASE_URL/api/documents")"
assert_eq "health route publishes a status word and nothing else" "ok" "$(curl -s --max-time 20 "$BASE_URL/healthz")"

if [ -n "${CREDS_FILE:-}" ]; then
  section "signed in through the public domain"
  assert_eq "web interface served" "200" "$(auth_code "$BASE_URL/")"
  body=$(auth_body "$BASE_URL/")
  if grep -q 'not connected yet' <<<"$body"; then
    pass "the instance is deployed but not connected to a paperless-ngx yet"
    assert_contains "and the page names both variables" "PAPERLESS_API_TOKEN" "$body"
  else
    pass "the instance is connected to a paperless-ngx"
    assert_eq "tag list served" "200" "$(auth_code "$BASE_URL/api/tags")"
  fi
fi
summary
