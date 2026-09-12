#!/bin/bash
# paperless-gpt-railway entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. if the instance has not been pointed at a paperless-ngx yet, serve a page that says so
#   3. otherwise put the application on loopback and Caddy, with HTTP basic authentication, on the
#      public port, and supervise both
#
# paperless-gpt has no authentication of its own: `main.go` registers around thirty /api routes and
# none of them checks a credential. Those routes read documents, rewrite titles and tags, and send
# page images to a language model on the deployer's key. The wrapper supplies the boundary that
# upstream assumes the network provides.
set -uo pipefail

# Informational lines go to stdout and only failures to stderr. Railway derives a log's severity
# from the stream it arrived on, so a start-up message written to stderr is shown to the deployer
# in red as though something had gone wrong.
log()  { printf '[paperless-gpt-railway] %s\n' "$*"; }
fail() { printf '[paperless-gpt-railway] FATAL: %s\n' "$*" >&2; exit 1; }

: "${LISTEN_INTERFACE:=127.0.0.1:8090}"
: "${PAPERLESS_GPT_AUTH_USERNAME:=admin}"
: "${PAPERLESS_GPT_MAX_UPLOAD_MB:=64}"
: "${PAPERLESS_BASE_URL:=}"
: "${PAPERLESS_API_TOKEN:=}"
CADDYFILE=/etc/paperless-gpt-railway/Caddyfile
PLACEHOLDER_URL='https://paperless.example.com'

INTERNAL_HOST=${LISTEN_INTERFACE%:*}
INTERNAL_PORT=${LISTEN_INTERFACE##*:}

# The public listener takes the platform's PORT. Railway probes its healthcheck against that value
# (8080 when unset), so an app that ignores PORT is reported unhealthy however well it serves.
PUBLIC_PORT="${PORT:-8080}"
case "$PUBLIC_PORT" in
  ''|*[!0-9]*) fail "PORT must be a number, got \"$PUBLIC_PORT\"" ;;
esac
case "$INTERNAL_PORT" in
  ''|*[!0-9]*) fail "LISTEN_INTERFACE must end in a port, got \"$LISTEN_INTERFACE\"" ;;
esac
if [ "$PUBLIC_PORT" = "$INTERNAL_PORT" ]; then
  fail "PORT and the port in LISTEN_INTERFACE are both $PUBLIC_PORT. The public listener and the application cannot share a port; change LISTEN_INTERFACE."
fi
case "$INTERNAL_HOST" in
  127.0.0.1|localhost|::1) ;;
  *) fail "LISTEN_INTERFACE is \"$LISTEN_INTERFACE\". This image binds paperless-gpt to loopback on purpose: it has no authentication, and exposing it directly would publish read and write access to your document archive. Remove the variable." ;;
esac

case "$PAPERLESS_GPT_MAX_UPLOAD_MB" in
  ''|*[!0-9]*) fail "PAPERLESS_GPT_MAX_UPLOAD_MB must be a number, got \"$PAPERLESS_GPT_MAX_UPLOAD_MB\"" ;;
esac
[ "$PAPERLESS_GPT_MAX_UPLOAD_MB" -ge 1 ] || fail "PAPERLESS_GPT_MAX_UPLOAD_MB must be at least 1"

ALLOW_PUBLIC="${PAPERLESS_GPT_ALLOW_PUBLIC:-false}"
if [ "$ALLOW_PUBLIC" != "true" ]; then
  [ -n "${PAPERLESS_GPT_AUTH_PASSWORD:-}" ] || fail "missing required variable: PAPERLESS_GPT_AUTH_PASSWORD. paperless-gpt has no login of its own, so without this anyone who finds the URL can read your documents and rewrite them. Set a password, or set PAPERLESS_GPT_ALLOW_PUBLIC=true if you really want an open instance."
  [ "${#PAPERLESS_GPT_AUTH_PASSWORD}" -ge 12 ] || fail "PAPERLESS_GPT_AUTH_PASSWORD must be at least 12 characters"
  [ -n "$PAPERLESS_GPT_AUTH_USERNAME" ] || fail "PAPERLESS_GPT_AUTH_USERNAME must not be empty"
fi

# Has the deployer pointed this at their paperless-ngx yet? The template ships a placeholder so the
# first deploy succeeds and the deployer sees a page telling them what to fill in, rather than a
# healthcheck timeout with nothing to look at.
CONFIGURED=true
case "$PAPERLESS_BASE_URL" in
  ''|"$PLACEHOLDER_URL") CONFIGURED=false ;;
esac
[ -n "$PAPERLESS_API_TOKEN" ] || CONFIGURED=false

if [ "$CONFIGURED" = true ]; then
  case "$PAPERLESS_BASE_URL" in
    http://*|https://*) ;;
    *) fail "PAPERLESS_BASE_URL must start with http:// or https://, got \"$PAPERLESS_BASE_URL\"" ;;
  esac
fi

hash=""
if [ "$ALLOW_PUBLIC" != "true" ]; then
  hash=$(caddy hash-password --plaintext "$PAPERLESS_GPT_AUTH_PASSWORD" 2>/dev/null) \
    || fail "could not hash PAPERLESS_GPT_AUTH_PASSWORD"
  [ -n "$hash" ] || fail "empty password hash"
fi

emit_caddyfile() {
  cat > "$CADDYFILE" <<EOF
{
	admin off
	auto_https off
	persist_config off
}
:${PUBLIC_PORT} {
	request_body {
		max_size ${PAPERLESS_GPT_MAX_UPLOAD_MB}MB
	}

	# The platform healthcheck has no credentials to offer. This route says only whether the
	# container is up; it never touches the document archive.
	handle /healthz {
		respond "ok" 200
	}
EOF
  if [ "$CONFIGURED" != true ]; then
    # Nothing is started in this state, so there is nothing to proxy to. The page is the whole
    # application until the deployer fills in the two variables.
    cat >> "$CADDYFILE" <<EOF

	handle {
EOF
    [ "$ALLOW_PUBLIC" = "true" ] || cat >> "$CADDYFILE" <<EOF
		basic_auth {
			${PAPERLESS_GPT_AUTH_USERNAME} ${hash}
		}
EOF
    cat >> "$CADDYFILE" <<'EOF'
		header Content-Type "text/plain; charset=utf-8"
		respond `paperless-gpt is deployed but not connected yet.

Set these two service variables, then redeploy:

  PAPERLESS_BASE_URL   the address of your paperless-ngx, for example
                       https://paperless.example.com
  PAPERLESS_API_TOKEN  a token from that instance, under
                       Settings -> My Profile -> API Auth Token

Everything else already has a value.
` 200
	}
}
EOF
  else
    cat >> "$CADDYFILE" <<EOF

	handle {
EOF
    [ "$ALLOW_PUBLIC" = "true" ] || cat >> "$CADDYFILE" <<EOF
		basic_auth {
			${PAPERLESS_GPT_AUTH_USERNAME} ${hash}
		}
EOF
    cat >> "$CADDYFILE" <<EOF
		reverse_proxy ${LISTEN_INTERFACE}
	}
}
EOF
  fi
}

emit_caddyfile
unset hash
chmod 600 "$CADDYFILE"
caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1 \
  || fail "generated Caddy configuration is invalid"

if [ "$ALLOW_PUBLIC" = "true" ]; then
  log "WARNING: PAPERLESS_GPT_ALLOW_PUBLIC=true. Authentication is disabled and anyone who reaches this URL can read and rewrite the documents in the connected archive."
else
  log "authentication enabled for user \"${PAPERLESS_GPT_AUTH_USERNAME}\" (password length ${#PAPERLESS_GPT_AUTH_PASSWORD})"
fi

if [ "$CONFIGURED" != true ]; then
  log "PAPERLESS_BASE_URL and PAPERLESS_API_TOKEN are not set yet; serving the setup page and not starting the application"
  exec caddy run --config "$CADDYFILE" --adapter caddyfile
fi

log "connecting to paperless-ngx at ${PAPERLESS_BASE_URL} (token length ${#PAPERLESS_API_TOKEN})"
log "opening the public listener on :${PUBLIC_PORT} (upload limit ${PAPERLESS_GPT_MAX_UPLOAD_MB} MB)"
caddy run --config "$CADDYFILE" --adapter caddyfile &
caddy_pid=$!

log "starting paperless-gpt on ${LISTEN_INTERFACE}"
export LISTEN_INTERFACE PAPERLESS_BASE_URL PAPERLESS_API_TOKEN
/app/entrypoint.sh &
app_pid=$!

stopping=false
# shellcheck disable=SC2317  # reached through the trap below
term() { stopping=true; kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null; }
trap term TERM INT
wait -n "$app_pid" "$caddy_pid"
status=$?
if [ "$stopping" = true ]; then
  log "stopped on signal"
  status=0
else
  log "a supervised process exited with status ${status}; shutting down"
fi
kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null
wait 2>/dev/null
exit "$status"
