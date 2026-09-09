#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SECRETS_PATH="/ssh"
SSH_DIR="${HOME}/.ssh"
SECRETS=(id_ed25519 id_ed25519_unifi id_ed25519_docker)

mkdir -p "${SSH_DIR}"

DEFAULT_NAME="${SECRETS[0]}"
DEFAULT_INSTALLED=0

for name in "${SECRETS[@]}"; do
  value=$("${MAIN_DIR}/bin/infisical/infisical.sh" secret get -s "${SECRETS_PATH}" "${name}" 2>/dev/null) || {
    echo "[ssh] skipping ${name}: secret not found"
    continue
  }

  printf '%s\n' "${value}" > "${SSH_DIR}/${name}"
  chmod 600 "${SSH_DIR}/${name}"
  chown "${USER}:${USER}" "${SSH_DIR}/${name}"
  echo "[ssh] installed ${name}"

  [ "${name}" = "${DEFAULT_NAME}" ] && DEFAULT_INSTALLED=1
done

if [ "${DEFAULT_INSTALLED}" -eq 1 ]; then
  CONFIG="${SSH_DIR}/config"
  if [ ! -f "${CONFIG}" ] || ! grep -qF "IdentityFile ${SSH_DIR}/${DEFAULT_NAME}" "${CONFIG}" 2>/dev/null; then
    printf '\nHost *\n    IdentityFile %s/%s\n' "${SSH_DIR}" "${DEFAULT_NAME}" >> "${CONFIG}"
    echo "[ssh] configured default identity"
  fi
fi
