#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "${MAIN_DIR}/lib/common.sh"

SECRETS_PATH="/ssh"
SSH_DIR="${HOME}/.ssh"
SECRETS=(id_ed25519 id_ed25519_unifi id_ed25519_docker)

mkdir -p "${SSH_DIR}"

DEFAULT_NAME="${SECRETS[0]}"
DEFAULT_INSTALLED=0

for name in "${SECRETS[@]}"; do
  # stderr is dropped on purpose: these keys are optional, so a missing secret
  # is normal and gets the friendly message below instead of a stack of
  # diagnostics. An empty value is rejected too - it would write a useless
  # empty key file.
  value="$(fetch_secret "${name}" "${SECRETS_PATH}" ssh 2>/dev/null)" || {
    echo "[ssh] skipping ${name}: secret not found or empty in ${SECRETS_PATH}"
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
