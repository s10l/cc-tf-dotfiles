---
name: hekate
description: Reference for configuring Docker container labels so apps are discovered by hekate — the homelab launchpad. Covers all labels, defaults, URL derivation from Traefik, ACL behavior, and multiple expose points per container (`hekate.expose.<key>.*`). Use when adding labels to a compose file or docker run command.
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
   - Router selection: an exact `Host(...)` beats a wildcard; among the same type, the lowest router name wins.
   - The scheme is always `https` — hekate assumes TLS everywhere, whatever `tls`/`entrypoints` labels the router carries, and never generates a plain `http` link.
   - `PathPrefix(\`/auth\`)` is appended; bare `Path(\`/foo\`)` is ignored.
   - If no URL can be derived, the app appears with status `offline` (dimmed, non-clickable).

4. If the container serves more than one entry point — an admin console, a
   public view, a metrics endpoint — declare each extra one in the
   `hekate.expose.<key>.<field>` namespace, one tile per key:
   - Fields: `label` (default: the key), `url`, `router`, `icon`, `tooltip`,
     `acl`, `state`.
   - The flat `hekate.*` labels still describe the default entry point and are
     unchanged; exposes are added alongside it.
   - URL precedence per expose: `.url` → `.router` (derived from
     `traefik.http.routers.<name>.rule`) → the container's best Traefik router →
     offline.
   - `hekate.expose.auto=true` seeds one expose per Traefik router on the
     container, keyed by router name; explicit `hekate.expose.<router>.*` labels
     overlay the seed.

5. Explain ACL behavior when `hekate.acl` is set:
   - No ACL → visible to every authenticated user.
   - `hekate.acl=ops,sre` → only users in at least one of those groups see the app.
   - `*` matches everyone (same as no ACL, but explicit).
   - The admin group (default `admins`) bypasses all ACL — they see everything.

6. Explain `hekate.state`:
   - `show` → default; app renders normally (online when a URL is derivable,
     offline otherwise).
   - `hide` → app is hidden from the UI (bypassed by admin group).
   - `hide_offline` / `offline` → forced into the offline status: dimmed and
     non-clickable when `state.show_status` is on, dropped from the grid when
     `state.show_offline` is off.
   - Also mention the central `hekate.yaml` `state.show_offline` and `state.show_status` for global toggles.

## When to use me

Use this whenever you are about to add hekate labels to a Docker container — in a compose file, `docker run` command, or a Kubernetes-like manifest. Reach for it before writing any `hekate.` label to avoid guessing defaults or breaking URL derivation.

## Rules

- **`hekate.enabled` is the only required label.** Without it the container is invisible, regardless of every other label. Never suggest removing it unless the user explicitly asks to hide the app.
- **`hekate.enabled` gates exposes too.** No `hekate.expose.*` label is read unless the container also sets `hekate.enabled=true`; without it neither the default tile nor any expose is discovered.
- **Exposes do not inherit the base labels.** An expose's `acl`, `icon`, `tooltip` and `state` come only from its own `hekate.expose.<key>.*` labels — a missing `.acl` is visible to *all* authenticated users even when `hekate.acl` is restricted, and a missing `.label` falls back to the key, not the base label. Set every field you want on each expose explicitly.
- **Expose keys are lowercased, then validated** against `^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$`; `auto` is reserved and cannot name an expose. A malformed key, a bare `hekate.expose` label, or an unknown field is skipped with a warning — it never disables the container's other tiles.
- **Each expose is an independent tile.** Its ID is `<container id>#<key>`, it is ACL-filtered per user exactly like any other app, and it is added, removed and goes offline independently of the default entry point and its siblings.
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

### Expose label quick reference

For a multi-entry-point container, each `hekate.expose.<key>` becomes its own
tile. `hekate.enabled=true` and the flat labels are still required for the
container to be discovered at all.

| Label | Required | Default if omitted | Example |
|---|---|---|---|
| `hekate.expose.<key>.label` | no | The key (`admin` → `admin`) | `Grafana Admin` |
| `hekate.expose.<key>.url` | no | Derived (see precedence) or `offline` | `https://grafana-admin.example.com` |
| `hekate.expose.<key>.router` | no | Container's best Traefik router | `grafana-admin` |
| `hekate.expose.<key>.icon` | no | Colored monogram of the label | `mdi:shield-account` |
| `hekate.expose.<key>.tooltip` | no | — | `Admin-only console` |
| `hekate.expose.<key>.acl` | no | Visible to all authenticated users (no inheritance) | `admins` |
| `hekate.expose.<key>.state` | no | `show` | `hide` |
| `hekate.expose.auto` | no | — | `true` (seed one expose per router) |

### Expose URL derivation precedence

1. `hekate.expose.<key>.url` — exact override
2. `hekate.expose.<key>.router` — parsed from `traefik.http.routers.<name>.rule`
3. The container's best Traefik router (same derivation as the default entry point)
4. **No URL → `offline` status**

Example:

```yaml
labels:
  - hekate.enabled=true
  - hekate.label=Grafana
  - hekate.icon=logos:grafana
  - hekate.url=https://grafana.example.com
  - hekate.expose.admin.label=Grafana Admin
  - hekate.expose.admin.icon=mdi:shield-account
  - hekate.expose.admin.acl=admins
  - hekate.expose.admin.router=grafana-admin
  - traefik.http.routers.grafana-admin.rule=Host(`grafana-admin.example.com`)
```

### URL derivation precedence

1. `hekate.url` label — exact override
2. Traefik `Host(...)` / `HostRegexp(...)` rule — parsed
3. **No URL → `offline` status**

### URL derivation examples

- `Host(\`grafana.example.com\`)` → `https://grafana.example.com` (scheme always `https`)
- `Host(\`*.example.com\`) && PathPrefix(\`/app\`)` → `https://<subdomain>.example.com/app`
- `HostRegexp(\`{subdomain:[a-z]+}.example.com\`)` → **not derivable** (general regex, not literal or `*.suffix`) — app will be `offline` unless `hekate.url` is set.
