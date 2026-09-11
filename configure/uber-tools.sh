#!/usr/bin/env bash
set -euo pipefail

GITLAB_ENV="${HOME}/.config/gitlab/.env"

if [ ! -f "${GITLAB_ENV}" ]; then
  echo "[uber-tools] skipping: ${GITLAB_ENV} not found"
  exit 0
fi

set -a; source "${GITLAB_ENV}"; set +a

if [ -z "${GITLAB_HOST:-}" ]; then
  echo "[uber-tools] skipping: GITLAB_HOST not set in ${GITLAB_ENV}"
  exit 0
fi

TARGET_DIR="${HOME}/.config/uber-tools"
REMOTE_URL="https://${GITLAB_HOST}/uber/tools.git"

if [ -d "${TARGET_DIR}/.git" ]; then
  actual_remote="$(git -C "${TARGET_DIR}" config --get remote.origin.url 2>/dev/null || true)"
  if [ -n "${actual_remote}" ] && [ "${actual_remote}" != "${REMOTE_URL}" ]; then
    echo "[uber-tools] skipping: ${TARGET_DIR} tracks ${actual_remote}, expected ${REMOTE_URL}; move it out of the way and rerun"
    exit 0
  fi
  git -C "${TARGET_DIR}" pull --ff-only || {
    echo "[uber-tools] failed to update ${TARGET_DIR}; resolve conflicts or fix upstream and rerun"
    exit 1
  }
  echo "[uber-tools] updated ${TARGET_DIR}"
elif [ -e "${TARGET_DIR}" ]; then
  echo "[uber-tools] skipping: ${TARGET_DIR} exists but is not a git repository; remove or relocate it and rerun"
  exit 0
else
  git clone "${REMOTE_URL}" "${TARGET_DIR}" || {
    echo "[uber-tools] failed to clone ${REMOTE_URL}"
    exit 1
  }
  echo "[uber-tools] cloned to ${TARGET_DIR}"
fi

UBERTOOLS_SH="${TARGET_DIR}/uber-tools.sh"
if [ ! -f "${UBERTOOLS_SH}" ]; then
  echo "[uber-tools] skipping PATH setup: ${UBERTOOLS_SH} not found in clone"
  exit 0
fi

UBERTOOLS_BIN="$(dirname "${UBERTOOLS_SH}")"

for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
  [ -f "${rc}" ] || continue

  rc_line1="export PATH=\"${UBERTOOLS_BIN}:\$PATH\""
  rc_line2="alias ut=\"${UBERTOOLS_SH}\""

  if ! grep -qF -- "alias ut=" "${rc}" 2>/dev/null && grep -qF -- "uber-tools" "${rc}" 2>/dev/null; then
    echo "[uber-tools] found a stale uber-tools entry (old path?) in ${rc}; remove it and rerun"
  fi

  if ! grep -qF -- "${rc_line1}" "${rc}" 2>/dev/null; then
    printf '\n%s\n' "${rc_line1}" >> "${rc}"
    echo "[uber-tools] added PATH entry to ${rc}"
  fi
  if ! grep -qF -- "${rc_line2}" "${rc}" 2>/dev/null; then
    printf '%s\n' "${rc_line2}" >> "${rc}"
    echo "[uber-tools] added alias ut to ${rc}"
  fi
done