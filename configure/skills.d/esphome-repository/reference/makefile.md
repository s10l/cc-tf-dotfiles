# Makefile

The Makefile is a thin driver for `./esphome.sh`. It never compiles locally
and never reads a secret value. Two files control it:

- `makefile.conf` - `USE_BUNDLE`, `SCREENSHOT_DELAY`, `ACCEPT_REMOTE_DRIFT`,
  `HA_TARGET`, `INFISICAL_PROJECT`, `INFISICAL_ENV`,
  `INFISICAL_SECRET_PATH`. Sourced with `-include`; `make configure` seeds it
  once and never overwrites an existing line.
- `secret_refs.yaml` - one `name: reference-uri` line per `!secret`.

## Targets

| Target | Effect |
|---|---|
| `make help` | Print usage, devices and current settings. |
| `make configure` | Seed/update `makefile.conf` and `secret_refs.yaml` idempotently; append every newly discovered `!secret` name with an empty reference. |
| `make validate <device>` | `esphome.sh validate` (bundle or plain YAML). |
| `make build <device>` | `esphome.sh compile` -> `build/firmware_<device>.bin`. It runs validation first, ignoring its failure, so a broken validate never blocks a real compile error message. |
| `make install <device>` | `esphome.sh install` (compile + OTA). **Touches the live device.** |
| `make screenshot` | `esphome.sh screenshot --page <SCREENSHOT_PAGE>` -> `build/screenshot.png`. OPTIONAL. |
| `make screenshot-boost` | Second page -> `build/screenshot-boost.png`. OPTIONAL. |
| `make check-secrets` | Run `check-secrets.sh`; fails on a non-placeholder value. |
| `make prepare-secrets <device>` | **HUMAN-ONLY.** Export a hand-filled `secrets.yaml` to `secrets.tmp.json`, regenerate `secret_refs.yaml`, replace the values with dummies. Never run from an agent. |
| `make clean` | Remove `build/`, `.esphome`, `.pio*`. |
| `make homeassistant` | Run `deploy-ha.sh "$(HA_TARGET)"`. OPTIONAL. |

## Device list

`DEVICES` is a space-separated list. The Makefile expands it into
`validate-<device>`, `build-<device>` and `install-<device>` with static
pattern rules - never hardcode names in a recipe.

```make
DEVICES ?= device-a device-b
```

The alias targets read the device from `MAKECMDGOALS` (the second word of
`make build device-a`). With exactly one device the argument may be omitted:

```sh
make validate            # single-device repo
make validate device-a   # multi-device repo
```

A typo is rejected by a case whitelist; the catch-all `%:` rule exists only
to stop make from treating the device argument as a missing target.

## Bundle mode

`USE_BUNDLE=1` (default) packs one device into
`build/<device>.esphomebundle.tar.gz` and sends it with `--bundle`. Relative
`!include`s, packages, local components and assets resolve inside the
archive. `USE_BUNDLE=0` sends the plain `esphome/<device>.yaml`; that config
must be self-contained or fetch its parts via `remote_base`.

The bundle rule:

1. requires `esphome/<device>.yaml`,
2. asserts it declares `esphome: name: "<device>"`,
3. excludes every other root-level `*.yaml` (sibling devices, the screenshot
   entry) and `secrets.yaml`,
4. asserts `<device>.yaml` is at the archive root,
5. prints `creating <device>.esphomebundle.tar.gz...` and
   `<device>.esphomebundle.tar.gz created`.

`check-secrets` runs as an order-only prerequisite, so a real value can never
be packed. The archive is rebuilt on every invocation (`FORCE`).

## Secrets plumbing

`SECRET_ARGS` turns every non-empty `name: reference` line into
`--secret name=reference` pairs; the builder resolves the reference
server-side. Empty values are skipped, so a repo can be configured before the
secret manager entries exist (validation then fails with a clear missing-ref
error).

### `prepare-secrets` is human-only

`make prepare-secrets <device>` (script: `prepare-secrets.sh`) is the only
target that touches real values. An AI agent/LLM must not run it and must not
read its output file. It is for the human bootstrapping a repo:

1. fill `esphome/secrets.yaml` with the real values (the target refuses a file
   that still holds placeholders only),
2. run the target:
   - `secrets.tmp.json` is written, pretty printed as
     `{ "device-name": { "secret_name": "secret_value" } }` - names unchanged,
     no device/config prefix because the device node already scopes them;
     mode 600 and gitignored, but it holds the values until imported,
   - `secret_refs.yaml` is regenerated as
     `infisical://<project>/<env>/<path>/<device-name>/secret_name` for every key,
   - `esphome/secrets.yaml` is rewritten with dummies and re-checked by
     `check-secrets.sh`,
   - `makefile.conf` is seeded with `INFISICAL_PROJECT`, `INFISICAL_ENV` and
     `INFISICAL_SECRET_PATH` when missing (`PROJECT` stays empty until the
     human fills it in),
3. the human imports `secrets.tmp.json` into Infisical and deletes it.

Coordinates come from `makefile.conf` (or the command line, e.g.
`make prepare-secrets <device> INFISICAL_PROJECT=<project-uuid>`). The target
refuses to overwrite an existing `secrets.tmp.json`, and refuses to rewrite
`secret_refs.yaml` when it holds non-empty references outside this device's
path - a flat map cannot represent two devices' paths.

`SECRETS_SRC` overrides the input when the hand-filled file is a copy
elsewhere; it must live **outside `esphome/`** (every root YAML there except
`secrets.yaml` can be packed into a bundle), and `esphome/secrets.yaml` is
still the file rewritten with dummies. The source is then left untouched and
must be deleted by the human.

## Optional screenshot section

Keep the section only when the firmware has a display/LVGL. Set:

```make
SCREENSHOT_CONFIG        ?= $(ESPHOME_DIR)/<project>-screenshot.yaml
SCREENSHOT_PAGE         ?= main_page
SCREENSHOT_BOOST_PAGE   ?= <second-page-or-empty>
```

`SCREENSHOT_CONFIG` empty disables the targets with a clear message. The
screenshot entry's `esphome: name:` must match its file stem because the
builder resolves the config from the bundle filename.

## Verification

```sh
make -n build <device>          # show the remote command without running it
make help                       # devices + settings are what you expect
make check-secrets              # must pass on the dummy file
make build/<device>.esphomebundle.tar.gz   # inspect the archive
tar -tzf build/<device>.esphomebundle.tar.gz
```

The archive must contain `<device>.yaml` at its root and no `secrets.yaml` or
sibling entry YAML.
