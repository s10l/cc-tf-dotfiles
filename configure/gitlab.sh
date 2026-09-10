#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_ENV="${HOME}/.config/gitlab/.env"

if [ ! -f "${GITLAB_ENV}" ]; then
  echo "[gitlab] skipping: ${GITLAB_ENV} not found"
  exit 0
fi

set -a; source "${GITLAB_ENV}"; set +a

if [ -z "${GITLAB_HOST:-}" ]; then
  echo "[gitlab] skipping: GITLAB_HOST not set in ${GITLAB_ENV}"
  exit 0
fi
if [ -z "${GITLAB_CLIENT_CERT_FILE:-}" ]; then
  echo "[gitlab] skipping: GITLAB_CLIENT_CERT_FILE not set in ${GITLAB_ENV}"
  exit 0
fi

git config --global credential.helper store

# --- PAT (idempotent) ---
glpat=$("${MAIN_DIR}/bin/infisical/infisical.sh" secret get -s /git glpat)
cred_line="https://oauth2:${glpat}@${GITLAB_HOST}"
if grep -qF -- "${cred_line}" "${HOME}/.git-credentials" 2>/dev/null; then
  echo "[gitlab] PAT credential already present for ${GITLAB_HOST}"
else
  echo "${cred_line}" >> "${HOME}/.git-credentials"
  echo "[gitlab] added PAT credential for ${GITLAB_HOST}"
fi

# --- mTLS (git config overwrites, so idempotent by nature) ---
git config --global "http.https://${GITLAB_HOST}/.sslCert" "${GITLAB_CLIENT_CERT_FILE}"
git config --global "http.https://${GITLAB_HOST}/.sslCertType" P12
# git config --global "http.https://${GITLAB_HOST}/.sslKey" "${GITLAB_CLIENT_CERT_FILE}" # this is not valid for a P12 bundle with cert+key
echo "[gitlab] configured mTLS for ${GITLAB_HOST}"
