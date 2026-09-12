# Marketplace audit

Checked 2026-09-12 against Railway's template search.

## Gap

`templateSearch` returns no template named after paperless-gpt. What exists nearby is the archive
itself and some of the pieces it could use:

| Existing template | What it is | Why it does not cover this |
|---|---|---|
| paperless-ngx | The document archive | The thing this connects to, not a replacement for it. |
| paperless-AI | A different project with a similar aim | A separate application; this template is for paperless-gpt. |
| Docling, MinerU, Marker, MarkItDown | Document conversion APIs | They turn a file into text. They do not decide what a document is called or who it is from. |
| Stirling-PDF | PDF manipulation | Different job entirely. |

The gap is the companion: something that sits next to an archive somebody already runs and fills in
the metadata they never got round to.

## Why paperless-gpt

- MIT licensed, so redistributing a wrapper image is unencumbered.
- 2,681 stars and a push the day before this audit.
- A Go binary with an embedded web build and a small local database: one container, one small volume,
  no companion services.
- Its value is highest exactly where a template helps, on a hosted archive that somebody set up once
  and has not tidied since.
- It supports several model providers, so a deployer is not locked to one.

## Why it needs a template rather than a raw image

Deploying `ghcr.io/icereed/paperless-gpt` directly to Railway produces a service with no
authentication whatsoever, holding a token that can read and rewrite an entire document archive.
That is not a misconfiguration on the deployer's part; there is nothing to switch on. Upstream's
documentation puts it on a private network beside paperless-ngx, which a public platform does not
have.

The template also settles three things that are easy to get wrong:

1. **The port.** The upstream image listens on `:8080`, which is also what Railway probes. With a
   proxy in front the two collide unless something separates them.
2. **The healthcheck.** There is no health endpoint at all. Every route the application has is one
   the platform must not be able to reach without a credential, so the wrapper supplies its own.
3. **The first deploy.** The two variables that make the service useful describe an instance only
   the deployer knows about, and there is no sensible default for either. Rather than deploy into a
   crash loop, this template serves a page, behind the password, naming what is missing.

## Category

AI/ML. Railway added that category after the earlier templates in this family were published, and it
is the right home for a service whose whole job is running documents past a language model.
