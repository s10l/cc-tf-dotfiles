#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "${MAIN_DIR}/lib/common.sh"

if ! infisical_configured; then
  echo "[github] skipping: no Infisical config at ${INFISICAL_CONFIG_FILE:-${HOME}/.config/infisical/.env}"
  exit 0
fi

git config --global credential.helper store

ghpat="$(fetch_secret ghpat /git github)" || exit 1
cred_line="https://oauth2:${ghpat}@github.com"
if grep -qF -- "${cred_line}" "${HOME}/.git-credentials" 2>/dev/null; then
  echo "[github] PAT credential already present for github.com"
else
  echo "${cred_line}" >> "${HOME}/.git-credentials"
  echo "[github] added PAT credential for github.com"
fi
