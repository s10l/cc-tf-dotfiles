---
name: infisical
description: Reference for reading secrets from the self-hosted Infisical, in three scopes: the local shell wrapper `infisical.sh`, the CI wrapper shipped in the gl-gi-docker-deploy golden image, and the v4 API for code (Universal Auth, mTLS, PBES2 PKCS#12). Use when a shell command, a pipeline job, or a program needs a secret, or when a lookup fails with HTTP 400/404, an mTLS/TLS handshake error, or an empty value.
---

## What I do

1. Pick the client that matches the scope, then follow that reference:
   - **Local shell** — use the wrapper shipped with the dotfiles repo:
     `infisical.sh secret get [-s <path>] <name>`.
     Details: `reference/local-shell.md`.
   - **GitLab CI / any job running in the golden image** — use the wrapper
     baked into the image at `/usr/local/bin/infisical.sh` (verbs like
     `pull-secret`, `push-secret`). Details: `reference/ci-golden-image.md`.
   - **Code in the app** (Go or anything else) — use the v4 API with
     Universal Auth and mTLS directly. Details: `reference/v4-api.md`.
     Copy those requests instead of a snippet from memory.

2. Never roll a new client by hand until all three scopes above have been
   checked - each already exists and already handles the mTLS and
   token mechanics correctly.

3. In every scope: treat any non-2xx as a failure and report the body. An
   empty value must never be returned as success.

## When to use me

- A shell one-liner or script needs a secret locally.
- A pipeline job needs a secret: choosing the client, reading a value into a
  file, or pushing a new value.
- A program needs to fetch a secret itself, or an existing fetch is failing:
  HTTP 400, HTTP 404, an mTLS/TLS handshake error, or a secret that comes
  back empty although it exists in the UI.

## Rules

- **Never log, echo or commit a secret value.** Diagnostics may name the
  secret, environment, path, HTTP status and Infisical's `message` - never
  the value.
- **Never swallow the status.** The classic regression is a failed read that
  returns 400, is ignored, and surfaces as an empty string "successfully".
  Check the status and the body.
- **An empty value is a failure to fetch**, not a successful empty secret -
  at least for anything consumed as a token. The wrappers and helpers in
  `reference/local-shell.md` and `reference/ci-golden-image.md` guard this;
  code that reads the API must assert non-2xx **and** a non-empty
  `.secret.secretValue`.
- **mTLS is enforced.** Every request, login included, carries the client
  certificate; without it the request dies in the TLS handshake rather than
  with an HTTP status.
- **v4 for reads.** `GET /api/v4/secrets/<name>` is the current endpoint. Do
  not use `/api/v3/secrets/raw/...`, and never `/api/v2/secrets/...`. v3
  needs `workspaceId`, not `projectId`; a v3 read sent `projectId` is
  rejected with 400 - that 400 is the bug, not a fallback signal.
- **A wrong folder is indistinguishable from a missing secret.** Project,
  environment, path and name all take part in the lookup; a 404 names the
  mismatching dimensions - compare `environment` and `secretPath` with the
  UI.
- **Bad client-certificate material must not take a service down.** If a
  provider is optional, an empty or undecodable certificate should disable
  that provider with one clear log line, not crash the process at start-up -
  a crash loop hides the actual error.
