#!/usr/bin/env bash
# Shared helpers, sourced by bootstrap.sh and the configure modules.
# Sourced only - never executed.
#
# Callers keep their own MAIN_DIR for their own path maths; DOTFILES_DIR here
# is the same directory computed from this file's location, so the helpers work
# no matter who sourced them.

if [ -z "${DOTFILES_DIR:-}" ]; then
  DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# infisical <args...> - thin wrapper so no caller re-derives the binary path.
infisical() {
  "${DOTFILES_DIR}/bin/infisical/infisical.sh" "$@"
}

# True when an Infisical config exists. Mirrors the default the CLI itself
# resolves, so a machine without Infisical skips instead of failing.
infisical_configured() {
  [ -f "${INFISICAL_CONFIG_FILE:-${HOME}/.config/infisical/.env}" ]
}

# fetch_secret <secret-name> <secret-path> <tag>
# Prints the secret value on stdout, diagnostics on stderr. Returns non-zero
# when the secret cannot be fetched OR comes back empty: the CLI treats an
# empty value as success, so without this guard an empty token would be
# written out as "https://oauth2:@host".
fetch_secret() {
  local name="$1" path="$2" tag="$3" value=""

  if ! value="$(infisical secret get -s "${path}" "${name}" 2>/dev/null)"; then
    echo "[${tag}] FAILED: cannot fetch secret '${name}' from Infisical path '${path}'" >&2
    echo "[${tag}]   check the token/host/cert in ~/.config/infisical/.env and network access, then re-run bootstrap.sh" >&2
    return 1
  fi

  if [ -z "${value}" ]; then
    echo "[${tag}] FAILED: secret '${name}' in Infisical path '${path}' is empty" >&2
    echo "[${tag}]   set the secret in Infisical, then re-run bootstrap.sh" >&2
    return 1
  fi

  printf '%s' "${value}"
}
