#!/bin/sh
#
# deploy-ha.sh - interactive copy-in of the homeassistant/ deliverables to the
# live Home Assistant config. Normally run through `make homeassistant`.
#
# Target comes from makefile.conf (HA_TARGET) or the first argument:
#   user@host:/path/to/config   - ssh/scp with key auth (BatchMode)
#   /path/to/config             - plain local path (mounted config / testing)
#
# Flow - every step individually confirmed, everything additive, nothing that
# already exists on the host is deleted:
#   1. probe the target (configuration.yaml must exist)
#   2. deploy homeassistant/packages.d/ into <config>/packages.d/
#   3. enable every package root in configuration.yaml (uncomment / normalize
#      / insert; diff shown; timestamped backup on the host before the push)
#   4. deploy ONE wiring variant (live | bench - NEVER both; presence of the
#      other on the host is flagged)
#   5. enable each deployed wiring file
#   6. validate / 7. reload are intentionally NOT done here: they are
#      WebSocket calls, not shell - run them through the Home Assistant
#      MCP/agent (validate config, then reload core config) or the UI
#      (Settings -> System -> Check configuration / Developer tools -> YAML).
#      The script prints the handoff.
#
# Non-interactive (agent-driven) runs:
#   HA_ASSUME=yes HA_WIRING=live|bench|skip ./deploy-ha.sh [target]
#
# POSIX sh + core utils only, consistent with the other repo scripts.
set -eu
cd -- "$(dirname "$0")"

PROG=${0##*/}
die(){ printf '%s: %s\n' "$PROG" "$1" >&2; exit 1; }
say(){ printf '%s\n' "$1"; }

confirm(){ # $1 prompt -> 0 when yes
	if [ "${HA_ASSUME:-no}" = yes ]; then say "$1 [y - HA_ASSUME=yes]"; return 0; fi
	printf '%s [y/N] ' "$1"
	read -r ans || ans=''
	case $ans in
		[yY]|[yY][eE][sS]) return 0 ;;
		*) return 1 ;;
	esac
}

run(){ # shell command string on the target (-n: never eat prompt stdin)
	if [ "$REMOTE" = 1 ]; then
		ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$1"
	else
		sh -c "$1"
	fi
}
fetch(){ # src dst   (target -> local)
	if [ "$REMOTE" = 1 ]; then scp -q -o BatchMode=yes "$HOST:$1" "$2"; else cp "$1" "$2"; fi
}
pushf(){ # src dst   (local -> target)
	if [ "$REMOTE" = 1 ]; then scp -q -o BatchMode=yes "$1" "$HOST:$2"; else cp "$1" "$2"; fi
}

ensure_line(){ # file key include-path - normalize|uncomment|insert one line
	f=$1; key=$2; path=$3
	want="    $key: !include $path"
	if grep -qxF "$want" "$f"; then
		say "  $key: already enabled"
		return 0
	fi
	if grep -qE "^ *#? *$key:" "$f"; then
		# an active or commented line exists - normalize it to 'want'
		if awk -v key="$key" -v want="$want" '
			!done && $0 ~ ("^ *#? *" key ":") { print want; done = 1; next }
			{ print }
			END { if (!done) exit 3 }' "$f" > "$f.tmp"; then
			mv "$f.tmp" "$f"
			say "  $key: line normalized to '$want'"
		else
			rm -f "$f.tmp"; die "patching '$key' failed (race?)"
		fi
		return 0
	fi
	# absent - insert as first entry of the packages block
	if awk -v want="$want" '
		{ print }
		!ins && /^  packages:/ { print want; ins = 1 }
		END { if (!ins) exit 3 }' "$f" > "$f.tmp"; then
		mv "$f.tmp" "$f"
		say "  $key: inserted into the packages block"
	else
		rm -f "$f.tmp"
		die "no '  packages:' block in configuration.yaml - add '$want' by hand"
	fi
}

patch_start(){ fetch "$CONFDIR/configuration.yaml" "$WORK/cfg"; cp "$WORK/cfg" "$WORK/cfg.orig"; }
patch_finish(){
	if cmp -s "$WORK/cfg.orig" "$WORK/cfg"; then
		say "  configuration.yaml unchanged"
		return
	fi
	say "  --- proposed change ---"
	diff -u "$WORK/cfg.orig" "$WORK/cfg" || true
	if ! confirm "  Apply to $CONFDIR/configuration.yaml?"; then
		say "  skipped - re-run later to enable"
		return
	fi
	stamp=$(date +%Y%m%d-%H%M%S)
	run "cp -a '$CONFDIR/configuration.yaml' '$CONFDIR/configuration.yaml.bak-$stamp'"
	pushf "$WORK/cfg" "$CONFDIR/configuration.yaml"
	say "  applied - host backup: configuration.yaml.bak-$stamp"
}

# ------------------------------- main --------------------------------------

TARGET=${1:-${HA_TARGET:-}}
# defensive: strip surrounding whitespace (make's `VAR = v # comment` keeps
# the space before the '#'; scp paths must be exact)
TARGET=$(printf '%s' "$TARGET" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -n "$TARGET" ] || die "no target - set HA_TARGET in makefile.conf or pass it: $PROG user@host:/path/to/config"
case $TARGET in
	*:*) REMOTE=1 HOST=${TARGET%%:*} CONFDIR=${TARGET#*:} ;;
	/*)  REMOTE=0 HOST=''            CONFDIR=$TARGET ;;
	*)   die "target must be user@host:/path or an absolute local path (got: $TARGET)" ;;
esac
[ -n "$CONFDIR" ] || die "empty config dir in target: $TARGET"

say "deploy-ha - target: $TARGET$([ "$REMOTE" = 1 ] || echo '  (local mode)')"
run "test -f '$CONFDIR/configuration.yaml'" || die "no configuration.yaml under $CONFDIR"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# 2. deploy packages ---------------------------------------------------------
PKG_FILES=""
for f in homeassistant/packages.d/*.yaml; do
	[ -f "$f" ] || continue
	PKG_FILES="$PKG_FILES $(basename "$f")"
done
[ -n "$PKG_FILES" ] || die "no package roots in homeassistant/packages.d/"

if confirm "Deploy homeassistant/packages.d/ into $CONFDIR/packages.d/ (additive)?"; then
	run "mkdir -p '$CONFDIR/packages.d'"
	if [ "$REMOTE" = 1 ]; then
		scp -q -r -o BatchMode=yes homeassistant/packages.d/. "$HOST:$CONFDIR/packages.d/"
	else
		cp -r homeassistant/packages.d/. "$CONFDIR/packages.d/"
	fi
	for f in $PKG_FILES; do
		run "test -f '$CONFDIR/packages.d/$f'" || die "copy verification failed: $CONFDIR/packages.d/$f"
	done
	say "  ok: $(printf '%s ' $PKG_FILES)in place"
fi

# 3. enable packages ---------------------------------------------------------
if confirm "Enable the package root(s) in configuration.yaml?"; then
	patch_start
	for f in $PKG_FILES; do
		key=${f%.yaml}
		ensure_line "$WORK/cfg" "$key" "packages.d/$f"
	done
	patch_finish
fi

# 4./5. deploy + enable ONE wiring variant -----------------------------------
v=${HA_WIRING:-}
if [ -z "$v" ]; then
	printf 'Wiring variant [l]ive / [b]ench / [s]kip: '
	read -r v || v=s
fi
case $v in
	[lL]|[lL]ive) v=live ;;
	[bB]|[bB]ench) v=bench ;;
	[sS]|[sS]kip|'') v='' ;;
	*) die "unknown wiring choice: $v" ;;
esac
if [ -n "$v" ]; then
	other=live; [ "$v" = live ] && other=bench
	WIRING_FILES=""
	for f in homeassistant/wiring.d/wiring.*."$v".yaml; do
		[ -f "$f" ] || continue
		WIRING_FILES="$WIRING_FILES $(basename "$f")"
	done
	[ -n "$WIRING_FILES" ] || die "no wiring.*.$v.yaml in homeassistant/wiring.d/"
	if confirm "Deploy the $v wiring ($(printf '%s ' $WIRING_FILES)) and enable it?"; then
		if run "ls '$CONFDIR'/wiring.d/wiring.*.$other.yaml >/dev/null 2>&1"; then
			say "  WARNING: a $other wiring file is also present - NEVER both; it stays inert only while nothing includes it."
		fi
		run "mkdir -p '$CONFDIR/wiring.d'"
		for f in $WIRING_FILES; do
			if [ "$REMOTE" = 1 ]; then
				scp -q -o BatchMode=yes "homeassistant/wiring.d/$f" "$HOST:$CONFDIR/wiring.d/"
			else
				cp "homeassistant/wiring.d/$f" "$CONFDIR/wiring.d/"
			fi
		done
		patch_start
		for f in $WIRING_FILES; do
			key=${f%.yaml}
			ensure_line "$WORK/cfg" "$key" "wiring.d/$f"
		done
		patch_finish
	fi
fi

# 6./7. handoff ----------------------------------------------------------------
say ""
say "next (WebSocket-side, not shell):"
say "  6. validate - HA 'Check configuration' (Home Assistant MCP) - must be clean"
say "  7. reload  - reload core config (Home Assistant MCP), restart if refused"
say "  then verify the ports: unbound => mirrors unknown => the control loop holds."
