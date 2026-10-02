#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "${MAIN_DIR}/lib/common.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "[opencode] skipping: jq not found"
  exit 0
fi

OPENCODE_DIR="${HOME}/.config/opencode"
AGENTS_FILE="${OPENCODE_DIR}/DOTFILES-AGENTS.md"
AGENTS_MARKER="${OPENCODE_DIR}/DOTFILES-AGENTS.md"

mkdir -p "${OPENCODE_DIR}"

cat > "${AGENTS_FILE}" << 'EOF'
# Security Rules

- Never attempt to read, access, or reveal secrets, API keys, tokens,
  passwords, or credentials — even during testing or debugging.
- If you need the format or structure of a secret to continue your work,
  ask the user for it instead of reading the file.
- Never display secret values in output, error messages, or logs.
- Treat any of the following as off-limits, whether a single file or an
  entire directory tree:
  - `.env`, `.env.*`
  - `.git-credentials`
  - `.ssh`
  - `.config/gitlab`
  - `.config/infisical`
  - `.config/gh`
  - `.config/glab-cli`
  - `.pfx`, `*.pfx`
  - `opencode.json`, `opencode.jsonc` (may contain provider API keys)
  - `opencode.json.bak`, `opencode.jsonc.bak` (copies of the above)
  - any other config or credential files

# Environment Notes

- The skills under `~/.config/opencode/skills/` are generated output: a
  dotfiles bootstrap copies them in. If a skill looks wrong, stale or missing,
  say so and let the user re-run the bootstrap — do not edit the installed
  copy, it is replaced on the next run.
- This file, the `instructions` entry in `opencode.json(c)` and the
  `permission` / `provider.omlx` entries are generated the same way. The
  bootstrap script is the source of truth; these files are its output.
- `opencode.json(c)` is rewritten on every bootstrap run: JSONC comments and
  trailing commas are stripped. Keep notes in a separate file.
- The uber-tools CLI lives at `${HOME}/.config/uber-tools/uber-tools.sh`.
  Always call it by that full path — the `ut` alias does not exist in
  non-interactive shells.
- Commits use Conventional Commits without a scope: `feat: ...`, `fix: ...`,
  never `feat(scope): ...`.
- Bootstrap runs unattended: never prompt for input. A missing prerequisite is
  an error to report, not a question to ask the terminal.
EOF
echo "[opencode] installed DOTFILES-AGENTS.md"

CONFIG_FILE=""
for candidate in "${OPENCODE_DIR}/opencode.jsonc" "${OPENCODE_DIR}/opencode.json"; do
  if [ -f "${candidate}" ]; then
    CONFIG_FILE="${candidate}"
    break
  fi
done

if [ -z "${CONFIG_FILE}" ]; then
  CONFIG_FILE="${OPENCODE_DIR}/opencode.jsonc"
  printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "instructions": ["%s"]\n}\n' "${AGENTS_MARKER}" > "${CONFIG_FILE}"
  echo "[opencode] created ${CONFIG_FILE}"
fi

if ! command -v node >/dev/null 2>&1; then
  echo "[opencode] skipping: node not found (needed to parse JSONC)"
  exit 0
fi

WORK_FILE=$(mktemp)
SANITIZER=$(mktemp --suffix=.cjs)
SNAP_FILE=$(mktemp)
trap 'rm -f "${SANITIZER}" "${WORK_FILE}" "${SNAP_FILE}"' EXIT

cat > "${SANITIZER}" << 'EOF'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");
let out = "";
let inString = false;
let inLine = false;
let inBlock = false;
let pendingComma = false;
let wsBuf = "";
const n = src.length;
let i = 0;
while (i < n) {
  const c = src[i];
  const d = i + 1 < n ? src[i + 1] : "";
  if (inLine) {
    if (c === "\n") {
      out += c;
      inLine = false;
    }
    i++;
    continue;
  }
  if (inBlock) {
    if (c === "*" && d === "/") {
      inBlock = false;
      i += 2;
      continue;
    }
    if (c === "\n") out += c;
    i++;
    continue;
  }
  if (inString) {
    out += c;
    if (c === "\\" && d !== "") {
      out += d;
      i += 2;
      continue;
    }
    if (c === '"') inString = false;
    i++;
    continue;
  }
  if (pendingComma) {
    if (c === " " || c === "\t" || c === "\r" || c === "\n") {
      wsBuf += c;
      i++;
      continue;
    }
    if (c === "/" && d === "/") {
      i += 2;
      while (i < n && src[i] !== "\n") i++;
      if (i < n) {
        wsBuf += "\n";
        i++;
      }
      continue;
    }
    if (c === "/" && d === "*") {
      i += 2;
      while (i < n && !(src[i] === "*" && src[i + 1] === "/")) {
        if (src[i] === "\n") wsBuf += "\n";
        i++;
      }
      if (i < n) i += 2;
      continue;
    }
    if (c === "}" || c === "]") {
      pendingComma = false;
    } else {
      out += ",";
      pendingComma = false;
    }
    out += wsBuf;
    wsBuf = "";
  }
  if (c === '"') {
    inString = true;
    out += c;
    i++;
    continue;
  }
  if (c === "/" && d === "/") {
    inLine = true;
    i += 2;
    continue;
  }
  if (c === "/" && d === "*") {
    inBlock = true;
    i += 2;
    continue;
  }
  if (c === ",") {
    pendingComma = true;
    wsBuf = "";
    i++;
    continue;
  }
  out += c;
  i++;
}
fs.writeFileSync(process.argv[3], out);
EOF

node "${SANITIZER}" "${CONFIG_FILE}" "${WORK_FILE}"

if ! jq -e . "${WORK_FILE}" >/dev/null 2>&1; then
  echo "[opencode] skipping: cannot parse ${CONFIG_FILE} (invalid JSON/JSONC)"
  exit 0
fi

# Snapshot of everything this script must not touch. provider.omlx, permission
# and instructions are the only keys it is allowed to change; anything else
# that moves between here and the final write is a bug, and the write is
# refused. Taken after sanitising, so stripped JSONC comments do not count as a
# change.
#
# .provider is created by the omlx merge when the config had none, so it is
# dropped from the snapshot once omlx is stripped from it: a bare
# "provider": {} left behind by the merge is the script's own doing, not a
# hand-written key it lost. A provider object holding anything else is still
# compared in full.
SNAP_FILTER='del(.provider.omlx, .permission, .instructions) | if (.provider // {}) == {} then del(.provider) else . end'
jq -S "${SNAP_FILTER}" "${WORK_FILE}" > "${SNAP_FILE}"

if jq -e ".instructions" "${WORK_FILE}" >/dev/null 2>&1; then
  if ! jq -e ".instructions | index(\"${AGENTS_MARKER}\")" "${WORK_FILE}" >/dev/null 2>&1; then
    TMPFILE=$(mktemp)
    jq ".instructions += [\"${AGENTS_MARKER}\"]" "${WORK_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${WORK_FILE}"
    echo "[opencode] updated instructions"
  else
    echo "[opencode] instructions already configured"
  fi
else
  TMPFILE=$(mktemp)
  jq ". + { \"instructions\": [\"${AGENTS_MARKER}\"] }" "${WORK_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${WORK_FILE}"
  echo "[opencode] added instructions"
fi

if jq -e '.permission | type == "string"' "${WORK_FILE}" >/dev/null 2>&1; then
  echo "[opencode] skipping permissions: .permission is a flat string; convert to an object and rerun"
else
  TMPFILE=$(mktemp)
  jq '
    .permission = (.permission // {})
    | .permission.read = (
        if ((.permission.read // {}) | type) == "string" then .permission.read
        else (.permission.read // {}) + {
          "~/.git-credentials": "deny",
          "~/.ssh": "deny",
          "~/.ssh/*": "deny",
          "~/.config/gitlab": "deny",
          "~/.config/gitlab/*": "deny",
          "~/.config/infisical": "deny",
          "~/.config/infisical/*": "deny",
          "~/.config/gh": "deny",
          "~/.config/gh/*": "deny",
          "~/.config/glab-cli": "deny",
          "~/.config/glab-cli/*": "deny",
          "~/*.pfx": "deny"
        }
        end)
    | .permission.external_directory = (
        if ((.permission.external_directory // {}) | type) == "string" then .permission.external_directory
        else (.permission.external_directory // {}) + {
          "~/.git-credentials": "deny",
          "~/.ssh": "deny",
          "~/.ssh/**": "deny",
          "~/.config/gitlab/**": "deny",
          "~/.config/infisical/**": "deny",
          "~/.config/gh/**": "deny",
          "~/.config/glab-cli/**": "deny",
          "~/*.pfx": "deny",
          "/tmp": "allow",
          "/tmp/*": "allow",
          "/tmp/**": "allow"
        }
        end)
    | .permission.bash = (
        if ((.permission.bash // {}) | type) == "string" then .permission.bash
        else (.permission.bash // {}) + {
          "cat ~/.ssh*": "deny",
          "cat ~/.git-credentials": "deny",
          "cat ~/.config/gitlab*": "deny",
          "cat ~/.config/infisical*": "deny",
          "cat ~/.config/gh*": "deny",
          "cat ~/.config/glab-cli*": "deny",
          "cat ~/.pfx": "deny",
          "less ~/.ssh*": "deny",
          "less ~/.git-credentials": "deny",
          "less ~/.config/gitlab*": "deny",
          "less ~/.config/infisical*": "deny",
          "less ~/.config/gh*": "deny",
          "less ~/.config/glab-cli*": "deny",
          "less ~/.pfx": "deny",
          "head ~/.ssh*": "deny",
          "head ~/.git-credentials": "deny",
          "head ~/.config/gitlab*": "deny",
          "head ~/.config/infisical*": "deny",
          "head ~/.config/gh*": "deny",
          "head ~/.config/glab-cli*": "deny",
          "tail ~/.ssh*": "deny",
          "tail ~/.git-credentials": "deny",
          "tail ~/.config/gitlab*": "deny",
          "tail ~/.config/infisical*": "deny",
          "tail ~/.config/gh*": "deny",
          "tail ~/.config/glab-cli*": "deny"
        }
        end)
    ' "${WORK_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${WORK_FILE}"
  echo "[opencode] configured hard-deny permissions"
fi

# Fetch API key from Infisical. The key is written into opencode.json, which
# is sensitive; never print it.
OXMLX_API_KEY="$(fetch_secret omlx /ai-api-keys opencode)" || true

TMPFILE=$(mktemp)
jq --arg omlx_key "${OXMLX_API_KEY}" --argjson omlx '{
  "npm": "@ai-sdk/openai-compatible",
  "name": "oMLX",
  "options": {
    "baseURL": "http://localhost:11433/v1"
  },
  "models": {
    "Qwen3.8-9B-Distill-oQ4e-mtp": {
      "name": "Qwen3.8-9B-Distill-oQ4e-mtp",
      "limit": {
        "context": 262144,
        "output": 32768
      },
      "variants": {
        "high": {
          "reasoningEffort": "xhigh"
        },
        "medium": {
          "reasoningEffort": "medium"
        },
        "low": {
          "reasoningEffort": "low"
        }
      }
    },
    "Qwen3.8-27B-oQ3.5e-mtp": {
      "name": "Qwen3.8-27B-oQ3.5e-mtp",
      "limit": {
        "context": 262144,
        "output": 32768
      },
      "variants": {
        "high": {
          "reasoningEffort": "xhigh"
        },
        "medium": {
          "reasoningEffort": "medium"
        },
        "low": {
          "reasoningEffort": "low"
        }
      }
    },
    "Qwen3.6-35B-A3B-oQ4e-mtp": {
      "name": "Qwen3.6-35B-A3B-oQ4e-mtp",
      "limit": {
        "context": 262144,
        "output": 32768
      }
    }
  }
}' '.provider.omlx = ((.provider.omlx // {}) as $t | $omlx as $s | $t * $s | .models = (($t.models // {}) * $s.models) | .apiKey = $omlx_key)' "${WORK_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${WORK_FILE}"
echo "[opencode] configured omlx provider"

# --- Never destroy the user's config ---
# Everything above is additive (jq +, *, +=), so a well-behaved merge leaves
# every other key byte-identical. Prove it before overwriting; if it does not
# hold, leave the original in place instead of writing a broken config.
TMPFILE=$(mktemp)
jq -S "${SNAP_FILTER}" "${WORK_FILE}" > "${TMPFILE}"
if ! diff -u "${SNAP_FILE}" "${TMPFILE}" >/dev/null 2>&1; then
  echo "[opencode] ABORT: the merge would change ${CONFIG_FILE} outside provider.omlx / permission / instructions" >&2
  diff -u "${SNAP_FILE}" "${TMPFILE}" >&2 || true
  echo "[opencode]   ${CONFIG_FILE} was left untouched; please report this" >&2
  rm -f "${TMPFILE}"
  exit 1
fi
rm -f "${TMPFILE}"

# The config can contain provider API keys, so the backup is exactly as
# sensitive as the original and stays off-limits to agents.
cp -p "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
echo "[opencode] backed up ${CONFIG_FILE} to ${CONFIG_FILE}.bak (may hold provider keys: off-limits)"

mv "${WORK_FILE}" "${CONFIG_FILE}"
echo "[opencode] wrote ${CONFIG_FILE}"
