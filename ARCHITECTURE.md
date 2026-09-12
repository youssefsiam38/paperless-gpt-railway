# Architecture

## Service graph

One service, one small volume. The document archive lives in the paperless-ngx you already run,
which this service reaches over the internet or over Railway's private network.

```
internet --> Railway edge (TLS) --> :PORT  Caddy  --> 127.0.0.1:8090  paperless-gpt
                                      |                                    |
                                      |                                    +-- /app/db (volume)
                                      |                                    +--> your paperless-ngx
                                      +-- /healthz  open, a literal "ok"
                                      +-- everything else  HTTP basic auth
```

## Why a wrapper image

`main.go` registers about thirty routes under `/api` and none of them consults a credential:

```go
api.GET("/documents", app.documentsHandler)
api.POST("/generate-suggestions", app.generateSuggestionsHandler)
api.POST("/settings", app.updateSettingsHandler)
api.POST("/documents/:id/ocr", app.submitOCRJobHandler)
```

There is no setting that adds one. That is a reasonable design for a component you run on a private
network beside the paperless-ngx it talks to, and an unreasonable one to expose directly. What is
behind those routes is not a blank application: it is read and write access to a document archive,
plus the ability to spend whatever language-model key you configured.

Patching would mean maintaining a fork of a Go program against every upstream release. Fronting it
means the upstream image is used exactly as published, pinned by digest, and a version bump is a
one-line change with no code to re-review.

## The front door

Caddy is copied in as a static binary from the official `caddy:2.10-alpine` image. It listens on the
platform's `PORT` and proxies to the application on loopback.

Two route groups:

- `/healthz` is open and answers a literal `ok`. It is the wrapper's own route, not upstream's:
  paperless-gpt has no health endpoint, and every route it does have is one the platform must not be
  able to reach without a credential.
- Everything else requires HTTP basic authentication. The password is hashed with
  `caddy hash-password` at start-up; the plaintext never reaches the configuration file, and the
  file is written `0600` and validated with `caddy validate` before Caddy is allowed to read it.

## The unconfigured state

paperless-gpt cannot do anything without `PAPERLESS_BASE_URL` and `PAPERLESS_API_TOKEN`, and there
is no sensible default for either: they belong to an instance only the deployer knows about. A
template whose variables all need values would otherwise deploy, fail its healthcheck, and leave the
deployer looking at a crash loop.

So the entrypoint treats "not configured yet" as a first-class state. When the base URL is still the
placeholder the template ships, or the token is empty:

- the application is **not started** at all;
- Caddy serves a short plain-text page, still behind the password, naming the two variables and
  where to find the token;
- `/healthz` answers `ok`, so the deployment goes green and the deployer can read that page.

Filling the two variables in and redeploying moves it to the normal path. `tests/smoke.sh` covers
both states.

## Boot sequence

1. Validate the environment. Names of missing or wrong variables are printed; values never are.
2. Hash the password and write the Caddy configuration, then validate it.
3. If the instance is not configured yet, `exec` Caddy alone and stop here.
4. Otherwise start Caddy, then start the application on loopback through upstream's own
   `entrypoint.sh`, which drops privileges to uid 10001.
5. Supervise both. If either exits, the container exits and the platform restarts it. A stop signal
   exits 0, so a deliberate stop is not reported as a crash.

## Ports

| Port | Listener | Reachable from |
|---|---|---|
| `PORT` (8080) | Caddy | the internet |
| 8090 | paperless-gpt | inside the container only |

`LISTEN_INTERFACE` is pinned to `127.0.0.1:8090` in the image and the entrypoint refuses to start if
the host part is anything else, because moving the application off loopback would publish
unauthenticated write access to the archive.

Note that the upstream image defaults `LISTEN_INTERFACE` to `:8080`, the same port Railway probes.
The wrapper takes `PORT` for the public side and gives the application its own; the entrypoint
refuses a configuration where the two collide.

Railway runs its healthcheck against the value of `PORT`, not against the domain's target port. The
two must agree.

## Health

`/healthz` is the healthcheck path. It reports that the container is up and nothing else; it does
not proxy to the application and never touches the archive. In the unconfigured state it is the only
route that answers without a password.

## State

`/app/db` holds paperless-gpt's own small database of jobs, settings and prompts. Your documents are
never copied here; they stay in paperless-ngx and are fetched per request.
