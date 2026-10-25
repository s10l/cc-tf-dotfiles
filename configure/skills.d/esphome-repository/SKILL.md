---
name: esphome-repository
description: Blueprint for creating or restructuring an ESPHome device repository - single- or multi-device layout, DEVICES-driven Makefile, remote esphome-builder workflow via MCP or esphome.sh, GitLab matrix pipeline with per-device release branches, Infisical secret references, and optional Home Assistant packages or LVGL screenshots. Use when starting a new ESPHome device repo, adding a device to an existing one, or aligning a repo with this blueprint.
---

# ESPHome repository blueprint

This skill scaffolds the repository shape used for ESPHome devices: firmware
under `esphome/`, Home Assistant deliverables under `homeassistant/`, a
Makefile whose targets are generated from a device list, a GitLab pipeline
that validates/builds a matrix of devices and installs only from
`release-<device>` branches, and secrets that exist only as references to
Infisical.

Everything is in `reference/`; copy-ready files are in
`reference/templates/` with `@@TOKEN@@` markers described in
`reference/placeholders.md`. All firmware operations go to the secure
esphome-builder at `https://esphome-builder.lab.stefanbickel.com` - there is
no local ESPHome, no Docker build and no Python.

## What I do

1. **Inventory before writing.** Ask for, do not guess:
   - device count and slugs (each slug is a file stem, `esphome: name:` and
     CI `CFG`),
   - board/hardware description,
   - whether the firmware has a display/LVGL (screenshot support),
   - whether there is a Home Assistant side (`homeassistant/`),
   - the target directory and whether it is a new or existing repo.

   Stop here if the target exists and is not empty: read `git status`, show
   what would change, and wait for approval.

2. **Copy and render the templates.**

   ```sh
   SKILL_DIR="${HOME}/.config/opencode/skills/esphome-repository"
   target=/absolute/path/to/new-repo
   mkdir -p "$target"
   cp -R "${SKILL_DIR}/reference/templates/." "$target/"
   cd "$target"
   sed -i \
     -e 's|@@PROJECT@@|<project>|g' \
     -e 's|@@DEVICE@@|<device>|g' \
     -e 's|@@DEVICES@@|<device-a> <device-b>|g' \
     -e 's|@@DEVICES_CSV@@|<device-a>, <device-b>|g' \
     -e 's|@@BOARD@@|<board description>|g' \
     -e 's|@@PKG@@|<pkg>|g' \
     -e 's|@@DUMMY_API_KEY@@|RVNQSE9NRS1EVU1NWS1LRVktMDAwMDAwMDAwMDAwMDA=|g' \
     -e 's|@@SCREENSHOT_PAGE@@|main_page|g' \
     -e 's|@@SCREENSHOT_BOOST_PAGE@@||g' \
     -e 's|@@HA_TARGET@@|<user>@<ha-host>:/config|g' \
     $(grep -rl '@@' .)
   ```

   Rename the generic files (`reference/placeholders.md` has the full table):

   ```sh
   mv esphome/device.yaml "esphome/<device>.yaml"
   mv esphome/device.package.yaml "esphome/<device>.package.yaml"
   mv esphome/screenshot.yaml "esphome/<project>-screenshot.yaml"
   mv homeassistant/packages.d/pkg.yaml "homeassistant/packages.d/<pkg>.yaml"
   mv homeassistant/packages.d/pkg.d "homeassistant/packages.d/<pkg>.d"
   mv homeassistant/wiring.d/wiring.pkg.live.yaml "homeassistant/wiring.d/wiring.<pkg>.live.yaml"
   mv homeassistant/wiring.d/wiring.pkg.bench.yaml "homeassistant/wiring.d/wiring.<pkg>.bench.yaml"
   ```

3. **Enforce the naming chain.** For every device:
   `entry stem == esphome: name: == bundle stem == Makefile/CI CFG`. The name
   is the OTA target because `common/ota.yaml` declares no host.

   ```sh
   grep -nE '^[[:space:]]*name:' "esphome/<device>.yaml"
   make -n build "<device>"        # bundle filename must match
   ```

4. **Adapt the Makefile.** `DEVICES` is a space-separated list; the
   per-device targets expand from it. Keep `help`, `configure`, `validate`,
   `build`, `install`, `check-secrets`, `clean` and the human-only
   `prepare-secrets` (do not run it); keep `screenshot`,
   `screenshot-boost` and `homeassistant` only for the features that exist.
   See `reference/makefile.md`.

   ```sh
   grep -n '^DEVICES' Makefile
   make help
   ```

5. **Wire secrets through Infisical.** Never create, read, print or commit a
   value.

   ```sh
   make configure                    # seeds makefile.conf + secret_refs.yaml
   ./check-secrets.sh esphome/secrets.yaml
   ```

   Fill each empty reference in `secret_refs.yaml` with an
   `infisical://<project>/<env>/<path>` URI and ask the user to create the
   values in Infisical. Real values are resolved server-side by the builder;
   `esphome/secrets.yaml` keeps dummy placeholders. See
   `reference/secrets-infisical.md`.

   The template also ships `make prepare-secrets <device>`, which a **human**
   can use to bootstrap `secret_refs.yaml` from a hand-filled `secrets.yaml`
   (it writes `secrets.tmp.json` for an Infisical import, then restores
   dummies). **An agent must never run it and never read `secrets.tmp.json`**;
   the target is flagged as human-only in the Makefile, `AGENTS.md` and
   `reference/makefile.md`.

6. **Fetch the builder CLI** (committed, pre-paired):

   ```sh
   ./esphome.sh version || {
     curl -fsSL https://esphome-builder.lab.stefanbickel.com/esphome.sh -o esphome.sh
     chmod +x esphome.sh
     ./esphome.sh version
   }
   ```

   `get_client_script` from the esphome-builder MCP returns the same download
   URL and install command.

7. **Adapt CI.** Add every device to both matrices (`DEVICES_CSV`), duplicate
   the `build-<device>` / `install-<device>` blocks with matching
   `release-<device>` branches, and keep the `chore-guard` and path filters.
   Release MRs build only their own device. See `reference/gitlab-ci.md`.

   ```sh
   grep -nE 'CFG:|release-|EXPECTED_BRANCH' .gitlab-ci.yml
   ```

8. **Optional Home Assistant side.** Keep `homeassistant/packages.d/<pkg>.d`
   port-isolated (no foreign entity ids), one wiring variant enabled at a
   time, and the isolation lint wired into CI. See
   `reference/homeassistant.md`.

9. **Verify before handing over.**

   ```sh
   grep -rn '@@' .                                  # must print nothing
   ./check-secrets.sh esphome/secrets.yaml          # must pass
   sh -n check-secrets.sh prepare-secrets.sh check-package-isolation.sh deploy-ha.sh
   make -n build "<device>"
   make "build/<device>.esphomebundle.tar.gz"
   tar -tzf "build/<device>.esphomebundle.tar.gz"
   ```

   The archive contains `<device>.yaml` at its root, no sibling entry YAMLs,
   no `secrets.yaml`. Then validate remotely - MCP first:

   - `validate` with a `files` set, `entrypoint`, and `secrets_refs`, or
     `./esphome.sh validate --bundle ... --secret k=ref`.
   - `compile` (or `./esphome.sh build`) and poll `get_status` with
     `wait_seconds`; fetch with `get_firmware`.
   - `screenshot` only when the repo has a display; read the returned PNG.

   `reference/builder-and-mcp.md` lists every tool and its CLI equivalent.

10. **Git and release.** Create the repo/MR only when asked. The release is a
    merge request `main -> release-<device>` with a description and, for UI
    changes, `build/screenshot.png` attached. You do not merge it and you do
    not push to a release branch.

## When to use me

Use this when the user wants to:

- start a new ESPHome device repository,
- add a second device to an existing ESPHome repo or split one out,
- align an existing ESPHome repo with this layout (Makefile, GitLab pipeline,
  secrets references, HA packages),
- or decide where a piece of an ESPHome/HA setup belongs.

## Rules

- **No secret value may be written, read, printed or committed.** Reference
  URIs only in `secret_refs.yaml`; dummy placeholders only in
  `esphome/secrets.yaml`; values live in Infisical. If a value is needed to
  finish, ask the user - never fetch it to "check".
- **Never run `make prepare-secrets` and never read `secrets.tmp.json`.** The
  target is human-only: it reads a hand-filled `secrets.yaml`, exports the
  values to the gitignored import file and restores dummies. Agents work from
  references; if a task appears to need the values, stop and hand it back.
- **Do not modify a non-empty target without approval.** Show the planned
  files, then wait.
- **Remote actions wait for an explicit ask**: `git push`, MR creation,
  merging, `install`/`upload` (OTA), and anything that touches a live HA
  instance. Local scaffolding is the task; deployment is not implied by it.
- **Never push to or merge `release-*`.** Changes reach it only through a
  maintainer-merged MR. No force-push, no protection edits, no "quick"
  commit.
- **Remove optional parts instead of leaving dead config.** No display means
  no `screenshot.yaml`, no `screenshot*` targets, no `SCREENSHOT_*` vars. No
  HA means no `homeassistant/`, no `deploy-ha.sh`, no `ha-isolation` job.
- **Keep the bundle chain intact.** `<device>.esphomebundle.tar.gz` must
  contain `<device>.yaml` at its root, whose `esphome name:` equals the
  filename stem. Never use a generic/shared bundle name.
- **Keep the `web_server` OTA platform and its warning.** The plaintext
  `/update` endpoint is the recovery path; do not silence the warning by
  deleting the platform.
- **Personal data stays out of the scaffolded repo.** Allowed infrastructure
  literals are `gitlab.stefanbickel.com`,
  `esphome-builder.lab.stefanbickel.com` and the pinned runner image. No
  names, emails, IPs, secret-manager project UUIDs, device serials or real
  entity ids in anything you write. The operator's own Infisical coordinates
  are theirs to fill in (`makefile.conf`) or to generate with the human-only
  `make prepare-secrets`; never invent or copy a real project UUID into a
  template.
- **Firmware changes are never `chore`.** `chore-guard` fails a pipeline that
  declares firmware-neutral but changes `esphome/`.

## Output format notes

Checking the render:

- `make help` must list the real devices and `USE_BUNDLE`, and must not print
  `@@` tokens.
- `make -n build <device>` prints a command containing
  `--bundle build/<device>.esphomebundle.tar.gz` when `USE_BUNDLE=1`.
- `tar -tzf build/<device>.esphomebundle.tar.gz` lists `<device>.yaml` and
  `<device>.package.yaml` at the root; sibling `<other>.yaml` and
  `secrets.yaml` must be absent.
- `./check-secrets.sh` prints `... holds placeholder values only` on success;
  on failure it lists the offending key names and exits 1.

CI/CLI bundle lines (the device an install touched is readable from them):

```
creating <device>.esphomebundle.tar.gz...
<device>.esphomebundle.tar.gz created
installing <device>.esphomebundle.tar.gz...
```

MCP jobs:

- `compile`/`install`/`screenshot` return a job token (`cmp_...` / `scr_...`).
  Poll with `get_status` and `wait_seconds`; do not poll tighter than ~5 s.
- On success the status names the result tool in its `artifact` field:
  `get_firmware` for compile/install, `get_screenshot` for a render.
- Failures: `get_log` with `tail`; the failing command and `ERROR:` are near
  the end.

Final scans:

```sh
grep -rn '@@' .                       # empty
grep -rniE 'password|token|secret' .  # only placeholder/reference text
```

Any literal-looking credential, IP, UUID or personal name is a defect - stop
and fix it before handing over.

## Reference files

| File | Content |
|---|---|
| `reference/repo-layout.md` | Single- vs multi-device tree and what belongs where |
| `reference/makefile.md` | Targets, `DEVICES`, bundle rule, optional sections |
| `reference/gitlab-ci.md` | Matrix jobs, release branches, chore bypass, failure modes |
| `reference/secrets-infisical.md` | Reference URIs, dummy conventions, builder resolution |
| `reference/esphome-config.md` | Entry/package composition, OTA, web_server, screenshot, remote_base |
| `reference/homeassistant.md` | Ports, isolation rules, wiring, deployment |
| `reference/builder-and-mcp.md` | MCP tools vs `esphome.sh`, file sets, job flow |
| `reference/release-checklist.md` | Commit types, MR content, install-log checks, recovery |
| `reference/placeholders.md` | Token table, rendering, optional removals, verification |
| `reference/templates/` | Copy-ready repo files |
