#!/usr/bin/env bash
set -euo pipefail

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
  - `.pfx`, `*.pfx`
  - `opencode.json`, `opencode.jsonc` (may contain provider API keys)
  - any other config or credential files
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
trap 'rm -f "${SANITIZER}" "${WORK_FILE}"' EXIT

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
          "~/*.pfx": "deny"
        }
        end)
    | .permission.bash = (
        if ((.permission.bash // {}) | type) == "string" then .permission.bash
        else (.permission.bash // {}) + {
          "cat ~/.ssh*": "deny",
          "cat ~/.git-credentials": "deny",
          "cat ~/.config/gitlab*": "deny",
          "cat ~/.config/infisical*": "deny",
          "cat ~/.pfx": "deny",
          "less ~/.ssh*": "deny",
          "less ~/.git-credentials": "deny",
          "less ~/.config/gitlab*": "deny",
          "less ~/.config/infisical*": "deny",
          "less ~/.pfx": "deny",
          "head ~/.ssh*": "deny",
          "head ~/.git-credentials": "deny",
          "tail ~/.ssh*": "deny",
          "tail ~/.git-credentials": "deny"
        }
        end)
    ' "${WORK_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${WORK_FILE}"
  echo "[opencode] configured hard-deny permissions"
fi

TMPFILE=$(mktemp)
jq --argjson omlx '{
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
}' '.provider.omlx = ((.provider.omlx // {}) as $t | $omlx as $s | $t * $s | .models = (($t.models // {}) * $s.models))' "${WORK_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${WORK_FILE}"
echo "[opencode] configured omlx provider"

mv "${WORK_FILE}" "${CONFIG_FILE}"
echo "[opencode] wrote ${CONFIG_FILE}"
