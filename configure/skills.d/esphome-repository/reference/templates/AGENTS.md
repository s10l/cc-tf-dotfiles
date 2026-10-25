# AGENTS.md - ESPHome @@PROJECT@@

Operational rules for AI agents (and humans) working in this repository.
Read this before touching firmware configs or git branches.

## What this repo is

ESPHome configs for @@BOARD@@. Devices:

- `esphome/@@DEVICE@@.yaml` - device entry point
- `esphome/@@DEVICE@@.package.yaml` - that device's shared composition
- `esphome/screenshot.yaml` - UI preview config (screenshots only, optional)

All firmware operations (validate, compile, install, screenshot) run
**remotely** on the secure-esphome-builder service via `./esphome.sh`, the
committed CLI wrapper of that instance. There is no local or docker build.

## Hard rules - branch policy

1. **NEVER push directly to a `release-*` branch.** These branches exist only
   to receive **merge requests**. The pipeline installs firmware onto live
   devices the moment a change lands on them.
2. Changes reach a release branch **only** via a merge request that a
   maintainer approves and merges. Direct pushes are blocked by GitLab branch
   protection - do not try to work around it (no force-push, no protection
   edits, no "quick" commit straight onto the release branch).
3. **Every merge request must contain:**
   - a description of what changed and why (not just file names),
   - a screenshot when the change affects a display (`make screenshot` ->
     `build/screenshot.png`), attached to the MR description,
   - a green pipeline.
   Use the MR template at `.gitlab/merge_request_templates/Default.md`.
4. Development happens on `main` (or feature branches merged into it). Pushes
   to `main` are validated by CI but **never** installed.
5. Tags and manual release hacks: none. The branches above are the release
   mechanism.

If you are an agent and are asked to "deploy the device" or "push to
release": create the change on `main` (via MR), then open a merge request
`main` -> `release-<device>`. You do not merge or push it yourself.

## Pipeline

| Job | Trigger | Endpoint called |
|---|---|---|
| `validate` | push to `main` | `validate` (matrix over all devices) |
| `build` | MR into `main` | `compile` (matrix over all devices) |
| `build-<device>` | MR into `release-<device>` | `compile` (that device only) |
| `install-<device>` | merge into `release-<device>` | `install` |
| `ha-isolation` | push to `main`, MR pipelines | - (HA package lint, optional) |

Key properties:

- CI uses **no make and no python** - only `./esphome.sh`, `tar`, `gzip`,
  `awk` and `curl` on the runner image.
- **A release MR only builds its own device.** `main` -> `release-<device>`
  compiles that device and nothing else; MRs into `main` compile all devices.
- Every call sends a **bundle**: the device's config tree packed as
  `<device>.esphomebundle.tar.gz` (that device's entry YAML at the archive
  root; the other devices' entry YAMLs and `secrets.yaml` excluded).
- MR pipelines must be green before you merge. The build jobs only run when
  the MR touches firmware inputs; a docs/HA-only MR is green without a
  compile.

### Bundle filename contract (device safety)

The builder picks the config to compile **from the bundle filename**: the
contract is `<device>.esphomebundle.tar.gz` must contain `<device>.yaml` at
the archive root. `esphome/common/ota.yaml` declares no host, so the compiled
config's `esphome name:` decides which device is OTA-addressed. Nothing else
separates the devices - the full chain is:

```
CFG -> bundle filename -> entry YAML at archive root -> esphome name -> OTA target
```

- A release install sends **`<device>.esphomebundle.tar.gz`** derived from
  the job's `CFG`. A generic or shared bundle name must never appear in a
  builder call.
- The pipeline prints the bundle filename where it is created and where it is
  used (`creating <device>.esphomebundle.tar.gz...`,
  `installing <device>.esphomebundle.tar.gz...`), so the device an install
  job flashed is readable straight from the job log.
- Enforced in `.gitlab-ci.yml` (`.builder` pack step) and the `Makefile`
  bundle rule - a broken chain fails **before** the builder call, never at a
  device: per-device bundle contents; an assertion that the entry YAML's
  `esphome name:` equals `CFG`; an assertion in `install-*` that it runs on
  its own release branch.
- A cross-device flash can only come from a broken filename chain, never from
  name drift: a repo once committed `esphome/device-a.yaml` with
  `esphome name: "device-b"` - the bundle filenames were correct, the name
  was not, and firmware reached the wrong box.

## Commit types and the compile bypass (`chore`)

The builder jobs are the slow part, and they only look at `esphome/`. A
change that cannot affect firmware must not burn a compile.

- **`chore` never touches `esphome/`.** A commit subject starting with
  `chore` (or `chore(scope):`, `chore!:`) declares "firmware-neutral". On an
  MR-into-`main` pipeline or a `main` push with that subject, `validate` and
  `build*` are **not created**; `ha-isolation` still runs.
- The builder also skips when the diff changes none of the firmware inputs:
  `esphome/**`, `esphome.sh`, `secret_refs.yaml`, `check-secrets.sh`. That is
  what keeps docs-only merges fast on `main` even when the merge commit is
  titled `Merge branch 'x' into 'main'` (the `chore` marker only survives on
  `main` with squash merges).
- **`chore-guard`** fails the pipeline (`.pre` stage) if a `chore`-titled
  push to `main` or MR into `main` *does* change `esphome/`. A firmware
  change can never pass uncompiled: either the guard is red, or the path rule
  runs the build.
- **Release MRs ignore the `chore` marker.** Their diff is everything merged
  since the last release, so the head commit subject says nothing about
  firmware content. Such an MR pre-compiles **only its own device** when its
  diff against the release branch touches firmware inputs, and the merge
  always runs `install-*` - a release is never silently un-installed.
- Use `chore` for docs, `homeassistant/`, tooling, CI and skill files.
  Anything under `esphome/` is `feat`/`fix`/`refactor`, never `chore`.
- Check before committing: `git diff --name-only origin/main...HEAD -- esphome`
  must print nothing for a `chore` commit.

## Secrets

- **`make prepare-secrets <device>` is HUMAN-ONLY.** It is the one target that
  reads real values: it exports a hand-filled `esphome/secrets.yaml` to
  `secrets.tmp.json` (gitignored, but it holds the values until they are
  imported), rewrites `secret_refs.yaml` with the matching Infisical paths, and
  replaces the values in `secrets.yaml` with dummies. An AI agent/LLM **must
  never run it and must never read `secrets.tmp.json`**. Agents work from
  `secret_refs.yaml` (references only). If a task seems to need a real value,
  stop and ask the user to run the target themselves.
- `secret_refs.yaml` maps every `!secret` name to a **reference URI**
  (e.g. `infisical://<project>/<env>/<path>`) where the value is stored. It
  holds locations, never values, and is safe to commit. The builder resolves
  references server-side.
- `esphome/secrets.yaml` **is committed on purpose and contains dummy
  placeholders only.** It exists so the configs load on a local checkout
  (`esphome config`, `config-hash`, editor tooling). Real secret values live
  only in the secret manager and are revealed **only** by the remote
  esphome-builder. The file is excluded from every bundle, so CI never
  transmits it and a leaked placeholder unlocks nothing.
- A committed placeholder is provable: every value starts with `test`, and
  `api_encryption_key` is deliberately self-describing - decode it with
  `printf %s <value> | base64 -d` and it spells DUMMY. A real key is random
  bytes and would never read as English. Do not treat that file as leaked, do
  not rotate it, and do not compare it against the secret manager.
- Never put a real value in `esphome/secrets.yaml`, and never move a secret
  out of the manager into a config file. Keep the placeholders schema-valid
  (WPA passwords >= 8 chars, `domain` starting with `.`, encryption key =
  base64 of exactly 32 bytes and **not** all-zeros) or local validation
  breaks for the next person.
- If `validate` fails with *"config uses !secret tag(s) that have no
  secrets_refs entry"*, add the reference URIs to `secret_refs.yaml` - not
  values to the config.
- OTA does not use a password: uploads are encrypted with the API key. See
  `esphome/common/ota.yaml`.

## Deliberate choices - do not "fix" these

- **The `web_server` OTA platform stays, and its warning stays with it.**
  Building with `ota.encryption` produces
  `WARNING OTA encryption does not cover the web_server OTA platform; its
  plaintext /update endpoint accepts the same image`. That is accepted on
  purpose: the browser path (`http://<device>/update`) is the recovery route
  when the encrypted path is unusable (bad Wi-Fi settings, a broken api
  config, or a firmware that no longer joins the network). Do not delete
  `- platform: web_server`, and do not add `web_server: ota: false`, just to
  silence a pipeline warning. A non-clean build log is not a defect here.
- A real warning is still a real warning: compare against the known-good
  baseline instead of aiming blindly for zero warnings.
- **Build artifact cache opt-in:** `ESPHOME_ACCEPT_REMOTE_DRIFT=1` lets the
  builder reuse a compiled artifact for identical inputs. CI enables it;
  release installs may legitimately flash an MR-built image (identified by
  `cache: hit` in the install log). The cache key does **not** cover content
  ESPHome fetches from remote sources (`external_components` / remote
  packages) - treat a hit as speedup only, not a guarantee.

## Local commands

```sh
make validate <device>   # remote validation
make build <device>      # remote compile, firmware to build/
make screenshot          # remote render, build/screenshot.png (LVGL only)
make install <device>    # compile + OTA - touches LIVE devices, interactive use only
make homeassistant       # interactive copy-in of HA packages + one wiring
./check-package-isolation.sh   # HA package isolation lint (optional)
```

`make prepare-secrets <device>` is **human-only** and deliberately not in this
list: it reads real values from a hand-filled `secrets.yaml`. Never run it from
an agent, and never read `secrets.tmp.json`.

`make install` is the only hand-run path that can flash devices; CI is the
intended install path via release branches. `make homeassistant` stages the
`homeassistant/` deliverables on the live HA host (`HA_TARGET` in
`makefile.conf`) but does **not** validate or reload - those are
WebSocket-side steps run through the Home Assistant MCP/agent or the UI.
`./esphome.sh help` documents the raw CLI.

## GitLab setup (repo admin)

- Protect `release-*`: **Allowed to merge:** Maintainers; **Allowed to push
  and force push:** No one.
- Runners must reach `esphome-builder.lab.stefanbickel.com` (the URL
  `esphome.sh` is paired to). If the builder ever requires auth, add a masked
  CI variable `ESPHOME_TOKEN`; the script picks it up automatically.
