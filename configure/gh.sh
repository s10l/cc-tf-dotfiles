#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "${MAIN_DIR}/lib/common.sh"

if ! infisical_configured; then
  echo "[gh] skipping: no Infisical config at ${INFISICAL_CONFIG_FILE:-${HOME}/.config/infisical/.env}"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "[gh] skipping: gh (GitHub CLI) not found on PATH"
  exit 0
fi

if gh auth status --hostname github.com >/dev/null 2>&1; then
  echo "[gh] already authenticated for github.com"
  exit 0
fi

ghpat="$(fetch_secret ghpat /git gh)" || exit 1
if printf '%s\n' "${ghpat}" | gh auth login --hostname github.com --with-token --git-protocol https; then
  echo "[gh] authenticated for github.com"
else
  echo "[gh] WARNING: gh auth login failed (see error above)"
  echo "[gh]   gh requires a classic PAT with the scopes: repo, read:org, gist"
  echo "[gh]   fine-grained PATs are not accepted by 'gh auth login --with-token'"
  echo "[gh]   update the /git/ghpat secret in Infisical and re-run bootstrap.sh"
fi