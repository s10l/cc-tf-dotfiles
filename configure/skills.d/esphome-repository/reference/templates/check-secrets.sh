#!/bin/sh
#
# check-secrets.sh - prove that esphome/secrets.yaml holds placeholders only.
#
# The committed secrets file exists so the configs load on a local checkout;
# the real values live in the secret manager and are resolved server-side by
# the esphome-builder (see secret_refs.yaml). To keep that claim provable
# rather than a matter of trust, every value in the file must follow the
# placeholder convention:
#
#   - ordinary values start with "test"              testssid, testpassword
#   - wifi domains are ".local"                      (must start with '.')
#   - api_encryption_key is the DUMMY key below, whose 32 decoded bytes are
#     readable ASCII (a real key is random bytes and never reads as English)
#
# Anything else fails: either a real secret got committed (move it to the
# manager, put only the reference in secret_refs.yaml) or a new secret still
# needs a placeholder.
#
# POSIX sh + awk only, so the identical check runs from the Makefile and from
# a CI job on the runner image (no make, no python).
set -eu

PROG=$(basename "$0")
SECRETS_FILE=${1:-esphome/secrets.yaml}
DUMMY_KEY=${DUMMY_API_KEY:-@@DUMMY_API_KEY@@}

if [ ! -f "$SECRETS_FILE" ]; then
	printf '%s: no such file: %s\n' "$PROG" "$SECRETS_FILE" >&2
	exit 2
fi

status=0
BAD=$(awk -v key="$DUMMY_KEY" '
	/^[[:space:]]*(#|$)/ { next }
	{
		line = $0
		sub(/[[:space:]]+#.*$/, "", line)
		i = index(line, ":")
		if (i == 0) { print "malformed line: " $0; bad = 1; next }
		name = substr(line, 1, i - 1)
		value = substr(line, i + 1)
		sub(/^[[:space:]]+/, "", value)
		sub(/[[:space:]]+$/, "", value)
		gsub(/^["\047]|["\047]$/, "", value)
		if (value ~ /^test[^[:space:]]*$/ || value == ".local" || value == key) next
		print name
		bad = 1
	}
	END { exit bad ? 1 : 0 }
' "$SECRETS_FILE") || status=$?

if [ "$status" -ne 0 ]; then
	printf '%s: non-placeholder value line(s) in %s:\n' "$PROG" "$SECRETS_FILE" >&2
	printf '%s\n' "$BAD" >&2
	cat >&2 <<EOF
$PROG: esphome/secrets.yaml must contain dummy placeholders only.
  Real secret values belong in the secret manager and are referenced by name
  in secret_refs.yaml; they are resolved server-side by the esphome-builder,
  never committed and never bundled. Replace the offending value(s) with a
  "test..." placeholder (or the DUMMY api_encryption_key) and re-run.
EOF
	exit 1
fi

printf '%s: %s holds placeholder values only\n' "$PROG" "$SECRETS_FILE"
