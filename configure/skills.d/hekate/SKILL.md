---
name: hekate
description: Reference for configuring Docker container labels so apps are discovered by hekate — the homelab launchpad. Covers all labels, defaults, URL derivation from Traefik, and ACL behavior. Use when adding labels to a compose file or docker run command.
---

## What I do

1. Determine which labels the user needs for the target container:
   - **Must-have**: `hekate.enabled=true` without this the container is invisible.
   - **Optional**: `hekate.label`, `hekate.icon`, `hekate.tooltip`, `hekate.url`, `hekate.acl`, `hekate.state` — all zero-required.

2. Write labels in the form the user is using:
   - **Compose file** (`docker-compose.yml` / `compose.yaml`):
     ```yaml
     services:
       myapp:
         image: nginx
         labels:
           - hekate.enabled=true
           - hekate.label=My App
           - hekate.icon=logos:nginx
     ```
   - **docker run / docker create**:
     ```
     docker run -d --label hekate.enabled=true --label hekate.label="My App" nginx
     ```

3. If the container is behind Traefik (the normal path), explain how the URL is derived:
   - `hekate.url` label takes highest precedence — set it to skip Traefik parsing.
   - Otherwise hekate reads the Traefik router rule: `Host(\`example.com\`)` → `https://example.com`.
   - Scheme comes from `traefik.http.routers.X.tls=true` → `https`, or from the `entrypoints` field matching `--https-entrypoints`.
   - `PathPrefix(\`/auth\`)` is appended; bare `Path(\`/foo\`)` is ignored.
   - If no URL can be derived, the app appears with status `offline` (dimmed, non-clickable).

4. Explain ACL behavior when `hekate.acl` is set:
   - No ACL → visible to every authenticated user.
   - `hekate.acl=admin_group,sre` → only users in at least one of those groups see the app.
   - `*` matches everyone (same as no ACL, but explicit).
   - The admin group (default `admins`) bypasses all ACL — they see everything.

5. Explain `hekate.state`:
   - `show` → default; app renders normally with a status dot.
   - `hide` → app is hidden from the UI (bypassed by admin group).
   - Also mention the central `hekate.yaml` `state.show_offline` and `state.show_status` for global toggles.

## When to use me

Use this whenever you are about to add hekate labels to a Docker container — in a compose file, `docker run` command, or a Kubernetes-like manifest. Reach for it before writing any `hekate.` label to avoid guessing defaults or breaking URL derivation.

## Rules

- **`hekate.enabled` is the only required label.** Without it the container is invisible, regardless of every other label. Never suggest removing it unless the user explicitly asks to hide the app.
- **`hekate.url` overrides Traefik parsing.** Setting it is the recommended way to pin a specific URL. Warn the user that if they set it, Traefik router rules for that container are ignored by hekate.
- **URL derivation depends on Traefik.** Do not guess what URL hekate will derive — ask the user for the Traefik router rule, or tell them to check `traefik.http.routers.<name>.rule`. The only safe assumption is `Host(\`<something>\`)`.
- **ACL is per-group, not per-role.** `hekate.acl=users` matches any user in the `users` group. It is not a deny-list. Empty ACL means visible to all authenticated users.
- **Sort order is alphabetical, case-insensitive, with ID as tiebreak.** There is no `hekate.order` label — the user cannot control render order. Equal labels are stable because the container ID is the tiebreak.
- **Icons use the Iconify name format** (e.g. `logos:plex`, `mdi:home`). The default is a colored monogram derived from the label's first letter. Do not suggest arbitrary icon formats — only Iconify `collection:name`.
- **Never suggest `hekate.enabled=false` as a way to configure an app.** That label only gates discovery; it does not toggle visibility of an existing entry. Use `hekate.state=hide` instead.
- **Labels are case-sensitive.** All hekate labels must start with exactly `hekate.` — `Hekate.enabled` or `HEKATE.enabled` will not work.

## Output format notes

### Compose label syntax

Compose files support key-value pairs (`key=value`) or bare keys in the `labels:` list. hekate reads **both forms**, so:

```yaml
labels:
  - hekate.enabled=true
  - hekate.label=My App
```

is equivalent to:

```yaml
labels:
  hekate.enabled: "true"
  hekate.label: "My App"
```

### Label quick reference

| Label | Required | Default if omitted | Example |
|---|---|---|---|
| `hekate.enabled` | yes | — | `true` |
| `hekate.label` | no | Image short name (no registry/owner/tag) | `plex` |
| `hekate.icon` | no | Colored monogram of the label | `logos:plex` |
| `hekate.tooltip` | no | — | `Media server` |
| `hekate.url` | no | Derived from Traefik rules (or `offline`) | `https://plex.example.com` |
| `hekate.acl` | no | Visible to all authenticated users | `admins,ops` |
| `hekate.state` | no | `show` | `hide` |

### URL derivation precedence

1. `hekate.url` label — exact override
2. Traefik `Host(...)` / `HostRegexp(...)` rule — parsed
3. **No URL → `offline` status**

### URL derivation examples

- `Host(\`grafana.example.com\`)` → `https://grafana.example.com` (TLS on → https)
- `Host(\`*.example.com\`) && PathPrefix(\`/app\`)` → `https://<subdomain>.example.com/app`
- `HostRegexp(\`{subdomain:[a-z]+}.example.com\`)` → **not derivable** (general regex, not literal or `*.suffix`) — app will be `offline` unless `hekate.url` is set.
