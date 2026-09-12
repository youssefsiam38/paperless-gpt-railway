# Maintenance

## Release process

1. Make the change on a branch. The `test` workflow runs the full suite on every push and pull
   request.
2. Run locally:
   ```bash
   docker compose build --pull
   tests/static.sh && tests/smoke.sh && tests/persistence.sh
   ```
3. Tag `vX.Y.Z`. The `publish-image` workflow builds an amd64 candidate, runs the smoke and
   persistence suites against that exact image, and only then pushes it to GHCR as `X.Y.Z`, `X.Y`
   and `latest`.
4. Update the Railway template to the new tag. `RAILWAY_TEMPLATE.md` records the exact
   configuration; the template pins a version tag, never a digest, because the template generator
   rejects `@sha256:` references.
5. Deploy the updated template into a scratch project and run
   `tests/railway-smoke.sh https://domain` against it before leaving it published.

## What to watch

| Source | Why |
|---|---|
| https://github.com/icereed/paperless-gpt/releases | New versions, renamed settings, new routes. |
| That repository's `main.go` | **The wrapper exists because no route there authenticates.** New routes land behind basic auth automatically, but if upstream adds a login, this template should shrink rather than keep a second one. |
| That repository's `entrypoint.sh` | The wrapper invokes it directly, and relies on it dropping privileges. |
| https://github.com/paperless-ngx/paperless-ngx/releases | The API this service calls. A change to the token header or the documents endpoint shows up here first. |
| https://github.com/caddyserver/caddy/releases | Security fixes in the front door. |

## Breaking-change checklist

Before bumping the upstream digest, confirm:

- [ ] `/app/entrypoint.sh` still exists and still starts the binary with no arguments.
- [ ] `LISTEN_INTERFACE` is still the variable the listener reads, and still takes `host:port`.
- [ ] `PAPERLESS_BASE_URL` and `PAPERLESS_API_TOKEN` are still required and still named that.
- [ ] `/api/tags` still answers with the tags from the connected instance; a smoke test asserts it.
- [ ] The image is still Alpine, or the `apk add bash` line changes with it.
- [ ] No route has grown its own authentication that would double up with the proxy's.

## Rolling back

Republish the template with the previous wrapper tag. The only local state is a small job database,
and your documents are in paperless-ngx, so a rollback is a tag change and a redeploy.

## If this repository is abandoned

The image is a thin wrapper: the Dockerfile, the entrypoint and the tests are the whole of it. Fork
it, change the `org.opencontainers.image.source` label and the GHCR path, and publish your own
template. Nothing in the design depends on this account.
