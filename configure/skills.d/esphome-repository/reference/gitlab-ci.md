# GitLab CI

The pipeline calls the same `./esphome.sh` as the Makefile. It deliberately
does **not** use make: `esphome.sh` needs POSIX sh + curl, bundle packing needs
tar/gzip, the secret-refs pass needs awk. The runner image provides all of
them.

## Jobs

| Job | Trigger | Endpoint |
|---|---|---|
| `chore-guard` | `.pre`, only when a `chore` title meets an `esphome/` change | - |
| `validate` | push to `main` | `validate`, `parallel: matrix` over `DEVICES` |
| `build` | MR into `main` | `compile`, `parallel: matrix` over `DEVICES` |
| `build-<device>` | MR into `release-<device>` | `compile`, that device only |
| `install-<device>` | merge into `release-<device>` | `install` |
| `ha-isolation` | push to `main`, MR pipelines | - (OPTIONAL) |

## Why matrix + per-device jobs

`parallel: matrix` is used where every entry has the **same** target: validate
on `main`, compile on MRs into `main`. A release MR only builds the one
device its branch will flash, and GitLab `rules` cannot test a matrix
variable, so release builds and installs are separate per-device jobs. Add
one block per device, keeping the three names in sync:

```
build-<device>      CFG: <device>             branch release-<device>
install-<device>    CFG: <device>             EXPECTED_BRANCH release-<device>
```

This keeps a `release-remote` MR from waiting on a `release-control` compile,
and makes the install job's target visible in its name.

## Rules and the chore bypass

- `workflow.rules` keeps MR pipelines, `main` pushes and `release-*` pushes.
- `.firmware_paths` (`esphome/**/*`, `esphome.sh`, `secret_refs.yaml`,
  `check-secrets.sh`) gates the builder jobs: a docs/HA/CI-only change is
  green with no compile.
- A commit subject matching `^chore(\([^)]*\))?!?:` declares the change
  firmware-neutral and skips validate/build. `chore-guard` fails the pipeline
  if such a pipeline still changes `esphome/` - a firmware change must never
  pass uncompiled.
- **Release MRs ignore the chore marker**: their diff is everything since the
  last release, so the head subject is accidental. Only the path rule
  decides. `install-*` is never skipped - a merge into a release branch *is*
  the release.
- On MR pipelines `$CI_COMMIT_TITLE` is the **head commit's** subject, not the
  MR title. A mixed MR (chore + firmware) must keep the `feat`/`fix` commit
  at branch HEAD or the guard trips.

## Shared `.builder` base

`resource_group: esphome-builder` serializes jobs: parallel matrix jobs racing
on the same cold ESP-IDF framework download fail with partial-file size
mismatches. The `before_script`:

1. runs `./check-secrets.sh "$ESPHOME_DIR/secrets.yaml"`,
2. builds `SECRET_ARGS` from `secret_refs.yaml` with the same awk expression
   as the Makefile,
3. makes `esphome.sh` executable,
4. packs `$CFG.esphomebundle.tar.gz` and asserts the filename chain.

Every step prints the bundle filename, so an install job's log records which
device was flashed. `artifacts` keep `build/` for one week (firmware and
bundles).

## Required variables

```yaml
variables:
  ESPHOME_DIR: esphome
  BUILD_DIR: build
  SECRET_REFS_FILE: secret_refs.yaml
  ESPHOME_SH: ./esphome.sh
  ESPHOME_ACCEPT_REMOTE_DRIFT: "1"
```

`ESPHOME_ACCEPT_REMOTE_DRIFT=1` lets a release install reuse the artifact an
MR built. The cache key covers the submitted config tree, entrypoint,
resolved secret values and builder version - **not** `external_components` or
remote packages. A hit is a speedup, not a guarantee. An install log without
a `cache:` line means the flag did not arrive.

If the builder ever requires auth, add a masked CI variable `ESPHOME_TOKEN`;
`esphome.sh` sends it as a bearer token automatically.

## Bundle filename contract

The builder resolves the config **from the bundle filename**:
`<device>.esphomebundle.tar.gz` must contain `<device>.yaml` at its root, and
the compiled config's `esphome name:` is the OTA target (no host is declared
in `common/ota.yaml`). A generic or shared bundle name in a builder call is a
bug, not a shortcut.

## Failure modes

- **Builder job missing on a pipeline that changes `esphome/`**: head commit
  starts with `chore` - amend/push a `feat`/`fix` subject.
- **`chore-guard` red**: the pipeline changes `esphome/`. Rename the commit;
  never force a skip.
- **Wrong device flashed**: walk the chain - which bundle the install job
  created/sent, and whether the entry YAML's `esphome name:` equals `CFG`.
  Do not suspect DNS; device names resolve via records the pipeline cannot
  modify. Recover with the `web_server` `POST /update` rescue path, then
  re-install from the correct release branch.
- **Jobs queued forever**: another pipeline holds `resource_group:
  esphome-builder`; that is intentional serialization.
