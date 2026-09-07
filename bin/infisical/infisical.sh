#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${INFISICAL_CONFIG_FILE:-$HOME/.config/infisical/.env}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Infisical config file not found: $CONFIG_FILE" >&2
  echo "  Set INFISICAL_CONFIG_FILE to its location or create it." >&2
  exit 1
fi

# Source the config (auto-export) — authoritative source for all INFISICAL_* vars.
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

usage() {
  echo "Usage: $0 secret get [flags] <secret-name>" >&2
  echo "" >&2
  echo "Flags:" >&2
  echo "  -p <id>   project ID  (override config)" >&2
  echo "  -e <slug> environment (override config)" >&2
  echo "  -s <path> secret path (override config, default /)" >&2
  echo "  -v       verbose: print the curl command" >&2
  echo "" >&2
  echo "Config file: $CONFIG_FILE" >&2
  echo "  Defines INFISICAL_TOKEN, INFISICAL_URL, INFISICAL_PROJECT_ID," >&2
  echo "  INFISICAL_ENV_SLUG and INFISICAL_SECRET_PATH." >&2
  echo "  For mTLS: INFISICAL_CLIENT_CERT_FILE (P12 format)." >&2
  echo "  Override the config path with INFISICAL_CONFIG_FILE." >&2
  exit 1
}

[ "$#" -lt 3 ] && usage
[[ "${1:-}" != secret || "${2:-}" != get ]] && usage
shift 2

VERBOSE=0
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--verbose" ] || [ "$arg" = "-v" ]; then
    VERBOSE=1
  else
    ARGS+=("$arg")
  fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

SECRET_NAME=""
PROJECT_ID="${INFISICAL_PROJECT_ID:-}"
ENV_SLUG="${INFISICAL_ENV_SLUG:-}"
SECRET_PATH="${INFISICAL_SECRET_PATH:-/}"

while getopts "p:e:s:" opt; do
  case "$opt" in
    p) PROJECT_ID="$OPTARG" ;;
    e) ENV_SLUG="$OPTARG" ;;
    s) SECRET_PATH="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

[ "$#" -eq 1 ] || usage
SECRET_NAME="$1"

[ -z "${INFISICAL_TOKEN:-}" ] && { echo "Error: INFISICAL_TOKEN not set in config" >&2; exit 1; }
[ -z "${INFISICAL_URL:-}" ] && { echo "Error: INFISICAL_URL not set in config" >&2; exit 1; }
[ -z "$PROJECT_ID" ] && { echo "Error: project ID not set (use -p or INFISICAL_PROJECT_ID in config)" >&2; exit 1; }
[ -z "$ENV_SLUG" ] && { echo "Error: environment not set (use -e or INFISICAL_ENV_SLUG in config)" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required but not installed (see bin/infisical/infisical.md Requirements)" >&2
  exit 1
}

# The access token portion is everything before the last '.' delimiter
ACCESS_TOKEN="${INFISICAL_TOKEN%.*}"

URL="${INFISICAL_URL%/}/api/v4/secrets/${SECRET_NAME}?projectId=${PROJECT_ID}&environment=${ENV_SLUG}&secretPath=${SECRET_PATH}&viewSecretValue=true"

BODY=$(mktemp)
trap 'rm -f "${BODY-}"' EXIT INT TERM

CURL_ARGS=(-s -o "$BODY" -w "%{http_code}" "$URL" -H "Authorization: Bearer ${ACCESS_TOKEN}")
if [ -n "${INFISICAL_CLIENT_CERT_FILE:-}" ]; then
  CURL_ARGS+=(--cert-type P12 --cert "$INFISICAL_CLIENT_CERT_FILE")
fi

if [ "$VERBOSE" -eq 1 ]; then
  printf 'curl' >&2
  for arg in "${CURL_ARGS[@]}"; do
    printf ' %q' "$arg" >&2
  done
  printf '\n' >&2
fi

set +e
HTTP_CODE=$(curl "${CURL_ARGS[@]}")
CURL_RC=$?
set -e

if [ "$CURL_RC" -ne 0 ]; then
  echo "Error: curl failed with exit code $CURL_RC (no HTTP response received)" >&2
  echo "  Check: network connectivity / DNS / TLS to $INFISICAL_URL" >&2
  exit 1
fi

if [ "$HTTP_CODE" -ne 200 ]; then
  echo "Error: Infisical API returned HTTP $HTTP_CODE" >&2
  if [ "$HTTP_CODE" -eq 404 ]; then
    echo "  Secret '${SECRET_NAME}' not found in environment '${ENV_SLUG}' at path '${SECRET_PATH}'." >&2
  else
    echo "  URL: $URL" >&2
    echo "  Response body:" >&2
    sed 's/^/    /' "$BODY" >&2
  fi
  exit 1
fi

if jq -e '.secret? != null' "$BODY" >/dev/null 2>&1; then
  VALUE=$(jq -r '.secret.secretValue? // empty' "$BODY")
  if [ -z "$VALUE" ]; then
    echo "note: secret '${SECRET_NAME}' exists but its value is empty" >&2
  fi
  echo "$VALUE"
else
  echo "Error: HTTP 200 but secret '${SECRET_NAME}' not found in the Infisical response" >&2
  echo "  URL: $URL" >&2
  sed 's/^/    /' "$BODY" >&2
  exit 1
fi