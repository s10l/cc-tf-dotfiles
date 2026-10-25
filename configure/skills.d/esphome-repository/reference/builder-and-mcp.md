# Builder: MCP first, CLI for the repo

Two paths reach the same secure-esphome-builder service:

- **MCP tools** (`esphome-builder`) for interactive, ad-hoc work: validate a
  config tree, start a compile, poll it, pull the firmware or screenshot.
- **`./esphome.sh`** for anything the repo records or automates: Makefile,
  CI, release logs. The committed script is pre-paired with
  `https://esphome-builder.lab.stefanbickel.com`.

Use MCP first when working interactively; fall back to the CLI when the MCP
server is unavailable or when reproducing exactly what CI does.

## MCP tools

| Tool | Purpose |
|---|---|
| `get_client_script` | Download URL / install command / cheatsheet for `esphome.sh`. Use it to fetch the committed CLI. |
| `validate` | `esphome config` without a build. Takes `config` or `files` + `entrypoint`, plus `secrets_refs`. |
| `compile` | Async compile; returns a `cmp_...` token. Optional `accept_remote_drift`, `platform`. |
| `install` | Async compile + OTA upload; returns a token. **Touches a live device.** |
| `upload` | Async OTA upload without compiling (existing artifact). **Touches a live device.** |
| `screenshot` | Render a host/LVGL config, return the PNG inline or a `scr_...` token. |
| `get_status` | Status of a job by token; `wait_seconds` long-polls instead of busy-looping. |
| `get_firmware` | Firmware URL for a successful compile/install (`variant`: `ota`, `factory`, `all`). |
| `get_screenshot` | PNG for a successful screenshot job. |
| `get_log` | Job log; `tail` for the end. |

### Multi-file configs

Never paste a whole tree as one string when it uses `!include`/packages.
Submit a **files set** and an explicit entrypoint:

```json
{
  "files": {
    "<device>.yaml": "...",
    "<device>.package.yaml": "...",
    "common/ota.yaml": "...",
    "common/webserver.yaml": "...",
    "common/hardware.yaml": "...",
    "common/debug.yaml": "...",
    "common/substitutions.yaml": "..."
  },
  "entrypoint": "<device>.yaml",
  "secrets_refs": {
    "wifi_ssid": "infisical://...",
    "wifi_password": "infisical://...",
    "domain": "infisical://...",
    "api_encryption_key": "infisical://...",
    "wifi_ap_password": "infisical://..."
  }
}
```

The file set is the bundle equivalent: paths are relative to the same root
that `<device>.yaml` sits at, and the entrypoint must be at that root.

### Compile / install flow

1. `compile` (or `install`) with the file set and refs -> token.
2. `get_status` with `wait_seconds` (do not poll tighter than ~5 s). A cold
   ESP-IDF build can take minutes.
3. On success: `get_firmware` (token) for the image, or `get_screenshot`
   (token) for a render. On failure: `get_log` with `tail`.

`get_status` on success names the result tool in its `artifact` field.

### Screenshot flow

`screenshot` with `files` + `entrypoint`, optional `page`, `delay_seconds`.
It blocks up to `wait_seconds`; on timeout you get a token - call
`get_status` with `wait_seconds`, then `get_screenshot`. Read the actual PNG
result rather than describing what it should show.

### CLI equivalent

| Goal | CLI |
|---|---|
| validate | `./esphome.sh validate --bundle build/<device>.esphomebundle.tar.gz --secret k=ref...` |
| compile | `./esphome.sh compile ... -o build/firmware_<device>.bin` |
| install | `./esphome.sh install ...` |
| screenshot | `./esphome.sh screenshot ... --page <page> --delay <s> -o build/screenshot.png` |
| job status | `./esphome.sh status <token>` |
| job log | `./esphome.sh log <token> --tail 100` |
| firmware | `./esphome.sh firmware <token> -o fw.bin` |
| server | `./esphome.sh url`, `./esphome.sh version` |
| refresh CLI | `./esphome.sh self-update` |

The CLI accepts the same `--secret KEY=REF` pairs (repeatable) or
`--secrets-json`, and the same bundle contract.

## Bundle contract (shared by both paths)

`<device>.esphomebundle.tar.gz` must contain `<device>.yaml` at its root. The
builder derives the config from the filename; `esphome name:` in that YAML is
the OTA target. A bundle containing another device's entry YAML, or a filename
that does not match its entry, can flash the wrong device.

## Auth and transport

- The builder is open on the LAN; `ESPHOME_TOKEN` (masked CI variable) is sent
  automatically as `Authorization: Bearer` if the instance ever requires it.
- `--accept-remote-drift` / `ESPHOME_ACCEPT_REMOTE_DRIFT=1` enables the build
  artifact cache. Its key does **not** cover `external_components`/remote
  packages; treat a hit as a speedup, not a guarantee.
- `--url`, `--insecure`, `--header`, retry/timeout flags exist for unusual
  networks; defaults are fine on the LAN.

## Fetching the CLI into a new repo

Use `get_client_script` (preferred) or download the paired script:

```sh
curl -fsSL https://esphome-builder.lab.stefanbickel.com/esphome.sh -o esphome.sh
chmod +x esphome.sh
./esphome.sh version
```

Commit the result: CI calls `./esphome.sh` directly and must not depend on a
runtime download. `./esphome.sh self-update` refreshes it when the builder
moves.
