#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_ENV="${HOME}/.config/gitlab/.env"

if [ ! -f "${GITLAB_ENV}" ]; then
  echo "[glab] skipping: ${GITLAB_ENV} not found"
  exit 0
fi

set -a; source "${GITLAB_ENV}"; set +a

if [ -z "${GITLAB_HOST:-}" ]; then
  echo "[glab] skipping: GITLAB_HOST not set in ${GITLAB_ENV}"
  exit 0
fi
if [ -z "${GITLAB_CLIENT_CERT_FILE:-}" ]; then
  echo "[glab] skipping: GITLAB_CLIENT_CERT_FILE not set in ${GITLAB_ENV}"
  exit 0
fi

if ! command -v glab >/dev/null 2>&1; then
  echo "[glab] skipping: glab (GitLab CLI) not found on PATH"
  exit 0
fi

# --- Convert P12 bundle (cert+key, no passphrase) to separate PEM files ---
GLAB_CERT_DIR="${HOME}/.config/gitlab"
GLAB_CLIENT_CERT="${GLAB_CERT_DIR}/client-cert.pem"
GLAB_CLIENT_KEY="${GLAB_CERT_DIR}/client-key.pem"

mkdir -p "${GLAB_CERT_DIR}"

CERT_TMP=$(mktemp)
KEY_TMP=$(mktemp)
trap 'rm -f "${CERT_TMP}" "${KEY_TMP}"' EXIT

if openssl pkcs12 -in "${GITLAB_CLIENT_CERT_FILE}" -clcerts -nokeys -passin pass: -out "${CERT_TMP}" 2>/dev/null \
   && openssl pkcs12 -in "${GITLAB_CLIENT_CERT_FILE}" -nocerts -nodes -passin pass: -out "${KEY_TMP}" 2>/dev/null; then
  mv "${CERT_TMP}" "${GLAB_CLIENT_CERT}"
  mv "${KEY_TMP}" "${GLAB_CLIENT_KEY}"
  chmod 600 "${GLAB_CLIENT_CERT}" "${GLAB_CLIENT_KEY}"
elif openssl pkcs12 -legacy -in "${GITLAB_CLIENT_CERT_FILE}" -clcerts -nokeys -passin pass: -out "${CERT_TMP}" 2>/dev/null \
     && openssl pkcs12 -legacy -in "${GITLAB_CLIENT_CERT_FILE}" -nocerts -nodes -passin pass: -out "${KEY_TMP}" 2>/dev/null; then
  mv "${CERT_TMP}" "${GLAB_CLIENT_CERT}"
  mv "${KEY_TMP}" "${GLAB_CLIENT_KEY}"
  chmod 600 "${GLAB_CLIENT_CERT}" "${GLAB_CLIENT_KEY}"
else
  echo "[glab] skipping: failed to convert ${GITLAB_CLIENT_CERT_FILE} to PEM (expected empty P12 passphrase)"
  exit 0
fi

glab config set client_cert "${GLAB_CLIENT_CERT}" --host "${GITLAB_HOST}"
glab config set client_key "${GLAB_CLIENT_KEY}" --host "${GITLAB_HOST}"
glab config set -g host "${GITLAB_HOST}"
echo "[glab] default host set to ${GITLAB_HOST}"

if glab auth status --hostname "${GITLAB_HOST}" >/dev/null 2>&1; then
  echo "[glab] already authenticated for ${GITLAB_HOST}"
  exit 0
fi

glpat=$("${MAIN_DIR}/bin/infisical/infisical.sh" secret get -s /git glpat-admin)
if printf '%s\n' "${glpat}" | glab auth login --hostname "${GITLAB_HOST}" --api-host "${GITLAB_HOST}" --api-protocol https --git-protocol https --stdin; then
  echo "[glab] authenticated for ${GITLAB_HOST}"
else
  echo "[glab] WARNING: glab auth login failed (see error above)"
  echo "[glab]   glab requires a PAT with the api and write_repository scopes"
  echo "[glab]   update the /git/glpat-admin secret in Infisical (or the token scopes) and re-run bootstrap.sh"
fi