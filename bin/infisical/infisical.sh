#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 secret get [flags] <secret-name>" >&2
  echo "" >&2
  echo "Flags:" >&2
  echo "  -p <id>   project ID  (override INFISICAL_PROJECT_ID)" >&2
  echo "  -e <slug> environment (override INFISICAL_ENV_SLUG)" >&2
  echo "  -s <path> secret path (override INFISICAL_SECRET_PATH, default /)" >&2
  echo "" >&2
  echo "Env vars:" >&2
  echo "  INFISICAL_TOKEN  required    full service token" >&2
  echo "  INFISICAL_URL    required    e.g. https://infisical.stefanbickel.com" >&2
  echo "  INFISICAL_PROJECT_ID         project ID" >&2
  echo "  INFISICAL_ENV_SLUG           environment slug" >&2
  echo "  INFISICAL_SECRET_PATH        secret path (default /)" >&2
  exit 1
}

[ "$#" -lt 3 ] && usage
[ "$1" != "secret" ] || [ "$2" != "get" ] && usage
shift 2

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

[ -z "${INFISICAL_TOKEN:-}" ] && { echo "Error: INFISICAL_TOKEN not set" >&2; exit 1; }
[ -z "${INFISICAL_URL:-}" ] && { echo "Error: INFISICAL_URL not set" >&2; exit 1; }
[ -z "$PROJECT_ID" ] && { echo "Error: project ID not set (use -p or INFISICAL_PROJECT_ID)" >&2; exit 1; }
[ -z "$ENV_SLUG" ] && { echo "Error: environment not set (use -e or INFISICAL_ENV_SLUG)" >&2; exit 1; }

# The access token portion is everything before the last '.' delimiter
ACCESS_TOKEN="${INFISICAL_TOKEN%.*}"

URL="${INFISICAL_URL%/}/api/v4/secrets/${SECRET_NAME}?projectId=${PROJECT_ID}&environment=${ENV_SLUG}&secretPath=${SECRET_PATH}&viewSecretValue=true"

BODY=$(mktemp)
HTTP_CODE=$(curl -s -o "$BODY" -w "%{http_code}" "$URL" -H "Authorization: Bearer ${ACCESS_TOKEN}")
CURL_RC=$?

if [ "$CURL_RC" -ne 0 ]; then
  echo "Error: curl failed with exit code $CURL_RC (no HTTP response received)" >&2
  echo "  Check: network connectivity / DNS / TLS to $INFISICAL_URL" >&2
  rm -f "$BODY"
  exit 1
fi

if [ "$HTTP_CODE" -ne 200 ]; then
  echo "Error: Infisical API returned HTTP $HTTP_CODE" >&2
  echo "  URL: $URL" >&2
  echo "  Response body:" >&2
  sed 's/^/    /' "$BODY" >&2
  rm -f "$BODY"
  exit 1
fi

RESPONSE=$(cat "$BODY")
rm -f "$BODY"

VALUE=$(echo "$RESPONSE" | jq -r '.secret.secretValue // empty' 2>/dev/null)

[ -z "$VALUE" ] && { echo "Error: secret '${SECRET_NAME}' not found or empty in response" >&2; exit 1; }

echo "$VALUE"
