#!/bin/sh
#
# prepare-secrets.sh - turn a hand-filled secrets.yaml into an import file and
# reference URIs.
#
# HUMAN-ONLY. An AI agent/LLM MUST NOT run this and MUST NOT read the resulting
# secrets.tmp.json. This is the one local step that handles real secret values:
# it reads them from a hand-filled file, writes them to secrets.tmp.json for
# import into the secret manager, and then replaces them with dummies. The
# agent workflow is references-only (secret_refs.yaml, see AGENTS.md).
#
# Steps:
#   1. read a hand-filled secrets file (default esphome/secrets.yaml),
#   2. write secrets.tmp.json, pretty printed, for an Infisical import:
#        {
#          "device-name": {
#            "secret_name": "secret_value"
#          }
#        }
#      ("device-name" is the device slug passed in; secret names are emitted
#      unchanged - no device/config prefix is added, because the device node
#      already scopes them.) The file is mode 600 and gitignored, and it never
#      reaches a bundle (it lives outside esphome/).
#   3. regenerate secret_refs.yaml with the matching storage locations:
#        secret_name: infisical://<project>/<env>/<path>/<device-name>/secret_name
#   4. rewrite esphome/secrets.yaml with schema-valid dummies,
#   5. seed INFISICAL_PROJECT/INFISICAL_ENV/INFISICAL_SECRET_PATH into
#      makefile.conf when they are not configured yet.
#
# Nothing here prints a value - only names and paths.
#
# Usage: ./prepare-secrets.sh <device> [source-secrets-file]
#        make prepare-secrets <device>
#
set -eu

PROG=$(basename "$0")
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

CONF_FILE=${CONF_FILE:-makefile.conf}
SECRET_REFS_FILE=${SECRET_REFS_FILE:-secret_refs.yaml}
ESPHOME_DIR=${ESPHOME_DIR:-esphome}
SECRETS_DEST=$ESPHOME_DIR/secrets.yaml
# Positional override wins over the SECRETS_SRC environment variable.
SECRETS_SRC=${2:-${SECRETS_SRC:-$SECRETS_DEST}}
OUT_FILE=secrets.tmp.json
DUMMY_KEY=${DUMMY_API_KEY:-@@DUMMY_API_KEY@@}

DEVICE=${1:-}
if [ -z "$DEVICE" ]; then
	printf 'Usage: %s <device> [source-secrets-file]\n' "$PROG" >&2
	exit 2
fi

conf_value() {
	[ -f "$CONF_FILE" ] || return 0
	awk -v k="$1" '
		$0 ~ "^" k "[ \t]*[?:]*=" {
			line = $0
			sub(/^[^=]*=[ \t]*/, "", line)
			sub(/[ \t]+#.*$/, "", line)
			sub(/[ \t]+$/, "", line)
			gsub(/^["\047]|["\047]$/, "", line)
			print line
			exit
		}' "$CONF_FILE"
}

# Fill an existing but empty "KEY ?=" line with a value given on the command
# line. Never touches a non-empty line.
conf_fill_empty() {
	key=$1
	val=$2
	[ -n "$val" ] || return 0
	[ -f "$CONF_FILE" ] || return 0
	grep -qE "^$key[[:space:]]*[?:]*=[[:space:]]*$" "$CONF_FILE" 2>/dev/null || return 0
	tmp="$CONF_FILE.tmp.$$"
	awk -v k="$key" -v v="$val" '
		$0 ~ "^" k "[ \t]*[?:]*=[ \t]*$" { print k " ?= " v; next }
		{ print }' "$CONF_FILE" >"$tmp" && mv "$tmp" "$CONF_FILE"
}

# --- coordinates -----------------------------------------------------------
# Command-line/environment overrides win; otherwise makefile.conf is read.
PROJECT=${INFISICAL_PROJECT:-$(conf_value INFISICAL_PROJECT)}
ENV_NAME=${INFISICAL_ENV:-$(conf_value INFISICAL_ENV)}
PATH_PREFIX=${INFISICAL_SECRET_PATH:-$(conf_value INFISICAL_SECRET_PATH)}
ENV_NAME=${ENV_NAME:-dev}
PATH_PREFIX=${PATH_PREFIX:-devices}

case "$DEVICE" in
	*[!A-Za-z0-9._-]*)
		printf '%s: invalid device name: %s\n' "$PROG" "$DEVICE" >&2
		exit 2 ;;
esac
case "$ENV_NAME" in
	''|*[!A-Za-z0-9._-]*)
		printf '%s: invalid INFISICAL_ENV: %s\n' "$PROG" "$ENV_NAME" >&2
		exit 2 ;;
esac
case "$PATH_PREFIX" in
	''|/*|*/|*..*|*[!A-Za-z0-9._/-]*)
		printf '%s: invalid INFISICAL_SECRET_PATH: %s\n' "$PROG" "$PATH_PREFIX" >&2
		exit 2 ;;
esac
if [ -n "$PROJECT" ]; then
	case "$PROJECT" in
		*[!A-Za-z0-9._-]*)
			printf '%s: invalid INFISICAL_PROJECT: %s\n' "$PROG" "$PROJECT" >&2
			exit 2 ;;
	esac
fi

# --- seed makefile.conf ----------------------------------------------------
[ -f "$CONF_FILE" ] || printf '# Global settings for the Makefile.\n' >"$CONF_FILE"

if ! grep -q '^INFISICAL_PROJECT' "$CONF_FILE" 2>/dev/null; then
	{
		printf '\n# Infisical coordinates for the reference URIs in %s.\n' "$SECRET_REFS_FILE"
		printf '# Used only by `make prepare-secrets` (HUMAN-ONLY). PROJECT is the\n'
		printf '# project UUID or slug, ENV the environment slug, SECRET_PATH the\n'
		printf '# parent folder all device secrets live under.\n'
		printf 'INFISICAL_PROJECT ?=\n'
		printf 'INFISICAL_ENV ?= %s\n' "$ENV_NAME"
		printf 'INFISICAL_SECRET_PATH ?= %s\n' "$PATH_PREFIX"
	} >>"$CONF_FILE"
else
	grep -q '^INFISICAL_ENV' "$CONF_FILE" 2>/dev/null || \
		printf 'INFISICAL_ENV ?= %s\n' "$ENV_NAME" >>"$CONF_FILE"
	grep -q '^INFISICAL_SECRET_PATH' "$CONF_FILE" 2>/dev/null || \
		printf 'INFISICAL_SECRET_PATH ?= %s\n' "$PATH_PREFIX" >>"$CONF_FILE"
fi
conf_fill_empty INFISICAL_PROJECT "${INFISICAL_PROJECT:-}"
conf_fill_empty INFISICAL_ENV "${INFISICAL_ENV:-}"
conf_fill_empty INFISICAL_SECRET_PATH "${INFISICAL_SECRET_PATH:-}"

if [ -z "$PROJECT" ]; then
	cat >&2 <<EOF
$PROG: no Infisical project configured - nothing was written.

  Set INFISICAL_PROJECT in $CONF_FILE (project UUID or slug) and re-run, or:
    make prepare-secrets $DEVICE INFISICAL_PROJECT=<project-uuid>

  INFISICAL_ENV (current: $ENV_NAME) and INFISICAL_SECRET_PATH (current:
  $PATH_PREFIX) select the environment and the parent folder.
EOF
	exit 1
fi

# --- guards ----------------------------------------------------------------
if [ ! -f "$SECRETS_SRC" ]; then
	printf '%s: no such secrets file: %s\n' "$PROG" "$SECRETS_SRC" >&2
	exit 2
fi

# A hand-filled copy inside the config tree would be packed by the bundle rule
# (it excludes only secrets.yaml itself), so real values could reach a build.
case "$SECRETS_SRC" in ./*) SECRETS_SRC=${SECRETS_SRC#./} ;; esac
case "$SECRETS_SRC" in
	"$ESPHOME_DIR"/*)
		if [ "$SECRETS_SRC" != "$SECRETS_DEST" ]; then
			printf '%s: refusing SECRETS_SRC inside %s/: %s\n' "$PROG" "$ESPHOME_DIR" "$SECRETS_SRC" >&2
			printf '  Every root YAML there except %s can be bundled. Move the\n' "$SECRETS_DEST" >&2
			printf '  hand-filled file outside %s/ and re-run.\n' "$ESPHOME_DIR" >&2
			exit 2
		fi ;;
esac

if [ -e "$OUT_FILE" ]; then
	cat >&2 <<EOF
$PROG: $OUT_FILE already exists and holds real secret values.

  Import it into the secret manager, delete it, then re-run this target.
  Nothing was changed; refusing to overwrite an export that may not be
  imported yet.
EOF
	exit 1
fi

if [ -f ./check-secrets.sh ] && sh ./check-secrets.sh "$SECRETS_SRC" >/dev/null 2>&1; then
	cat >&2 <<EOF
$PROG: $SECRETS_SRC holds dummy placeholders only - there is nothing to export.

  Fill in the real values first (this target is the one human-only step that
  reads them), then run it again.
EOF
	exit 1
fi

# A flat secret_refs.yaml can only map each name to one path. Refuse to
# silently rewrite references that belong to a different device/path layout.
PREFIX="infisical://$PROJECT/$ENV_NAME/$PATH_PREFIX/$DEVICE/"
if [ -f "$SECRET_REFS_FILE" ]; then
	CONFLICTS=$(awk -v prefix="$PREFIX" '
		/^[A-Za-z0-9_]+:/ {
			v = $0
			sub(/^[^:]*:[ \t]*/, "", v)
			sub(/[ \t]+#.*$/, "", v)
			sub(/[ \t]+$/, "", v)
			gsub(/^["\047]|["\047]$/, "", v)
			if (v != "" && index(v, prefix) != 1) {
				k = $1
				sub(/:$/, "", k)
				print k
			}
		}' "$SECRET_REFS_FILE") || true
	if [ -n "$CONFLICTS" ]; then
		cat >&2 <<EOF
$PROG: $SECRET_REFS_FILE already holds references outside

  $PREFIX

  These names would be rewritten to the path above:
$(printf '    %s\n' $CONFLICTS)

  A flat secret_refs.yaml maps each name to exactly one path, so another
  device may be using them. Merge the references by hand (or prepare secrets
  for one device only) and re-run. Nothing was changed.
EOF
		exit 1
	fi
fi

# --- 1. export (real values -> secrets.tmp.json) ---------------------------
COUNT=$(awk '/^[[:space:]]*(#|$)/ { next } { n++ } END { print n + 0 }' "$SECRETS_SRC")
if ! (umask 077; awk -v dev="$DEVICE" -v prog="$PROG" '
	function esc(s,   o, i, c) {
		o = ""
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c == "\\") o = o "\\\\"
			else if (c == "\"") o = o "\\\""
			else if (c == "\t") o = o "\\t"
			else if (c == "\r") o = o "\\r"
			else if (c == "\n") o = o "\\n"
			else o = o c
		}
		return o
	}
	BEGIN {
		print "{"
		printf "  \"%s\": {\n", esc(dev)
		n = 0
	}
	/^[[:space:]]*(#|$)/ { next }
	{
		line = $0
		sub(/[[:space:]]+#.*$/, "", line)
		i = index(line, ":")
		if (i == 0) {
			printf "%s: malformed line (expected name: value): %s\n", prog, $0 > "/dev/stderr"
			bad = 1
			next
		}
		name = substr(line, 1, i - 1)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
		value = substr(line, i + 1)
		sub(/^[[:space:]]+/, "", value)
		sub(/[[:space:]]+$/, "", value)
		gsub(/^["\047]|["\047]$/, "", value)
		if (name !~ /^[A-Za-z0-9_]+$/) {
			printf "%s: invalid secret name: %s\n", prog, name > "/dev/stderr"
			bad = 1
			next
		}
		if (value == "") {
			printf "%s: empty value for %s - fill it in %s first\n", prog, name, FILENAME > "/dev/stderr"
			bad = 1
			next
		}
		if (n++) printf ",\n"
		printf "    \"%s\": \"%s\"", esc(name), esc(value)
	}
	END {
		if (n) printf "\n"
		print "  }"
		print "}"
		if (bad) exit 1
	}' "$SECRETS_SRC" >"$OUT_FILE"); then
	rm -f "$OUT_FILE"
	printf '%s: no import file written\n' "$PROG" >&2
	exit 1
fi
chmod 600 "$OUT_FILE"

# --- 2. references ---------------------------------------------------------
{
	printf '# One entry per !secret found under %s/: name -> reference URI\n' "$ESPHOME_DIR"
	printf '# pointing to where the secret is stored (infisical://<project>/<env>/<path>).\n'
	printf '# NOT the secret itself. Generated by `make prepare-secrets` (HUMAN-ONLY);\n'
	printf '# edit by hand only to add names or change a path.\n'
	printf '#\n'
	printf '# Device: %s\n' "$DEVICE"
	awk -v base="$PREFIX" '
		/^[[:space:]]*(#|$)/ { next }
		{
			line = $0
			sub(/[[:space:]]+#.*$/, "", line)
			i = index(line, ":")
			if (i == 0) next
			name = substr(line, 1, i - 1)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
			if (name !~ /^[A-Za-z0-9_]+$/) next
			print name ": " base name
		}' "$SECRETS_SRC"
} >"$SECRET_REFS_FILE"

# --- 3. dummies ------------------------------------------------------------
DUMMY_TMP="$SECRETS_DEST.tmp.$$"
mkdir -p "$(dirname "$SECRETS_DEST")"
{
	cat <<EOF
# -----------------------------------------------------------------------------
# DUMMY PLACEHOLDERS ONLY - this file is committed on purpose.
#
# Nothing below is a secret. Real values live only in the secret manager and
# are revealed only server-side by the remote esphome-builder, which resolves
# the reference URIs in $SECRET_REFS_FILE. This file is excluded from every
# config bundle, so CI never transmits it and a leaked placeholder unlocks
# nothing.
#
# It exists so the configs load on a local checkout: \`esphome config\`,
# \`esphome config-hash\`, editor tooling and screenshots all need a value for
# every \`!secret\` reference. Keep the values schema-valid or local validation
# breaks for the next person (WPA passwords >= 8 chars, domain starts with '.',
# encryption key = base64 of exactly 32 non-zero bytes).
#
# Generated by \`make prepare-secrets $DEVICE\` (HUMAN-ONLY): the previous values
# were exported to $OUT_FILE for import and replaced with the dummies below.
#
# HOW TO TELL THESE ARE DUMMIES, WITHOUT ASKING ANYONE:
#   printf %s $DUMMY_KEY | base64 -d
#   -> ESPHOME-DUMMY-KEY-...
# The key decodes to readable ASCII. A real key is random bytes and would
# never print as English text. Every other value here starts with \`test\` for
# the same reason.
#
# Do not treat anything in this file as leaked, do not rotate it, and do not
# compare it against the secret manager to decide whether to use it. Do not
# "improve" the key into all-zeros either: ESPHome rejects an all-zeros key.
# -----------------------------------------------------------------------------
EOF
	awk -v key="$DUMMY_KEY" '
		function dummy(name,   d) {
			if (name == "api_encryption_key" || name ~ /encryption_key$/) return key
			if (name == "domain" || name ~ /^domain_/) return ".local"
			d = "test" name
			gsub(/[^A-Za-z0-9_.-]/, "-", d)
			if (length(d) < 8) d = "test-placeholder"
			return d
		}
		/^[[:space:]]*(#|$)/ { next }
		{
			line = $0
			sub(/[[:space:]]+#.*$/, "", line)
			i = index(line, ":")
			if (i == 0) next
			name = substr(line, 1, i - 1)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
			if (name !~ /^[A-Za-z0-9_]+$/) next
			print name ": " dummy(name)
		}' "$SECRETS_SRC"
} >"$DUMMY_TMP"

mv "$DUMMY_TMP" "$SECRETS_DEST"
chmod 644 "$SECRETS_DEST" 2>/dev/null || true

if [ -f ./check-secrets.sh ]; then
	sh ./check-secrets.sh "$SECRETS_DEST"
fi

if [ "$SECRETS_SRC" != "$SECRETS_DEST" ]; then
	printf '%s: note: %s still holds the real values - delete it\n' "$PROG" "$SECRETS_SRC" >&2
fi

cat <<EOF

$PROG: exported $COUNT secret(s) for device $DEVICE
  import file : $OUT_FILE (mode 600, REAL values, gitignored)
  references  : $SECRET_REFS_FILE -> $PREFIX
  placeholders: $SECRETS_DEST rewritten

Next steps (human only):
  1. import $OUT_FILE into Infisical: project $PROJECT, env $ENV_NAME,
     folder /$PATH_PREFIX/$DEVICE
  2. delete $OUT_FILE afterwards - it is gitignored but holds real values
  3. commit $SECRET_REFS_FILE and $SECRETS_DEST (references + dummies only)
EOF
