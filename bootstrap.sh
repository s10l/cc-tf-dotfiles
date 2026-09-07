#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory this script lives in (handles symlinks and relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export_dir="${SCRIPT_DIR}/bin/infisical"

BASHRC="${HOME}/.bashrc"
line="export PATH=\"\${PATH}:${export_dir}\""

if ! grep -qF -- "${export_dir}" "${BASHRC}" 2>/dev/null; then
  printf '\n%s\n' "${line}" >> "${BASHRC}"
  echo "Added ${export_dir} to PATH in ${BASHRC}"
else
  echo "Already present in ${BASHRC}: ${export_dir}"
fi
