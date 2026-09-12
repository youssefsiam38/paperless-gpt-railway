# paperless-gpt on Railway

A community Railway template for [paperless-gpt][upstream], which adds language-model OCR, titles,
tags, correspondents and document types to an existing [paperless-ngx][ngx]. Point it at the archive
you already run and it suggests metadata for documents you have not sorted, and re-reads scans that
plain OCR could not. It is not affiliated with the paperless-gpt project.

paperless-gpt has **no authentication**. `main.go` registers around thirty routes under `/api` and
not one of them checks a credential, because the project expects to sit on a private network beside
the paperless-ngx it talks to. Those routes list your documents, rewrite their titles and tags, and
send page images to whichever language model you configured, on your API key. Railway gives every
service a public URL, so deployed as-is it is an open door into an archive that usually holds
contracts, invoices and correspondence.

This repository publishes a thin wrapper image that puts Caddy in front with HTTP basic
authentication and binds the application to loopback. No application code is changed.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/paperless-gpt)

## What you get

- The official upstream image, pinned by tag and digest, with Caddy in front.
- A password you never have to invent: the template generates one.
- **A first deploy that goes green before you have configured anything.** Until you supply your
  paperless-ngx address and token, the application is not started and the site serves a short page,
  behind the password, telling you which two variables to fill in.
- One open route, `/healthz`, for the platform probe. It returns the word `ok` and never touches the
  archive.
- An upload size cap and fail-fast validation: the container refuses to start with a missing or
  short password, a port collision, an address without a scheme, or an attempt to move the
  application off loopback.

## First run

1. Deploy the template. Railway generates `PAPERLESS_GPT_AUTH_PASSWORD` for you.
2. Open the domain and sign in as `admin` with that password. You will see a page listing what is
   still missing.
3. In your paperless-ngx, go to **Settings → My Profile → API Auth Token** and copy the token.
4. Set these two variables on the service and redeploy:

| Variable | Example |
|---|---|
| `PAPERLESS_BASE_URL` | `https://paperless.example.com` |
| `PAPERLESS_API_TOKEN` | the token from step 3 |

5. Set a model provider, if you have not already: `LLM_PROVIDER`, `LLM_MODEL` and the matching key.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `PAPERLESS_GPT_AUTH_PASSWORD` | none, required | Basic-auth password. At least 12 characters. |
| `PAPERLESS_GPT_AUTH_USERNAME` | `admin` | Basic-auth user. |
| `PAPERLESS_GPT_ALLOW_PUBLIC` | `false` | `true` disables authentication entirely. Read `SECURITY.md` first. |
| `PAPERLESS_BASE_URL` | placeholder | Your paperless-ngx. Until this is real, the setup page is served instead of the app. |
| `PAPERLESS_API_TOKEN` | empty | A token from that instance. |
| `PAPERLESS_GPT_MAX_UPLOAD_MB` | `64` | Largest accepted request body. |
| `LISTEN_INTERFACE` | `127.0.0.1:8090` | Where the application listens. Loopback only; the wrapper refuses anything else. |
| `PORT` | `8080` | Public port. Railway sets this and probes its healthcheck against it. |

Every upstream setting is passed through untouched: `LLM_PROVIDER`, `LLM_MODEL`, `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`, `GOOGLEAI_API_KEY`, the Azure Document Intelligence family, `AUTO_TAG`,
`AUTO_OCR_TAG`, `CREATE_LOCAL_PDF` and the rest. See upstream's documentation.

## Persistent paths

| Path | Holds |
|---|---|
| `/app/db` | paperless-gpt's own small database of jobs and settings. |

Your documents stay in paperless-ngx. This service holds no copy of them.

## Local development

```bash
docker compose build
tests/static.sh
tests/smoke.sh
tests/persistence.sh
```

The local stack runs a small stand-in for paperless-ngx so the tests can exercise the routes without
pulling the real thing. `tests/railway-smoke.sh https://your-domain` checks a deployed instance; set
`CREDS_FILE` to a file holding `username:password` to exercise the authenticated paths too.

## Documentation

| File | Covers |
|---|---|
| `ARCHITECTURE.md` | Service graph, the front door, the unconfigured state, ports, health. |
| `SECURITY.md` | What is exposed, what it can reach, and how to opt out safely. |
| `UPSTREAM.md` | Provenance, what the wrapper changes, how to bump the version. |
| `MAINTENANCE.md` | Release process, what to watch, rollback. |
| `THIRD_PARTY_NOTICES.md` | Licences shipped in the image. |
| `MARKETPLACE_AUDIT.md` | Why this template exists. |
| `RAILWAY_TEMPLATE.md` | The exact published template configuration. |

## Licence

The wrapper is MIT. paperless-gpt is MIT and Caddy is Apache-2.0; both licences travel inside the
image at `/usr/share/licenses/paperless-gpt-railway/`.

[upstream]: https://github.com/icereed/paperless-gpt
[ngx]: https://github.com/paperless-ngx/paperless-ngx
