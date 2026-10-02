#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "${MAIN_DIR}/lib/common.sh"

# Creates one docker context per context described in ~/.config/docker/.env.
#
# The env file is the only source of truth; the prefix is DOCKER_CONTEXT_ so a
# stray REGISTRY_HOST in the same file cannot be mistaken for a context:
#
#   DOCKER_CONTEXT_PROD_HOST=tcp://prod.example.com:2376
#   DOCKER_CONTEXT_PROD_CA=/home/me/.docker/prod/ca.pem
#   DOCKER_CONTEXT_PROD_CERT=/home/me/.docker/prod/cert.pem
#   DOCKER_CONTEXT_PROD_KEY=/home/me/.docker/prod/key.pem
#   DOCKER_CONTEXT_PROD_DESCRIPTION="prod fleet"
#   DOCKER_CONTEXT_STAGING_HOST=tcp://staging.example.com:2376
#
# The context name is the lowercased <NAME> between the prefix and _HOST, so
# PROD above becomes the context "prod". Only _HOST is required; _CA, _CERT,
# _KEY, _DESCRIPTION and _SSH_ID are optional and left out of the endpoint when
# unset. _SSH_HOST_KEY, if present, is added as a line to ~/.ssh/known_hosts
# idempotently.
#
# Everything here is client-side: docker context needs no daemon, and nothing
# outside ~/.docker is touched. An existing context is updated in place rather
# than recreated, so a name that is already in use keeps its history. The
# active context is never switched and a context that disappears from the env
# file is never removed - both would be a surprise on someone else's machine.

DOCKER_ENV="${HOME}/.config/docker/.env"
ENV_PREFIX="DOCKER_CONTEXT_"

if [ ! -f "${DOCKER_ENV}" ]; then
  echo "[docker] skipping: ${DOCKER_ENV} not found"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[docker] skipping: docker not found on PATH"
  exit 0
fi

set -a; source "${DOCKER_ENV}"; set +a

# Indirect expansion that yields the empty string for an unset variable: the
# optional _CA/_CERT/_KEY/_DESCRIPTION keys are usually absent, and a bare
# ${!key} would trip set -u on them.
value_of() {
  local key="$1"
  if [ -n "${!key+set}" ]; then
    printf '%s' "${!key}"
  fi
}

# Add an SSH host key line to known_hosts idempotently
add_known_hosts_line() {
  local line="$1"
  local kh_dir="${HOME}/.ssh"
  local kh_file="${kh_dir}/known_hosts"

  if [ -z "${line}" ]; then
    return 0
  fi

  # Trim trailing newlines for exact matching
  line="$(printf '%s' "${line}" | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}' -e 's/\n*$//')"
  if [ -z "${line}" ]; then
    return 0
  fi

  mkdir -p "${kh_dir}"
  chmod 700 "${kh_dir}"
  touch "${kh_file}"
  chmod 600 "${kh_file}" 2>/dev/null || true

  if grep -qxF "${line}" "${kh_file}"; then
    return 0
  fi

  printf '%s\n' "${line}" >> "${kh_file}"
}

ALL_KEYS="$(compgen -v | grep -E "^${ENV_PREFIX}[A-Za-z0-9_.+-]+_(HOST|CA|CERT|KEY|DESCRIPTION|SSH_HOST_KEY)$" || true)"
HOST_KEYS="$(printf '%s\n' ${ALL_KEYS} | grep -E "_HOST$" || true)"

if [ -z "${HOST_KEYS}" ]; then
  if [ -n "${ALL_KEYS}" ]; then
    # _HOST is the one required key: without it there is no endpoint, so the
    # context cannot be created and the other keys are unreachable.
    echo "[docker] FAILED: ${DOCKER_ENV} has ${ENV_PREFIX}<NAME>_* keys but no ${ENV_PREFIX}<NAME>_HOST"
    echo "[docker]   _HOST is required; _CA, _CERT, _KEY, _DESCRIPTION and _SSH_HOST_KEY are optional"
    exit 1
  fi
  echo "[docker] skipping: no ${ENV_PREFIX}<NAME>_HOST entries in ${DOCKER_ENV}"
  exit 0
fi

# Docker Desktop ships these; updating one would repoint Docker Desktop itself.
readonly RESERVED_CONTEXTS="default desktop-linux"

FAILED=()
ORPHANED=""
CONFIGURED=0

for host_key in ${HOST_KEYS}; do
  prefix="${host_key%_HOST}"
  name="$(printf '%s' "${prefix#"${ENV_PREFIX}"}" | tr '[:upper:]' '[:lower:]')"

  host="$(value_of "${host_key}")"
  ca="$(value_of "${prefix}_CA")"
  cert="$(value_of "${prefix}_CERT")"
  key="$(value_of "${prefix}_KEY")"
  description="$(value_of "${prefix}_DESCRIPTION")"
  ssh_host_key="$(value_of "${prefix}_SSH_HOST_KEY")"

  if printf '%s\n' ${RESERVED_CONTEXTS} | grep -qxF "${name}"; then
    echo "[docker] skipping: '${name}' is a reserved docker context; pick another <NAME> in ${DOCKER_ENV}"
    continue
  fi

  if [ -z "${host}" ]; then
    echo "[docker] FAILED: ${host_key} is set but empty"
    FAILED+=("${name}")
    continue
  fi

  # docker needs cert and key together; cacert stands alone.
  if { [ -n "${cert}" ] && [ -z "${key}" ]; } || { [ -n "${key}" ] && [ -z "${cert}" ]; }; then
    echo "[docker] FAILED: ${prefix} needs both _CERT and _KEY, or neither"
    FAILED+=("${name}")
    continue
  fi

  bad_path=""
  for path in "${ca}" "${cert}" "${key}"; do
    if [ -n "${path}" ] && [ ! -r "${path}" ]; then
      bad_path="${path}"
      break
    fi
  done

  if [ -n "${bad_path}" ]; then
    echo "[docker] FAILED: ${prefix} points at ${bad_path}, which does not exist or is not readable"
    FAILED+=("${name}")
    continue
  fi

  endpoint="host=${host}"
  if [ -n "${ca}" ]; then
    endpoint="${endpoint},cacert=${ca}"
  fi
  if [ -n "${cert}" ]; then
    endpoint="${endpoint},cert=${cert},key=${key}"
  fi

  create_args=()
  if [ -n "${description}" ]; then
    create_args=(--description "${description}")
  fi

  if docker context inspect "${name}" >/dev/null 2>&1; then
    action="update"
  else
    action="create"
  fi

  # stdout of docker context create/update is a progress line, not something
  # worth printing; stderr is left alone so a failure explains itself.
  if docker context "${action}" "${name}" "${create_args[@]}" --docker "${endpoint}" >/dev/null; then
    echo "[docker] ${action}d context '${name}' -> ${host}"
    CONFIGURED=$((CONFIGURED + 1))
  else
    echo "[docker] FAILED: 'docker context ${action} ${name} --docker ${endpoint}' failed"
    FAILED+=("${name}")
  fi

  add_known_hosts_line "${ssh_host_key}"
done

# Optional keys for a context that has no _HOST would otherwise be silently
# dropped: catch them so a typo in the required key is not a no-op.
for key in ${ALL_KEYS}; do
  case "${key}" in
    *_HOST) continue ;;
  esac
  orphan_prefix="${key%_*}"
  if printf '%s\n' ${HOST_KEYS} | grep -q "^${orphan_prefix}_HOST$"; then
    continue
  fi
  if printf '%s\n' ${ORPHANED} | grep -qxF "${orphan_prefix}"; then
    continue
  fi
  ORPHANED="${ORPHANED} ${orphan_prefix}"
  echo "[docker] FAILED: ${key} is set but ${orphan_prefix}_HOST is not"
  echo "[docker]   _HOST is required per context; _CA, _CERT, _KEY, _DESCRIPTION and _SSH_HOST_KEY are optional"
  FAILED+=("${orphan_prefix#"${ENV_PREFIX}"}")
done

if [ ${#FAILED[@]} -gt 0 ]; then
  printf '[docker] %d context(s) failed: %s\n' "${#FAILED[@]}" "${FAILED[*]}"
  exit 1
fi

echo "[docker] ${CONFIGURED} context(s) in sync with ${DOCKER_ENV}"
