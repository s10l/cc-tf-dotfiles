# Release checklist

## 1. Commit type

Ask one question: **does the diff touch `esphome/`?**

```sh
git diff --name-only origin/main...HEAD -- esphome   # must print nothing for chore
```

| Diff touches | Commit type | Builder jobs |
|---|---|---|
| `esphome/**` | `feat` / `fix` / `refactor` | run |
| `esphome.sh`, `secret_refs.yaml`, `check-secrets.sh`, `prepare-secrets.sh` | `chore` is fine, but the path rule still runs the builder | run |
| `homeassistant/`, docs, CI, skills, screenshots | `chore` | skipped |

Never label a firmware change `chore`: `chore-guard` runs in `.pre`, sees
`esphome/` in the diff and fails the pipeline. On MR pipelines the marker is
the **head commit** subject, so keep a `feat`/`fix` commit at branch HEAD in a
mixed MR.

## 2. Before opening an MR

- [ ] `make validate <device>` passes (or MCP `validate` with the same files).
- [ ] `make build <device>` passes if the payload changed.
- [ ] `make screenshot` attached when the change affects a display (or "n/a -
      no display" stated).
- [ ] `secret_refs.yaml` covers every new `!secret`.
- [ ] `./check-secrets.sh esphome/secrets.yaml` passes.
- [ ] `secrets.tmp.json` is absent (gitignored, but it holds real values - it
      must be imported and deleted, never committed).
- [ ] No secret value in the diff, logs or MR description.

## 3. MR into `main`

Use `.gitlab/merge_request_templates/Default.md`: what changed and why, the
screenshot, the checklist. The pipeline compiles every device when firmware
inputs changed; a `chore` MR is green with the jobs skipped - say so in the
description so "build green" stays honest.

## 4. Release MR

1. Open `main` -> `release-<device>` (one device per release branch).
2. Attach the screenshot (`make screenshot` -> `build/screenshot.png`).
3. The pipeline pre-compiles **only** that device when the diff against the
   release branch touches firmware inputs. `install-<device>` is never
   skipped.
4. A maintainer merges; the merge pipeline runs `install-<device>` (OTA).
   Agents never push to or merge release branches.

## 5. After the install

Read the `install-<device>` job log:

- `creating <device>.esphomebundle.tar.gz...` and
  `installing <device>.esphomebundle.tar.gz...` - confirm the device is the
  one you intended.
- `cache: hit` means the image came from an earlier compile with identical
  inputs (MR build reused). No `cache:` line means drift-accept did not
  arrive.
- The tail should show the OTA upload succeeding, then the device reconnecting
  to the API.

Verify the device came back: entities update, the web UI at
`http://<device>/` responds, and `api` reconnects.

## 6. Recovery

- **Bad firmware / no network**: use the browser rescue path
  `http://<device>/update` (`platform: web_server` OTA) and upload a known-good
  factory/OTA image. This is why the `web_server` platform and its build
  warning are deliberate.
- **Wrong device flashed**: walk the bundle chain (install log filename ->
  entry YAML `esphome name:` -> `CFG` -> expected branch). DNS is not the
  suspect; device records are static. Rescue the wrong device via
  `/update`, then re-install from the correct release branch.
- **Pipeline red on `chore-guard`**: rename the commit; do not force a skip.
- **Builder queued forever**: `resource_group: esphome-builder` serializes
  jobs by design; wait for the running pipeline.
