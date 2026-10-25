# ESPHome configuration

The config tree is split so that one device is one entry file plus a package
file, and everything shared lives under `common/`.

## Entry point

`esphome/<device>.yaml` carries only what is device-specific:

```yaml
esphome:
  name: "<device>"
  friendly_name: "<device>"
  comment: "<board description>"

api:
  encryption:
    key: !secret api_encryption_key

wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
  domain: !secret domain
  ap:
    password: !secret wifi_ap_password

captive_portal:
logger:
  level: DEBUG

packages:
  host: !include <device>.package.yaml
```

- `esphome: name:` **must equal the file stem**. That name is the OTA target
  (no host is declared in `common/ota.yaml`).
- Never put a literal secret in the entry; use `!secret`.
- Do not add an `ota:` block here - it lives in `common/ota.yaml`.

## Package composition

`esphome/<device>.package.yaml` pulls the shared files:

```yaml
packages:
  substitutions: !include common/substitutions.yaml
  ota: !include common/ota.yaml
  webserver: !include common/webserver.yaml
  hardware: !include common/hardware.yaml
  debug: !include common/debug.yaml
  # screens: !include common/screens.yaml   # OPTIONAL LVGL
  # fonts: !include common/fonts.yaml       # OPTIONAL LVGL
```

Two devices share every file except their entry and package. Device-specific
differences belong in the device package, overlaying a shared block (ESPHome
merges package keys).

## OTA and the web_server warning

`common/ota.yaml` declares OTA **once**:

```yaml
ota:
  - platform: esphome
    encryption:          # inherits api.encryption.key
  - platform: web_server # deliberate recovery path
```

Two `platform: esphome` entries are merged by ESPHome and turn into a hard
error when version/id/key disagree. Building with `ota.encryption` always
produces:

```
WARNING OTA encryption does not cover the web_server OTA platform; its
plaintext /update endpoint accepts the same image
```

That warning is accepted on purpose. The browser path
`http://<device>/update` is the recovery route when the encrypted path is
unusable (bad wifi, broken api/encryption, a firmware that no longer joins the
network). Do not remove the `web_server` platform to silence it.

## Hardware

`common/hardware.yaml` holds the board block (`esp32:`/`esp8266:`/`rp2040:`,
flash/PSRAM, buses, outputs, backlight). Replace the generic skeleton with the
real board config. Keep it separate so a second device can reuse it.

## Substitutions

`common/substitutions.yaml` holds shared `$values` (screen geometry, idle
timeouts). Device-specific values go in the device package. YAML `$name`
substitution is resolved by ESPHome at load time.

## Secrets

`!secret` names must exist in:

- `secret_refs.yaml` (reference URI, for the builder), and
- `esphome/secrets.yaml` (dummy placeholder, for local loading).

See `secrets-infisical.md`. A new `!secret` without a reference fails
validation with a clear error.

## Optional: screenshot config

Only when the firmware has a display/LVGL. `esphome/<project>-screenshot.yaml`
is a **host** config (`host:`, no `esp32:`/`ota:`/`webserver:`) that reuses the
UI packages and declares a `display:`/`lvgl:` tree. Its `esphome: name:` must
match the file stem because the builder resolves it from the bundle filename.

`make screenshot` renders it with `--page <SCREENSHOT_PAGE>`; a second page can
be exposed as `screenshot-boost` with `SCREENSHOT_BOOST_PAGE`. Without a
display, omit the file and leave `SCREENSHOT_CONFIG` empty.

## Bundle mode vs remote_base

With `USE_BUNDLE=1` (default), relative `!include`s work because the whole
tree travels in the archive. With `USE_BUNDLE=0` only the entry file is sent:
relative includes do not resolve remotely, so the entry must fetch its parts
as a git package instead:

```yaml
packages:
  remote_base:
    url: https://gitlab.stefanbickel.com/<group>/<project>
    username: !secret gluser
    password: !secret glpat
    file: <device>.package.yaml
    ref: main
    refresh: always
```

That mode needs `gluser`/`glpat` secret refs; bundle mode is the default and
needs neither.

## Local checks

```sh
./check-secrets.sh esphome/secrets.yaml
make validate <device>        # remote, resolves real values
# or the esphome-builder MCP validate with a files set + secrets_refs
```

Local `esphome config` (if ESPHome is installed) can only use the dummy
values; it is useful for syntax, not for behaviour.
