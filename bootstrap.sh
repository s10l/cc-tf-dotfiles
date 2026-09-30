#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

export_dir="${SCRIPT_DIR}/bin/infisical"

# bootstrap runs unattended: never let a tool stop and ask for input. A missing
# credential has to surface as an error (see the failure summary at the end),
# not as a hang waiting for a username.
export GIT_TERMINAL_PROMPT=0

DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  -h|--help)
    printf 'Usage: %s [--dry-run]\n\n  --dry-run  validate module order and list the run without touching $HOME\n' "$0"
    exit 0
    ;;
  "") ;;
  *)
    printf 'unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
esac

# --- PATH setup (idempotent) ---
# CONTRACT: the entry below is the absolute path of this checkout on purpose.
# The tooling is expected at exactly that location, so the path is part of the
# contract: do not make it relative, and do not relocate the clone without
# updating this line and the PATH line already in ~/.bashrc.
#
# Skipped under --dry-run, which must not change anything.
BASHRC="${HOME}/.bashrc"
if [ "${DRY_RUN}" -eq 1 ]; then
  echo "--dry-run: would ensure ${export_dir} is on PATH in ${BASHRC}"
elif ! grep -qF -- "${export_dir}" "${BASHRC}" 2>/dev/null; then
  {
    printf '\n'
    printf '# added by cc-tf-dotfiles bootstrap.sh\n'
    printf '# the absolute checkout path below is a contract: the tooling must stay here.\n'
    printf '# Do not make it relative and do not move the clone without updating it.\n'
    printf 'export PATH="%s:$PATH"\n' "${export_dir}"
  } >> "${BASHRC}"
  echo "Added ${export_dir} to PATH in ${BASHRC}"
else
  echo "PATH already contains ${export_dir}"
fi

# --- Discover modules (registration is by filename: every configure/*.sh runs) ---
MODULES=()
for script in "${SCRIPT_DIR}/configure/"*.sh; do
  [ -f "${script}" ] || continue
  MODULES+=("${script}")
done

if [ ${#MODULES[@]} -eq 0 ]; then
  echo "no modules found in ${SCRIPT_DIR}/configure/"
  exit 0
fi

ORDERED_NAMES=()
for i in "${!MODULES[@]}"; do
  ORDERED_NAMES+=("$(basename "${MODULES[$i]}")")
done

# --- Validate declared dependencies ---
# A module declares what must already have run in a header line:
#   # bootstrap-requires: gitlab.sh
# Execution order is filename order, so this check turns a silent mis-ordering
# (typically a rename) into a loud error instead of a broken machine.
DEPENDENCY_ERRORS=0
for i in "${!MODULES[@]}"; do
  script="${MODULES[$i]}"
  name="${ORDERED_NAMES[$i]}"
  requires="$(sed -n 's/^#[[:space:]]*bootstrap-requires:[[:space:]]*//p' "${script}" | head -n 1)"
  [ -n "${requires}" ] || continue

  for dep in ${requires}; do
    dep_index=-1
    for j in "${!MODULES[@]}"; do
      if [ "${ORDERED_NAMES[$j]}" = "${dep}" ]; then
        dep_index="${j}"
        break
      fi
    done

    if [ "${dep_index}" -lt 0 ]; then
      printf 'dependency error: %s requires %s, which is not a module in configure/\n' "${name}" "${dep}" >&2
      DEPENDENCY_ERRORS=$((DEPENDENCY_ERRORS + 1))
    elif [ "${dep_index}" -ge "${i}" ]; then
      printf 'dependency error: %s runs before %s but requires it\n' "${name}" "${dep}" >&2
      DEPENDENCY_ERRORS=$((DEPENDENCY_ERRORS + 1))
    fi
  done
done

if [ "${DEPENDENCY_ERRORS}" -gt 0 ]; then
  printf 'hint: modules run in filename order - rename one so the dependency sorts first (e.g. 10-gitlab.sh)\n' >&2
  exit 1
fi

if [ "${DRY_RUN}" -eq 1 ]; then
  printf -- '--dry-run: %d module(s) would run in this order:\n' "${#MODULES[@]}"
  for i in "${!MODULES[@]}"; do
    printf '  %d. %s\n' "$((i + 1))" "${ORDERED_NAMES[$i]}"
  done
  printf -- '--dry-run: dependency order OK, nothing was changed\n'
  exit 0
fi

# --- Run every module ---
# A failing module must not take the rest of the run with it: skills, SSH keys
# and the OpenCode config must still be applied when, say, Infisical is
# unreachable. Failures are collected and reported at the end, and the exit
# status is non-zero so an unattended caller still notices.
FAILED=()
for i in "${!MODULES[@]}"; do
  script="${MODULES[$i]}"
  name="${ORDERED_NAMES[$i]}"
  chmod +x "${script}"
  echo "=== Running ${name} ==="
  if ! bash "${script}"; then
    FAILED+=("${name}")
  fi
done

echo
if [ ${#FAILED[@]} -gt 0 ]; then
  printf '=== bootstrap finished: %d of %d module(s) FAILED: %s ===\n' \
    "${#FAILED[@]}" "${#MODULES[@]}" "${FAILED[*]}"
  exit 1
fi
printf '=== bootstrap finished: all %d module(s) OK ===\n' "${#MODULES[@]}"
