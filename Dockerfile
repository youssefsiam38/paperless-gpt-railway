# syntax=docker/dockerfile:1
#
# paperless-gpt-railway: thin wrapper around the official paperless-gpt image.
#
# paperless-gpt has no authentication. `main.go` registers about thirty routes under /api and not
# one of them checks a credential, because the project expects to sit on a private network beside
# the paperless-ngx it talks to. Those routes read your documents, rewrite their titles and tags,
# and send page images to whichever language model you configured -- on your API key.
#
# Railway gives every service a public URL, so deployed as-is it is an open door into an archive
# that usually holds contracts, invoices and correspondence. This wrapper puts Caddy in front with
# HTTP basic authentication and binds the application to loopback. Application code is unchanged.
#
# Both images are pinned by tag AND digest. Update the image and version args together.
ARG CADDY_IMAGE=docker.io/library/caddy:2.10-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d
ARG PAPERLESS_GPT_IMAGE=ghcr.io/icereed/paperless-gpt:v0.27.0@sha256:855d9df5bacb2bed60bd520f1ffe0d118695aef9f77d37466ae85823001f547d

FROM ${CADDY_IMAGE} AS caddy

FROM ${PAPERLESS_GPT_IMAGE}

ARG PAPERLESS_GPT_VERSION=0.27.0
ARG CADDY_VERSION=2.10.2
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

USER root

# Caddy ships as a static Go binary, so the alpine-built one runs on this base unchanged.
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY licenses/ /usr/share/licenses/paperless-gpt-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/paperless-gpt-railway-entrypoint
# The upstream image is Alpine and ships no bash. The entrypoint needs one for `wait -n`, which
# BusyBox ash does not implement reliably, so it is installed rather than the script rewritten.
RUN apk add --no-cache bash \
    && caddy version \
    && install -d /etc/paperless-gpt-railway

# The application listens on loopback only; Caddy owns the public port.
ENV LISTEN_INTERFACE=127.0.0.1:8090 \
    PAPERLESS_GPT_AUTH_USERNAME=admin

LABEL org.opencontainers.image.title="paperless-gpt-railway" \
      org.opencontainers.image.description="Community Railway wrapper for paperless-gpt, which adds LLM OCR and tagging to paperless-ngx. Adds the authentication upstream has none of. Not affiliated with the paperless-gpt project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/paperless-gpt-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/paperless-gpt-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/paperless-gpt-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="ghcr.io/icereed/paperless-gpt:v${PAPERLESS_GPT_VERSION}" \
      io.paperless-gpt-railway.upstream.version="${PAPERLESS_GPT_VERSION}" \
      io.paperless-gpt-railway.caddy.version="${CADDY_VERSION}"

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/paperless-gpt-railway-entrypoint"]
