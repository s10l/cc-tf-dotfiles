# @@PROJECT@@

ESPHome firmware for @@BOARD@@.

All firmware work (validate, compile, install, screenshot) runs **remotely**
on the secure-esphome-builder service via the committed `esphome.sh` CLI.
There is no local ESPHome installation, no Docker build and no Python
involved.

## Installation

Requirements: `make`, a POSIX shell, `curl`, `tar`, `gzip` and `awk`. Nothing
else - the build itself happens on the remote builder.

```sh
git clone https://gitlab.stefanbickel.com/<group>/@@PROJECT@@.git
cd @@PROJECT@@
make configure
```

`make configure` seeds two files, idempotently (existing lines are never
overwritten):

- `makefile.conf` - global settings (`USE_BUNDLE`, `SCREENSHOT_DELAY`,
  `ACCEPT_REMOTE_DRIFT`, `HA_TARGET`, `INFISICAL_*`).
- `secret_refs.yaml` - one entry per `!secret` used by the configs, e.g.
  `wifi_ssid: infisical://<project>/<env>/<path>`.

Fill in the empty references in `secret_refs.yaml` with the URI where the
value is stored, and create the values in the secret manager. **Never commit
secret values** - that file holds references only. `esphome/secrets.yaml`
**is** committed, but it contains dummy placeholders only (every value starts
with `test`; the encryption key decodes to readable DUMMY text). It exists so
the configs load on a local checkout. The real values live in the secret
manager and are revealed only by the remote builder, which resolves the
references server-side. `secrets.yaml` is excluded from every bundle, so CI
never transmits it. `make check-secrets` enforces this convention.

A human can bootstrap the references from a hand-filled `esphome/secrets.yaml`
instead of typing them:

```sh
make prepare-secrets <device>   # HUMAN-ONLY - never run from an AI agent
```

It writes `secrets.tmp.json` for an Infisical import - real values, gitignored,
delete it after importing - regenerates `secret_refs.yaml`, and replaces the
values in `esphome/secrets.yaml` with dummies. An agent must never run this
target or read `secrets.tmp.json`; it works from `secret_refs.yaml` only.

```sh
# validate a device config against the remote builder
make validate @@DEVICE@@

# compile firmware -> build/firmware_@@DEVICE@@.bin
make build @@DEVICE@@

# render the UI -> build/screenshot.png (only with a display/LVGL)
make screenshot
```

`ACCEPT_REMOTE_DRIFT=0 make build @@DEVICE@@` forces a fresh compile (ignores
the build artifact cache); `ACCEPT_REMOTE_DRIFT=1` (default) allows reuse.

`./esphome.sh` is downloaded automatically on first use; the committed copy is
already paired with the builder. See `./esphome.sh help`.

## Devices

| Config | Entry point | Purpose |
|---|---|---|
| @@DEVICE@@ | `esphome/@@DEVICE@@.yaml` | primary device |

## Make targets

```sh
make validate <device>   # validate the configuration
make build <device>      # compile remotely, firmware lands in build/
make install <device>    # compile + OTA upload to the live device
make screenshot          # render the UI to build/screenshot.png (LVGL only)
make check-secrets       # assert secrets.yaml holds dummies only
make clean               # remove build artifacts
```

`make prepare-secrets <device>` is human-only (see above) and therefore not in
the list agents should run.

`make install` is the only hand-run path that flashes a device - CI is the
intended install path. In a single-device repo the device argument may be
omitted.

## Repository layout

```
esphome/
  @@DEVICE@@.yaml            device entry point
  @@DEVICE@@.package.yaml    shared composition for that device
  common/                    board, ota, webserver, debug, substitutions
  screenshot.yaml            UI preview config (screenshots only, optional)
homeassistant/               HA-side packages + wiring (optional)
secret_refs.yaml             !secret name -> storage reference URI
Makefile, makefile.conf      local workflow
esphome.sh                   remote builder CLI (committed on purpose)
check-secrets.sh             secrets placeholder guard
check-package-isolation.sh   HA package isolation guard (optional)
```

## Release

Development happens on `main`. A release is a merge request from `main` into
`release-@@DEVICE@@`; merging it runs the OTA install. Never push directly to
a release branch. See `AGENTS.md` and
`.gitlab/merge_request_templates/Default.md`.
