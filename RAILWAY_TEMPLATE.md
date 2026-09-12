# Railway template configuration

The published template. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | paperless-gpt |
| Code | `paperless-gpt` |
| Template id | `ca642fa6-9e0a-40c5-a560-13d222d8f31c` |
| Category | AI/ML |
| Image | `ghcr.io/youssefsiam38/paperless-gpt-railway:<version>` |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

## Service `gpt` — public

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/paperless-gpt-railway:<version>` |
| Port | 8080 |
| Domain | generated, target port 8080 |
| Healthcheck | `/healthz` |
| Volume | `/app/db` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PAPERLESS_GPT_AUTH_USERNAME` | `admin` |
| `PAPERLESS_GPT_AUTH_PASSWORD` | `${{secret(24)}}` |
| `PAPERLESS_BASE_URL` | `https://paperless.example.com` |
| `PAPERLESS_API_TOKEN` | empty, **marked optional** |
| `LLM_PROVIDER` | `openai` |
| `LLM_MODEL` | `gpt-4o-mini` |
| `OPENAI_API_KEY` | empty, **marked optional** |
| `PORT` | `8080` |
| `TZ` | `UTC` |

## Notes

- Every variable has a value or a generator, so a headless deploy works without a TTY. **An empty
  default is not a value**: `railway deploy -t <code>` fails with "Failed to prompt for options: The
  input device is not a TTY" until the variable is also marked optional. That is why
  `PAPERLESS_API_TOKEN` and `OPENAI_API_KEY` carry `isOptional: true`; they then arrive unset rather
  than empty, which the entrypoint reads the same way.
- **`PAPERLESS_BASE_URL` ships as a placeholder on purpose.** Until the deployer replaces it and
  supplies a token, the wrapper does not start the application and serves a page, behind the
  password, naming both variables. The deploy goes green either way, which is the point: the
  alternative is a healthcheck timeout with nothing to look at.
- **The healthcheck path must be `/healthz`.** That route belongs to the wrapper. paperless-gpt has
  no health endpoint, and every route it does have needs a credential.
- **`PORT` and the domain's target port must match.** Railway runs its healthcheck against the value
  of `PORT`. The upstream image listens on `:8080` by default, so the wrapper gives the application
  `127.0.0.1:8090` and keeps 8080 for the proxy; the entrypoint refuses a configuration where they
  collide.
- Do not add `LISTEN_INTERFACE` with a non-loopback host. The wrapper refuses it, because it would
  publish unauthenticated write access to the connected archive.
- The volume mounts `/app/db`, which holds job records and settings. The documents stay in
  paperless-ngx.
- There is no second service and nothing on the private network. If the deployer's paperless-ngx is
  also on Railway, `PAPERLESS_BASE_URL` can use its private domain.
