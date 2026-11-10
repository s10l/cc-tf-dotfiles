---
name: renovate
description: Renovate policy and GitLab CI integration for the lab - central runner config, per-repo renovate.json packageRules, CalVer (date-tag) image automerge, the renovate-config-check and docker-deploy-renovate jobs, MR flow and troubleshooting. Consulted whenever GitLab pipelines or Renovate are involved.
---

# Renovate

Renovate keeps every repository on `gitlab.stefanbickel.com` current: a central
runner runs hourly, autodiscovers all repos, and opens `chore(deps):` merge
requests from `renovate/*` branches. It automerges exactly the update classes
this document allows — nothing else. `glph` audits pipeline structure and asks
the per-image automerge question; this skill is the policy and mechanics
reference behind those answers.

## What I do

1. Determine which config governs the repo. Look for a repo-level
   `renovate.json` (also check `.renovaterc.json`, `.gitlab/renovate.json`).
   No file means only the central config applies — say so, and note that
   adding one *replaces* the effective packageRules for that repo (see Rules).
2. Before changing anything, restate the effective automerge policy to the
   user: central rules (below) first, repo rules after, later rules win.
   Show the repo's own `renovate.json` alongside.
3. Classify every image the repo references (compose files and CI):
   - **CalVer date-tag** (`2026.11.02`, optionally `-suffix`): an image built
     and published by the lab's own pipelines. Safe to automerge at *every*
     update type.
   - **Semver tag** (`v2.39.1`, `44.227`): third-party. Automerge is limited
     (see policy); a compose minor bump is normally manual.
   - **`latest` or floating major** (`postgres:17`): never automerge.
   - When several images are involved, ask the user per image which ones
     should automerge at every update type — never assume.
4. Propose the config change as a concrete diff and apply it only after the
   user agrees. For the canonical per-repo template see
   `reference/renovate.json`; for the CI jobs see
   `reference/gitlab-ci-renovate-jobs.yml`.
5. Validate before pushing: the `renovate-config-check` CI job runs
   `renovate-config-validator`; locally, run it via the pinned Renovate image
   (`docker run --rm -v "$PWD":/repo -w /repo --entrypoint
   renovate-config-validator renovate/renovate:<version> <file>`).
6. After merging a config change, tell the user how it takes effect: Renovate
   runs hourly and re-evaluates *already-open* MRs, so an existing MR can gain
   (or lose) automerge on the next run without a new branch.

## Rules

### Central runner (what is live)

The runner lives in the `renovate/renovate-runner` project. Its config is
`config/renovate-config.js`, loaded via `RENOVATE_CONFIG_FILE`.

| Aspect | Value |
|---|---|
| Cadence | hourly, `0 * * *`, `Europe/Berlin` (pipeline schedule ID 25) |
| Image | `renovate/renovate:<pinned>` — Renovate bumps its own pin |
| Run mode | `renovate --autodiscover=true`, `post` stage (after target pipelines) |
| Config | `requireConfig: 'optional'` — repos *without* their own config are still managed |
| Branch / commits | `branchPrefix: renovate/`, `commitMessagePrefix: chore(deps): ` |
| MR setup | reviewers from code owners, `assignAutomerge: true` |
| Base | `automerge: false` — only rules below enable it |
| Managers | `gomod`, `dockerfile`, `gitlabci`, `docker-compose`, `terraform`, `custom.regex` |

Central packageRules, in order:

1. `gomod` patch+minor → automerge, grouped as `Go dependencies`.
2. `gomod` → ignore unstable releases.
3. `golang.org/x/*` patch+minor → automerge.
4. `dockerfile`/`gitlabci`/`docker-compose` patch+minor → automerge, `pinDigests`.
5. Terraform docker resource images → automerge, `pinDigests`.
6. Current value `latest` → **never** automerge, `pinDigests`.
7. **CalVer date-tag images** (current value matching
   `/^\d{4}\.\d{2}\.\d{2}(-[0-9a-z]+)?/`, docker datasource) across
   `dockerfile`/`gitlabci`/`docker-compose` → automerge at
   `major`, `minor`, `patch`, `replacement`, `digest`, `pinDigests`.

Repos *without* a `renovate.json` therefore automerge compose minor bumps of
any image (rule 4) — including third-party ones. That is the baseline, not a
bug; a repo that wants tighter control adds its own config.

A stale copy of the config also sits in `renovate/renovate-config`
(`renovate-config.js` at that repo's root). It is **not** loaded by anything
and has drifted (older rules, no CalVer rule). Do not edit it expecting an
effect; treat the runner's copy as the only live one.

### Precedence — why per-repo configs must restate everything

Renovate merges the central config first, then appends the repo's own rules,
and evaluates the combined list in order with **later rules overriding
earlier**. A repo-level catch-all such as
`{"matchPackageNames": ["*"], "automerge": false}` therefore overrides *every*
central automerge rule. Consequence:

- A repo with a `renovate.json` gets **only** what its own file re-enables.
  The central rules effectively vanish behind the catch-all.
- A repo without one gets exactly the central rules.

This is why the house template below repeats the whole policy instead of
relying on the central config.

### House per-repo template

Copy `reference/renovate.json` and replace the `hekate-agent` descriptions
with the repo name:

1. Default: no automerge (`matchPackageNames: ["*"]`).
2. `.gitlab-ci.yml` images (gitlabci + docker datasource) → automerge at all
   types: CI-image bumps are exercised by every pipeline.
3. Compose images → automerge `patch` only.
4. Compose images whose current tag is CalVer → automerge at every update
   type (`major`, `minor`, `patch`, `replacement`, `digest`).

Known variants — keep them, they are deliberate:

- `esphome-builder` adds `"platformAutomerge": false`,
  `"timezone": "Europe/Berlin"` and `"automergeSchedule": ["* 3-5 * * *"]`:
  merging redeploys the builder service and interrupts in-flight firmware
  builds, so merges only happen in the 03:00–05:00 night window. Offer this
  to any repo whose deploy job restarts a service people use during the day.
- `traefik` adds a rule that pins `postgres`/`mysql`/`mariadb` (and bitnami
  variants) to `automerge: false` even for patch bumps: database upgrades are
  never automatic.

### CI integration

Every repo that has a `renovate.json` (and every repo Renovate manages)
carries the two jobs from `reference/gitlab-ci-renovate-jobs.yml`:

- `renovate-config-check` (validate stage): pinned `renovate/renovate:<ver>`
  image, `renovate-config-validator`. Runs on every pipeline — a broken
  `renovate.json` must fail fast.
- `docker-deploy-renovate` (renovate/* branches only): the shared
  ssh/docker preamble plus `docker compose pull` — it warms the host's image
  cache so the real deploy after the merge is fast. It must carry the same
  `resource_group` as the live deploy job so the two never fight over the
  host, and it must **never** push images. Renovate jobs may build images but
  pushing from a Renovate branch is forbidden unless the user explicitly
  asks, and then it gets a marker comment (`# renovate: docker push is
  intentional`).

### The CalVer trap

Renovate parses `2026.10.22` as the semver triple `2026.10.22`. A bump to
`2026.11.02` is therefore a **minor** update, and a year rollover (`2027.x`)
is a **major**. Any rule keyed on `matchUpdateTypes` alone will misclassify
date-tagged images — that is exactly why the CalVer rule matches
`matchCurrentValue` instead.

### MR flow

- MRs come from `renovate-bot`, branch `renovate/...`, title
  `chore(deps): Update ... Docker tag to vX.Y.Z`. The body carries the update
  table, the schedule/automerge summary and a `<!--renovate-debug:...-->`
  footer with the Renovate version and target branch.
- The line `🚦 **Automerge**: Disabled by config.` reflects the *rules at the
  time of the last Renovate run*. After a config change it is refreshed on
  the next hourly run — an already-open MR can switch to automatic merging
  without being rebased.
- Automerge merges as soon as the MR pipeline is green (platform automerge),
  which is why the pre-pull job and the `resource_group` coupling exist.
- Renovate rebases on conflict; the daily cleanup schedule (04:40
  Europe/Berlin) closes MRs that have been conflicted for more than
  `RENOVATE_CONFLICT_AGE_DAYS` (3) days and deletes their branches.

### Troubleshooting

- **"Automerge: Disabled by config" on an MR that should merge itself**:
  walk the rule order. Most common cause: the repo's catch-all
  `automerge: false` sits after the rule you expected to win, or the repo
  relies on a central rule while having its own config that shadows it.
- **A minor date-tag bump opened instead of merged**: the CalVer rule is
  missing from the *effective* config (repo config shadowing, or the rule
  never landed). Add the rule from `reference/renovate.json`.
- **`renovate-config-check` red**: run the validator locally, fix the JSON
  (a regex inside `matchCurrentValue` must be slash-delimited:
  `/^\\d{4}\\./`), and never "fix" it by deleting the config — the repo
  falls back to the central rules, which are looser.
- **No MR at all**: check whether the manager is enabled centrally
  (`enabledManagers`), whether the datasource is reachable, and the
  dependency dashboard issue in the repo.

## When to use me

Use this whenever GitLab pipelines or Renovate are involved: Renovate merge
requests, `renovate.json` changes, automerge decisions (especially CalVer
images), the renovate CI jobs, or "why did/didn't this update merge itself".
For structural pipeline review (stages, images, ssh/docker preamble, matrix)
use `glph` — it will point back here for the automerge policy.
