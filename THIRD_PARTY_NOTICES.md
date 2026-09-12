# Third-party notices

This image redistributes software written by other people. Their licences are shipped inside it at
`/usr/share/licenses/paperless-gpt-railway/` and vendored in `licenses/` here.

## Shipped inside the wrapper image

| Component | Licence | Source | Notice |
|---|---|---|---|
| paperless-gpt 0.27.0 | MIT | https://github.com/icereed/paperless-gpt | `licenses/PAPERLESS-GPT-LICENSE` |
| Caddy 2.10.2 | Apache-2.0 | https://github.com/caddyserver/caddy | `licenses/CADDY-LICENSE` |

The upstream image itself contains further components, among them Gin (MIT), langchaingo (MIT),
GORM (MIT), React (MIT), Alpine Linux's base packages, and `su-exec` (Apache-2.0). Their notices
travel in the layers upstream publishes; this wrapper does not repackage or relink any of them. The
wrapper adds `bash` (GPL-3.0-or-later) from Alpine's package index, unmodified and unlinked to
anything.

paperless-ngx is a separate service you run yourself; nothing from it is redistributed here.

## Licence obligations

Both vendored licences are permissive and require only that the notice accompanies the software.
Copying them into the image satisfies that for anyone who pulls the image without reading this
repository.

## Trademarks and artwork

"paperless-ngx" and "paperless-gpt" belong to their respective projects, neither of which is
affiliated with or endorses this template. The template icon in `assets/` was made for this
repository and is not an upstream logo.

## This repository

The wrapper, its entrypoint, its tests and its documentation are MIT licensed. See `LICENSE`.
