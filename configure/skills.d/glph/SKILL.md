---
name: glph
description: Inspect a .gitlab-ci pipeline and propose a plan to harmonize/align it
---

## What I do

1. Load `.gitlab-ci.yml` (also check `.gitlab-ci.yaml` if the other form is absent). If a compose file exists, load it too.
2. Audit the pipeline against the rules below.
3. Produce a harmonization/refactor plan with concrete diffs. Show every proposed diff to the user before applying anything.
4. Ask the user whether they want renovate job(s) in the pipeline.

## Rules

### Images

- Any job that uses common commands, ssh, or docker (alone or combined) must use `s10l/gl-gi-docker-deploy:2026.09.07` or later as its image.
- Never use `latest` as an image tag — always pin a version.
- On violation, flag the job and recommend the pinned `s10l/gl-gi-docker-deploy` image, letting the user pick a newer pin if they want.
- If the image is `s10l/gl-gi-docker-deploy`, do not set `entrypoint: ["/bin/sh", "-c"]` — omit the entrypoint entirely.
- Never share images via templates/anchors (e.g. `<<: *image`); each job declares its `image:` inline.
- Every job must declare its own explicit `image:` — don't rely on a default or inherited image.

### SSH

- SSH configuration must live in the job's `before_script` (a global `before_script` is also ok).
- The ssh section must be preceded by a comment line `- # ssh`.

### Docker

- Docker configuration (login, context setup) must live in `before_script`.
- The docker section must be preceded by a comment line `- # docker`.
- If a context is created and it is the only one, it must be named `remote_host`.

### Pushed image tags

Never rely on `$CI_PIPELINE_ID` (or similar pipeline-scoped values) for tags.

- Build on `main`: push two separate tags — `$IMAGE_DATE=$(date +%Y.%m.%d)` and `latest`.
- Plain build: tag with the short commit hash — never `latest`.
- Multiarch build: append `-$ARCH` to the chosen base tag, where `$ARCH` is only `arm64` or `amd64` (e.g. `$IMAGE_DATE-arm64`, `latest-amd64`, or `$COMMIT_HASH-arm64`).

### Stages

- If stages are similar, use matrix stages to reduce duplication.
- Show the user a potential diff of the matrix refactor.
- For a worked matrix example, see `reference/gitlab-ci-matrix-example.yml` (global variables are illustrative and may change).

### Rules (only/except)

- If a job/stage uses the legacy `only` (or `except`) keyword, refactor it to the modern `rules` layout (e.g. `rules:` with `- if:` conditions), carrying over the equivalent condition and showing the diff.

### Renovate

- Ask the user if they want renovate job(s).
- Renovate jobs may build docker images, but are not allowed to push them to the docker registry.
- If renovate jobs push docker images, only allow it when the user explicitly wants this, and mark the push with a comment noting it is on purpose (e.g. `# renovate: docker push is intentional`).

### Compose

- If a compose file exists and is used:
  - no variables may be used for image tags
  - never use `latest` as an image tag — always pin a version
  - every service must have an `image` attribute
  - `build:` is not allowed

## When to use me

Use this when the user wants to review, harmonize, or refactor their GitLab CI pipeline and/or its compose file.