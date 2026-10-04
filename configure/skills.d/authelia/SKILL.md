---
name: authelia
description: Reference for using Authelia as a forward-auth middleware with Traefik — adding `authelia@docker` to routers, understanding the forward-auth flow, and debugging auth issues. Use when writing Traefik router middlewares or debugging why a route redirects to the login page.
---

## What I do

1. Determine whether the user is **adding authelia protection to a Traefik router** or **troubleshooting an existing authelia-protected route**.

2. If adding authelia protection to a Traefik router (in a compose file or dynamic config):
   - Add `- authelia@docker` to the router's `middlewares` list, or
   - Add the label `traefik.http.routers.<name>.middlewares=authelia@docker` in a compose file
   - Only add it to the **HTTPS** router — never to the HTTP-to-HTTPS redirect router
   - Ensure the HTTPS router has `entryPoints: https` and `tls: true` set; authelia protection belongs on the secure entry point

3. Auto-discover or obtain the Authelia URL — the base URL for login redirects — before explaining any forward-auth behavior:
   - If the user already provided it, use it directly.
   - Otherwise, try to discover it by reading the authelia container's Traefik router rule:
     ```
     docker inspect --format='{{range $k, $v := .Config.Labels}}{{index $v}}{{"\n"}}{{end}}' authelia 2>/dev/null | grep -oP 'Host\(`[^`]+`' | head -1 | sed 's/Host(`//;s/`//'
     ```
     The output is the hostname; the full URL is `https://<hostname>` — the router always uses TLS.
   - If discovery fails (container not found, no Traefik labels, or no output), ask the user: "What is the Authelia base URL? It is set in the Traefik router rule: `traefik.http.routers.<name>.rule = Host(\`...\`)."

4. Explain the forward-auth flow:
   - Traefik intercepts incoming requests and forwards them to `http://authelia:9091/api/authz/forward-auth?authelia_url=<URL-encoded auth URL>`
   - If authenticated: authelia returns 200 and adds identity headers (`Remote-User`, `Remote-Groups`, `Remote-Name`, `Remote-Email`) to the request
   - If not authenticated: authelia returns 302 redirect to the login page at the discovered Authelia URL

5. If the user reports that a protected route is not working (e.g., redirect loop, unexpected login page, or blank response):
   - Verify the router has `authelia@docker` in its middlewares
   - Check that the HTTPS router has `entryPoints: https` and `tls: true`
   - Ensure the HTTP redirect router does **not** also have `authelia@docker` — that causes redirect loops
   - Confirm the `authelia_url` query parameter in the forward-auth address matches the discovered URL (scheme, host, trailing slash)
   - Check authelia logs for error messages

## When to use me

Use this whenever you are writing or modifying Traefik router configurations that need authentication, protecting a new route with authelia, or debugging why a route is redirecting to the login page. Reach for it before writing any `authelia@docker` middleware reference or before troubleshooting an auth redirect.

## Rules

- **`authelia@docker` is the middleware name.** It comes from the Docker provider (labels on the authelia container). Do not suggest `authelia@file` — the running setup uses the Docker provider.
- **Never add `authelia@docker` to an HTTP redirect router.** Only add it to the HTTPS router. If both the HTTP redirect router and the HTTPS router have authelia, the HTTP request will redirect to the login page instead of to HTTPS — a redirect loop.
- **The `authelia_url` must be correct.** It is set in the forward-auth middleware's `address` label as a query parameter and must match the authelia container's Traefik router host. A mismatch causes the login redirect to point to the wrong domain.
- **Authelia is on the `traefik` Docker network.** The forward-auth address is always `http://authelia:9091`. This is the Docker internal address; never use `localhost` or any external hostname for it.
- **The response headers are a contract.** `Remote-User, Remote-Groups, Remote-Name, Remote-Email` are added to every authenticated request. Do not remove or rename any of them — downstream services depend on them.
- **Never expose other services' configuration or details.** Only discuss Authelia and the Traefik integration points that directly involve Authelia. Do not mention other containers, their labels, or their configurations.

## Output format notes

### Middleware reference in YAML

```yaml
# Docker provider (compose file labels)
labels:
  - traefik.http.routers.<name>.middlewares=authelia@docker

# Traefik dynamic YAML config
http:
  routers:
    myapp:
      middlewares:
        - authelia@docker
```

### Discovering the Authelia URL

If the user did not provide the Authelia URL, attempt to discover it from the running container's Traefik labels:

```
docker inspect --format='{{range $k, $v := .Config.Labels}}{{index $v}}{{"\n"}}{{end}}' authelia 2>/dev/null | grep -oP 'Host\(`[^`]+`' | head -1 | sed 's/Host(`//;s/`//'
```

- Output is the hostname (e.g. `auth.example.org`).
- The full URL is `https://<hostname>` — the router always uses TLS and the `https` entry point.
- If the command produces no output, ask the user for the URL.

### Forward-auth headers passed downstream

| Header | Meaning |
|---|---|
| `Remote-User` | Authenticated username |
| `Remote-Groups` | Comma-separated group names |
| `Remote-Name` | Display name |
| `Remote-Email` | Email address |

These are added by authelia to the proxied request when the forward-auth check passes (HTTP 200). The Traefik middleware preserves them automatically via the `authResponseHeaders` setting.

### Troubleshooting: redirect loop

Symptoms: page keeps reloading, or the browser shows "too many redirects."

Likely causes:

1. **Authelia attached to the HTTP redirect router.** The HTTP router sends the user to the login page instead of to HTTPS. Remove `authelia@docker` from the redirect router — it only belongs on the HTTPS router.
2. **`authelia_url` query parameter mismatch.** The URL in the forward-auth middleware's address does not match the authelia container's own host. Check:
   ```
   docker inspect --format='{{index .Config.Labels "traefik.http.routers.authelia.rule"}}' authelia
   ```
   The scheme and host in the query parameter must match exactly.
3. **Missing `tls: true` on the HTTPS router.** Authelia issues a redirect to `https://...` but the router accepts only HTTP, so the request never reaches the backend.

### authelia@docker vs authelia@file

- `authelia@docker` — middleware defined by labels on the authelia container (used in the running setup)
- `authelia@file` — middleware defined in a static Traefik config file (not used in this setup)

If you encounter `authelia@file` in a config, it belongs to a different environment.
