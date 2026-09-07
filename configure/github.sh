#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git config --global credential.helper store

ghpat=$("${MAIN_DIR}/bin/infisical/infisical.sh" secret get -s /git ghpat)
cred_line="https://oauth2:${ghpat}@github.com"
if grep -qF -- "${cred_line}" "${HOME}/.git-credentials" 2>/dev/null; then
  echo "[github] PAT credential already present for github.com"
else
  echo "${cred_line}" >> "${HOME}/.git-credentials"
  echo "[github] added PAT credential for github.com"
fi
