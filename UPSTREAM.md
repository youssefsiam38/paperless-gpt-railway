# Upstream provenance

## paperless-gpt

| | |
|---|---|
| Project | https://github.com/icereed/paperless-gpt |
| Licence | MIT (`LICENSE`) |
| Version pinned | 0.27.0, released 2026-07-21 |
| Image | `ghcr.io/icereed/paperless-gpt:v0.27.0` |
| Digest | `sha256:855d9df5bacb2bed60bd520f1ffe0d118695aef9f77d37466ae85823001f547d` |
| Base | Alpine Linux; the application is a Go binary serving an embedded web build |

The image ships no bash, and the wrapper's entrypoint needs one for `wait -n`, which BusyBox ash
does not implement reliably. The Dockerfile installs it rather than rewriting the script around a
shell limitation; a static check asserts that the install is there.

Upstream's own `entrypoint.sh` creates a user, fixes ownership and drops privileges to uid 10001 with
`su-exec`. The wrapper invokes it rather than the binary, so that still happens.

## Caddy

| | |
|---|---|
| Project | https://caddyserver.com |
| Licence | Apache-2.0 |
| Version pinned | 2.10.2 via `caddy:2.10-alpine` |
| Digest | `sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d` |

Only the binary is copied out of that image.

## What this repository changes

It adds four things and removes none:

1. The Caddy binary at `/usr/local/bin/caddy`, and `bash` from Alpine's package index.
2. `scripts/entrypoint.sh` as the image entrypoint, which still invokes upstream's
   `/app/entrypoint.sh`.
3. Environment defaults that pin the application to loopback (`LISTEN_INTERFACE`).
4. The two upstream licences at `/usr/share/licenses/paperless-gpt-railway/`.

No Go file is patched, no route is added or rewritten, and no dependency is changed.

## Licence obligations

Both upstream licences are permissive and both require their notice to travel with the software.
They are vendored in `licenses/` and copied into the image. `THIRD_PARTY_NOTICES.md` records what is
shipped and why.

The wrapper itself is MIT.

## Bumping the upstream version

1. Read the upstream release notes, and **re-read the route table in `main.go`**. The wrapper's
   whole premise is that no route authenticates; if upstream adds a login, the design changes.
2. Resolve the new digest:
   `docker buildx imagetools inspect ghcr.io/icereed/paperless-gpt:vX.Y.Z`
3. Update `PAPERLESS_GPT_IMAGE` and `PAPERLESS_GPT_VERSION` in the Dockerfile and the assertion in
   `tests/static.sh`, which pins the tag string.
4. Run the full suite locally, then tag a release. CI rebuilds, retests against the candidate image
   and pushes.
