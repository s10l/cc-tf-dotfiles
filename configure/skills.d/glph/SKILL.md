---
name: glph
description: Inspect a .gitlab-ci pipeline and propose a plan to harmonize/align it
---

## What I do

1. Load `.gitlab-ci.yml` (also check `.gitlab-ci.yaml` if the other form is absent). If a compose file exists, load it too.
2. Audit the pipeline against the rules below.
3. Produce a harmonization/refactor plan with concrete diffs. Show every proposed diff to the user before applying anything.
4. Audit concurrency: every non-matrix job carries a `resource_group`, matrix jobs carry none — see *Concurrency — resource groups*. Flag uncovered jobs, over-serialization, and same-artifact jobs in different groups.
5. Ask the user whether they want renovate job(s) in the pipeline.
6. Inventory every image the repo references (compose files and CI jobs) and ask which of them should automerge at every update type — see the Renovate section.

## Rules

### Images

- Every job's image must be pinned and suitable for the job's workload:
  - `s10l/gl-gi-docker-deploy:<version>` for jobs using common shell commands, ssh, or docker (alone or combined). `2026.09.07` or later; Renovate bumps the pin, so leave bumping to Renovate.
  - `s10l/gl-gi-ansible:<version>` for jobs that run ansible (it ships the ansible toolchain; `gl-gi-docker-deploy` does not).
  - `renovate/renovate:<version>` for the `renovate-config-check` job only.
- Never use `latest` as an image tag — always pin a version.
- On violation, flag the job and recommend the matching house image, letting the user pick a newer pin if they want.
- If the image is `s10l/gl-gi-docker-deploy`, do not set `entrypoint: ["/bin/sh", "-c"]` — omit the entrypoint entirely.
- Declare the image explicitly: one global `image:` at the top when every job uses the same image, otherwise per job. Never rely on a runner default, and never share an image between jobs via templates or YAML anchors inside `.gitlab-ci.yml`.

### Shared setup

- The house pattern for repeated ssh/docker preamble is a hidden job (`.ssh_and_docker`) whose `before_script` every host-touching job `extends`. Sharing *setup* this way is correct; sharing an *image* is not.
- Never copy-paste the preamble into each job when a hidden job can hold it once.

### SSH

- SSH configuration lives in the job's (or shared hidden job's) `before_script` — a global `before_script` is also ok.
- The ssh section must be preceded by a comment line `# ssh`.
- Host keys stay pinned: `$HOSTKEY_<host>` is written into `known_hosts` (e.g. `cat $HOSTKEY_LAB >> ~/.ssh/known_hosts`). Never add a `StrictHostKeyChecking no` override or `/dev/null` known_hosts — it defeats the pinning. Flag any job that does this.

### Docker

- Docker configuration (login, context setup) must live in `before_script` (job, shared hidden job, or global).
- The docker section must be preceded by a comment line `# docker`.
- Context variables follow the house shape: `CONTEXT: remote_host` and `DOCKER_HOST_URL: "ssh://$SSH_USER@$SSH_HOST"` in the `variables:` block, then `docker context create $CONTEXT --docker host=$DOCKER_HOST_URL`. Additional job-specific contexts are allowed (e.g. a nested-daemon context), but the host context stays named `remote_host`.
- If the compose file references a private registry, `docker login` belongs in the shared preamble.

### Pushed image tags

Never rely on `$CI_PIPELINE_ID` (or similar pipeline-scoped values) for tags.

- Build on `main`: push two separate tags — `$IMAGE_DATE=$(date +%Y.%m.%d)` and `latest`.
- Plain build: tag with the short commit hash — never `latest`.
- Multiarch build: append `-$ARCH` to the chosen base tag, where `$ARCH` is only `arm64` or `amd64` (e.g. `$IMAGE_DATE-arm64`, `latest-amd64`, or `$COMMIT_HASH-arm64`).

### Stages

- If stages are similar, use matrix stages to reduce duplication.
- Show the user a potential diff of the matrix refactor.
- For a worked matrix example, see `reference/gitlab-ci-matrix-example.yml` (global variables are illustrative and may change).
- `parallel: matrix` only where every entry has the same target; if a job's `rules:` need to test a value that would be a matrix variable, it must be a separate per-target job — `rules:` cannot test matrix variables.
- Jobs that touch the same shared resource (one remote host, one builder service) must carry a shared `resource_group` so they serialize instead of racing (e.g. the live deploy and the renovate pre-pull on the same host) — the full concurrency policy lives in *Concurrency — resource groups* below; apply it to every job you review.

### Concurrency — resource groups

Every non-matrix job carries a `resource_group`: duplicate work never races, and serialization is keyed by the job's **kind**, not its pipeline — steps of different pipeline IDs stay concurrent except where they would duplicate or race the same work.

- **Build-type jobs** (`build`, `compile`, `docker-build`, …): one group per build kind — `resource_group: build-go` on the Go build, `resource_group: build-ts` on the TypeScript build. Consequences:
  - same kind, same project (main pipeline vs MR pipeline vs retrigger): serialized — a build never runs concurrently with the same build of the same project;
  - different kinds, same project (`build-go` + `build-ts`): concurrent — they share nothing;
  - same kind, different projects: concurrent (groups are per project).
- **Matrix exception**: a `parallel: matrix` job carries **no** `resource_group`. The matrix exists to run its legs concurrently — if matrix is used, concurrency is planned. The same-kind serialization rule above does not apply between a matrix's legs or between matrix builds of the same kind. When the legs must serialize anyway (they push shared tags, or the build is not safe to repeat), drop the matrix and use per-target jobs instead, each with a group keyed on the target artifact — distinct targets stay concurrent, same-target writes across pipelines serialize.
- **Deploy pipelines**: ONE group for the whole pipeline. Every step that belongs to the deploy — provisioning, one-time backfills, `docker compose up`, smoke checks — carries the same `resource_group: deploy-<target>` (one group per host target when the repo deploys to several). No two deploy steps ever run concurrently with each other, and no other job touches that host while a deploy runs.
- The renovate pre-pull job (`docker-deploy-renovate`) shares the deploy group — it reaches the host too.

Audit checks:

- every non-matrix job has a `resource_group` — flag any without one;
- a matrix job carrying a `resource_group` → flag: it silently serializes its own legs against the matrix design; either drop the group or convert to per-target jobs;
- two jobs sharing a group while producing *different* artifacts → over-serialization, propose separate groups;
- two jobs producing the *same* artifact (same image tag, same manifest, same cache) in *different* groups → under-serialization, propose a shared group;
- deploy steps split across several groups → collapse into the single `deploy-<target>` group.

Group names should describe the shared thing (the artifact, tag, cache or host), never the pipeline — `build-go`, `deploy-lab`, not `$CI_PIPELINE_ID` (a per-pipeline group would serialize nothing).

### Rules (only/except)

- If a job/stage uses the legacy `only` (or `except`) keyword, refactor it to the modern `rules` layout (e.g. `rules:` with `- if:` conditions), carrying over the equivalent condition and showing the diff.
- Recognize the current patterns as correct: a `when: never` exclusion (e.g. skipping scheduled pipelines), schedule-only jobs (`$CI_PIPELINE_SOURCE == "schedule"`), MR-pipeline triggers (`merge_request_event`, optionally combined with a source-branch regex like `/^renovate\//`), and path scoping with `changes:`. A `workflow: rules` block at the top governs which pipelines exist at all.

### Renovate

- Ask the user if they want renovate job(s).
- Renovate jobs may build docker images, but are not allowed to push them to the docker registry.
- If renovate jobs push docker images, only allow it when the user explicitly wants this, and mark the push with a comment noting it is on purpose (e.g. `# renovate: docker push is intentional`).
- A repo managed by Renovate should have the two house jobs (full snippets and the config policy live in the `renovate` skill): `renovate-config-check` (validate stage, pinned `renovate/renovate` image, `renovate-config-validator`) and a `docker-deploy-renovate` pre-pull job on `renovate/*` branches sharing the deploy job's `resource_group`.
- If a `renovate.json` exists, audit it against the house template in the `renovate` skill and validate it (the `renovate-config-check` job does this in CI; run `renovate-config-validator` locally before pushing).

### Renovate: the per-image automerge question

After inventorying the images (step 6), for each **compose file image** determine its tag style:

- **CalVer date-tag** (`2026.11.02`, optionally `-suffix`): the lab's own app images, built by their own pipelines. Candidates for automerge at *every* update type (`major`, `minor`, `patch`, `replacement`, `digest`).
- **Semver / floating / third-party**: automerge stays `patch`-only at most; database images (`postgres`, `mysql`, `mariadb` and bitnami variants) never automerge.

Renovate parses `2026.10.22` as semver, so a date bump `2026.10.22 -> 2026.11.02` is a *minor* update — tag style, not update size, decides the policy.

Then ask the user which of the images should automerge at every update type — repos often pin several images and the answer differs per image:

- Propose a `packageRule` per image the user selects, keyed on `matchPackageNames` (explicit, survives image changes), or the single house rule keyed on `matchCurrentValue: /^\d{4}\.\d{2}\.\d{2}(-[0-9a-z]+)?/` when the user wants *all* date-tagged images covered. Show the diff.
- If the repo's deploy job restarts a service that is used during the day (a builder, a dashboard), also ask about the night window: `platformAutomerge: false` + `timezone: Europe/Berlin` + `automergeSchedule: ["* 3-5 * * *"]` restricts merges to 03:00–05:00. Without it, platform automerge merges as soon as the MR pipeline is green.
- Remind the user: a repo-level `renovate.json` shadows the central rules (its rules are evaluated after them), so the file must restate the whole policy — use the template in the `renovate` skill.

### Compose

- If a compose file exists and is used:
  - no variables may be used for image tags
  - never use `latest` as an image tag — always pin a version
  - every service must have an `image` attribute
  - `build:` is not allowed
  - sharing one image value between services (or between `image:` and a derived variable like a version stamp) via a top-level anchor (`x-...: &name ...`) is fine — the anchor ban above applies to `.gitlab-ci.yml` images only

## When to use me

Use this when the user wants to review, harmonize, or refactor their GitLab CI pipeline and/or its compose file. For Renovate policy, the automerge mechanics and the renovate MR flow, the `renovate` skill is the reference — the two skills are meant to be used together.
