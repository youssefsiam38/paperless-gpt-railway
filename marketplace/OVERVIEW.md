# Deploy and Host paperless-gpt on Railway

paperless-gpt reads the documents in a paperless-ngx archive you already run and fills in what is
missing: a real title instead of a scanner filename, the correspondent, the document type, tags, and
better OCR for scans that plain text extraction could not handle. It sends pages to a language model
you choose and writes the results back. This is a community-maintained template; it is not
affiliated with the paperless-gpt project.

## About Hosting paperless-gpt

It is small to host: a Go binary serving its own web interface, one modest database of jobs and
settings, no companion services. Your documents stay where they are, in paperless-ngx; this service
fetches them per request.

The part that needs care is authentication, because paperless-gpt has none. It defines around thirty
API routes and not one of them checks a credential, since the project is designed to sit on a
private network beside the archive it talks to. On a platform that gives every service a public
address, that assumption stops being true the moment the deploy finishes, and what is behind those
routes is not a blank application: it is read and write access to contracts, invoices and
correspondence, plus the ability to spend the model key you configured.

This template puts a password in front of the application and binds the application itself to
loopback. The password is generated for you. One route stays open, a health route that belongs to
the template rather than the application, so the platform can watch the service without a route
existing that reaches your documents.

## Why Deploy paperless-gpt on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying paperless-gpt on Railway, you are one step closer to supporting a complete full-stack
application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

Concretely, this template generates the password, configures the front door, separates the public
port from the application's own, attaches the small volume it needs, and points the healthcheck at
the one route that stays open. It also makes the first deploy succeed before you have configured
anything: until you supply your archive's address and token, the site serves a short page, behind
the password, telling you exactly which two values to fill in.

## Common Use Cases

- Give scanned documents real titles instead of `scan_0043.pdf`.
- Fill in correspondents, document types and tags across an archive nobody has had time to sort.
- Re-read scans whose OCR came out unusable, with a model that can look at the page.
- Keep the archive itself where it is, and add the tidying as a separate service you can turn off.

## Dependencies for paperless-gpt Hosting

- A running paperless-ngx, and an API token from it. The token comes from Settings, My Profile, API
  Auth Token.
- An API key for a language-model provider: OpenAI, Anthropic, Google, Ollama or Azure Document
  Intelligence.
- A small persistent volume for the job database.
- Nothing else. No external database, cache or queue.

### Deployment Dependencies

- paperless-gpt upstream project: https://github.com/icereed/paperless-gpt
- paperless-ngx, the archive it connects to: https://github.com/paperless-ngx/paperless-ngx
- Caddy, used as the authenticating front door: https://caddyserver.com
- Template repository, wrapper image and tests: https://github.com/youssefsiam38/paperless-gpt-railway
- Published image: `ghcr.io/youssefsiam38/paperless-gpt-railway`
- paperless-gpt is MIT licensed and Caddy is Apache-2.0; both are permissive.

### Implementation Details

The wrapper adds no application code. It validates the configuration and refuses to start on a
missing or short password, a port that collides with the application's own, an archive address with
no scheme, or an attempt to move the application off loopback. It hashes the password into a proxy
configuration it validates before use. When the archive details are still unset it serves the setup
page and does not start the application at all; otherwise it opens the public port and runs the
application behind it through upstream's own entrypoint, which drops privileges. Both processes are
supervised, so if either stops the container stops and the platform restarts it.
