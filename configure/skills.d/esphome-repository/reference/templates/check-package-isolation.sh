#!/bin/sh
#
# check-package-isolation.sh - prove that no HA package references an entity
# id outside its own namespace.
#
# Every package directory homeassistant/packages.d/<pkg>.d may only create and
# reference entities in its OWN namespace (<pkg>_*). Anything from the outside
# world must arrive through an input_text port - the port mechanism is what
# keeps packages replaceable and their data sources swappable without package
# edits, so the rule is enforced mechanically here instead of by review.
#
# What is scanned: *.yaml under the package dir (YAML comments stripped -
# CONTRACT.md and comments MAY name foreign ids, they are documentation).
# What passes: an entity-id token whose name starts with the package prefix,
# plus plain service-call pairs (domain.set_value, domain.select_option, ...)
# that only look like entity ids.
#
# POSIX sh + awk only, so the identical check runs by hand and as the CI
# validate-stage step on the runner image (no make, no python).
set -eu

PROG=$(basename "$0")
ROOT=${1:-homeassistant/packages.d}

# entity-id shape we look for: <domain>.<name>. Domains chosen from the ones
# this system's wiring actually binds. Longer alternatives first so
# binary_sensor/text_sensor/input_* match as wholes.
DOMAINS='input_number|input_select|input_text|binary_sensor|text_sensor|sensor|number|switch|counter'

# service-call suffixes: "number.set_value" is a service name, not an id
SERVICE_OK='^(number|input_number|input_select|input_text|sensor|text_sensor|binary_sensor|switch|counter)\.(set_value|select_option|turn_on|turn_off|reload|create|remove|update|turn_toggle|reset|increment|decrement|check_in)$'

scan_pkg() {
	dir=$1
	pkg=$2
	if [ ! -d "$dir" ]; then
		printf '%s: package dir missing: %s\n' "$PROG" "$dir" >&2
		return 1
	fi
	offenders=""
	for f in "$dir"/*.yaml; do
		[ -f "$f" ] || continue
		hits=$(awk -v DOM="$DOMAINS" -v PKG="$pkg" -v F="$f" '
			{
				line = $0
				sub(/[ \t]#.*$/, "", line)    # inline comment
				sub(/^[ \t]*#.*$/, "", line)  # whole-line comment
				s = line
				while (match(s, "((^|[^A-Za-z0-9_])(" DOM ")[A-Za-z0-9_]*\\.[A-Za-z0-9_]+)")) {
					m = substr(s, RSTART, RLENGTH)
					sub("^[^a-z]", "", m)       # drop the boundary char
					# allowed: <domain>.<pkg>_... - own namespace behind the dot
					if (m !~ ("^[A-Za-z0-9_]+\\." PKG "_"))
						print F ":" NR ":" m
					s = substr(s, RSTART + RLENGTH)
				}
			}
		' "$f")
		for h in $hits; do
			ent=${h##*:}
			printf '%s\n' "$ent" | grep -Eq "$SERVICE_OK" && continue
			offenders="$offenders$h
"
		done
		# HA 2026.10 schema fact: the template integration cannot declare or
		# reference text_sensor entities (own-namespace prefix would sneak
		# past the filter, so check the domain explicitly).
		if sed 's/^[[:space:]]*#.*$//; s/[[:space:]]#.*$//' "$f" | grep -q 'text_sensor'; then
			printf '%s: %s: text_sensor is not supported by the HA 2026 template integration - string entities are plain sensor.*\n' "$PROG" "$f" >&2
			return 1
		fi
	done
	if [ -n "$offenders" ]; then
		printf '%s' "$offenders" >&2
		return 1
	fi
	printf '%s: %s is namespace-clean (pkg=%s)\n' "$PROG" "$dir" "$pkg"
}

# Merge-shape guard: a package ROOT (packages.d/*.yaml) must be a MAPPING of
# domain keys, each `domain: !include part.yaml` binding a BARE part (no
# domain key of its own). Two failure modes, both seen on live instances:
#   * list root - HA setup aborts with "expected a mapping" and
#     validate_config does NOT flag it;
#   * part that keeps its own domain key under such a root - double-nests,
#     every helper errors as "input_text->input_text-><name> is an invalid
#     option".
scan_roots(){
	rc2=0
	for f in "$ROOT"/*.yaml; do
		[ -f "$f" ] || continue
		# (a) list root: a top-level "- " item
		if grep -qE '^- ' "$f"; then
			printf '%s: %s is a list-root (HA wants a mapping of domain keys - "expected a mapping")\n' "$PROG" "$f" >&2
			rc2=1
		fi
		# (b) every domain: !include part - the part must be BARE content
		grep -E '^[A-Za-z_]+:[[:space:]]*!include' "$f" | while IFS=' ' read -r key _kw path; do
			dom=${key%:}
			part="$ROOT/$path"
			[ -f "$part" ] || continue
			first=$(grep -vE '^[[:space:]]*(#|$)' "$part" | head -1 | sed 's/^[[:space:]]*//')
			[ "$first" = "$dom:" ] || continue
			printf '%s: %s keeps its own %s root key (double-nests under %s) - parts must be BARE content\n' "$PROG" "$path" "$dom" "$f" >&2
			exit 7
		done
		[ $? -eq 7 ] && rc2=1
	done
	return $rc2
}

rc=0
scan_roots || rc=1

found=0
for dir in "$ROOT"/*.d; do
	[ -d "$dir" ] || continue
	found=1
	pkg=$(basename "$dir" .d)
	scan_pkg "$dir" "$pkg" || rc=1
done

if [ "$found" -eq 0 ]; then
	printf '%s: no package directories under %s - nothing to lint\n' "$PROG" "$ROOT"
	exit 0
fi

if [ "$rc" != 0 ]; then
	cat >&2 <<EOF
$PROG: isolation rule violated - a package references an entity id outside
its own namespace. Move the value behind an input_text port
(<pkg>_src_*/<pkg>_out_*) and bind it in homeassistant/wiring.d/ instead.
EOF
	exit 1
fi

printf '%s: all HA packages pass the isolation guard\n' "$PROG"
