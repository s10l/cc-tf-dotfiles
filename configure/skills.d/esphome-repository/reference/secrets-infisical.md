# Secrets and Infisical

The repository never contains a secret value. It contains two things:

1. **`secret_refs.yaml`** - one line per `!secret` name, mapping it to the
   *location* of the value. Safe to commit.
2. **`esphome/secrets.yaml`** - dummy placeholders so the config loads
   locally. Committed on purpose, excluded from every bundle.

The real values live in the secret manager (Infisical) and are revealed only
server-side by the esphome-builder, which resolves the reference URIs in
`secret_refs.yaml`.

## Reference URI

```yaml
secret_name: infisical://<project-id>/<env>/devices/<device-name>/secret_name
wifi_ssid: infisical://<project-id>/<env>/devices/<device-name>/wifi_ssid
```

The key is the `!secret` name used by the config; the last URI segment must be
that same name.

- One flat `name: reference` per line; the reference must not contain spaces.
- Empty values are allowed while the entry does not exist yet; they are
  skipped and the builder fails with a missing-ref error.
- `make configure` appends every newly discovered `!secret` name with an empty
  value; it never overwrites an existing line.

## Bootstrapping from a hand-filled file (human-only)

`make prepare-secrets <device>` is the one target that reads real values. It is
for a human, not for an agent: an AI agent/LLM must not run it, must not ask
for it to be run to "check" something, and must never read `secrets.tmp.json`.

The human workflow:

1. fill `esphome/secrets.yaml` with real values (the target aborts while the
   file still holds placeholders only, and on any empty value);
2. run `make prepare-secrets <device>`, which writes
   `secrets.tmp.json` - pretty printed as
   `{ "device-name": { "secret_name": "secret_value" } }`, keys unchanged and
   without a device/config prefix because the device node scopes them - then
   regenerates `secret_refs.yaml` with
   `infisical://<project>/<env>/<path>/<device-name>/secret_name` and rewrites
   `esphome/secrets.yaml` with dummies;
3. import `secrets.tmp.json` into Infisical (project/env/folder as printed),
   then delete it - it is gitignored, but it is the only place the values
   exist before the import.

Coordinates come from `makefile.conf` (`INFISICAL_PROJECT`,
`INFISICAL_ENV` default `dev`, `INFISICAL_SECRET_PATH` default `devices`) and
are seeded there on first use. `INFISICAL_PROJECT` is the project UUID or slug;
it is intentionally empty in the template.

Guards: the target refuses to overwrite an existing `secrets.tmp.json` (import
and delete first), and refuses to rewrite `secret_refs.yaml` if it already
holds non-empty references outside this device's path, because a flat map
cannot point one name at two devices.

## Creating the values

Create the matching entries in Infisical yourself (UI or admin tooling) under
the project/environment/path used in the reference. Agent rules:

- **Do not read, print, fetch or echo a secret value** - not to verify it, not
  to compare it with the placeholder, not to debug.
- **Do not run `make prepare-secrets` and do not read `secrets.tmp.json`.**
  Both belong to the human operator. If a value is needed, name the missing
  reference and stop.
- Do not pass a value through a shell command, a commit, a log or an MCP
  argument. The builder accepts reference URIs, not values (`--secret
  KEY=REF`, MCP `secrets_refs`).
- If a value is missing, say which name/path is missing and let the user fix
  it. A 404 from the secret manager usually means project, environment, path
  or name mismatch - name those dimensions, not the value.

## Dummy file conventions

Keep `esphome/secrets.yaml` schema-valid or local loading breaks for the next
person:

| Kind | Convention | Why |
|---|---|---|
| ordinary values | start with `test` (`testssid`, `testpassword`) | obviously fake |
| wifi `domain` | `.local` | must start with a dot |
| WPA passwords | `test...` >= 8 chars | WPA minimum |
| `api_encryption_key` | base64 of exactly 32 bytes, readable ASCII, **not** all-zeros | ESPHome rejects all-zeros; readable bytes prove it is a dummy |

A good dummy key decodes to text such as `ESPHOME-DUMMY-KEY-...`:

```sh
printf %s '<base64 value>' | base64 -d    # must print readable DUMMY text
```

A real key is random bytes and never reads as English. Do not treat the
committed placeholders as leaked, do not rotate them, and do not compare them
against Infisical.

## The guard

`check-secrets.sh` fails on any value that does not match the conventions
above. It runs:

- as an order-only prerequisite of the Makefile bundle rule, so a real value
  can never be packed or built;
- as the first step of every CI `.builder` job.

Run it directly after editing the placeholder file or adding a secret name:

```sh
./check-secrets.sh esphome/secrets.yaml
```

If it reports an offender, either the value is real (move it to the secret
manager, put only the reference in `secret_refs.yaml`) or a new secret lacks a
placeholder (add `test...`).

## Wiring secrets into a builder call

Makefile / CI:

```sh
./esphome.sh validate --bundle build/<device>.esphomebundle.tar.gz \
  --secret wifi_ssid=infisical://... \
  --secret api_encryption_key=infisical://...
```

MCP (`validate`, `compile`, `install`, `screenshot`):

```json
{
  "files": { "...": "..." },
  "entrypoint": "device-name.yaml",
  "secrets_refs": {
    "secret_name": "infisical://<project-id>/<env>/devices/<device-name>/secret_name"
  }
}
```

Every `!secret` used by the submitted config must appear in the map, or the
builder rejects the job with "config uses !secret tag(s) that have no
secrets_refs entry". The fix is always to add the reference, never to inline a
value.

## Bundle exclusion

`secrets.yaml` is excluded from every bundle (Makefile and CI). That is why a
committed placeholder file is harmless: CI never transmits it, and the builder
resolves the references itself.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `no secrets_refs entry` for a name | config uses a `!secret` absent from `secret_refs.yaml` | add the reference URI |
| `check-secrets.sh` offenders | real value or wrong placeholder shape | replace with `test...`/dummy key |
| Builder resolves an empty value | reference points at a missing secret | create it in the manager; check project/env/path/name |
| Local `esphome config` fails on a secret | placeholder missing from `secrets.yaml` | add a schema-valid dummy |
