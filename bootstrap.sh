#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export_dir="${SCRIPT_DIR}/bin/infisical"

# --- PATH setup (idempotent) ---
BASHRC="${HOME}/.bashrc"
if ! grep -qF -- "${export_dir}" "${BASHRC}" 2>/dev/null; then
  printf '\nexport PATH="%s:$PATH"\n' "${export_dir}" >> "${BASHRC}"
  echo "Added ${export_dir} to PATH in ${BASHRC}"
else
  echo "PATH already contains ${export_dir}"
fi

# --- Make configure scripts executable & run them ---
for script in "${SCRIPT_DIR}/configure/gitlab.sh" "${SCRIPT_DIR}/configure/github.sh"; do
  if [ -f "${script}" ]; then
    chmod +x "${script}"
    echo "=== Running ${script} ==="
    bash "${script}"
  else
    echo "Missing: ${script}"
  fi
done
