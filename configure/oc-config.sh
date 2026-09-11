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

if ! jq -e . "${CONFIG_FILE}" >/dev/null 2>&1; then
  echo "[opencode] skipping: cannot parse ${CONFIG_FILE} (JSONC comments?)"
  exit 0
fi

if jq -e ".instructions" "${CONFIG_FILE}" >/dev/null 2>&1; then
  if ! jq -e ".instructions | index(\"${AGENTS_MARKER}\")" "${CONFIG_FILE}" >/dev/null 2>&1; then
    TMPFILE=$(mktemp)
    jq ".instructions += [\"${AGENTS_MARKER}\"]" "${CONFIG_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${CONFIG_FILE}"
    echo "[opencode] updated instructions"
  else
    echo "[opencode] instructions already configured"
  fi
else
  TMPFILE=$(mktemp)
  jq ". + { \"instructions\": [\"${AGENTS_MARKER}\"] }" "${CONFIG_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${CONFIG_FILE}"
  echo "[opencode] added instructions"
fi

if jq -e '.permission | type == "string"' "${CONFIG_FILE}" >/dev/null 2>&1; then
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
    ' "${CONFIG_FILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${CONFIG_FILE}"
  echo "[opencode] configured hard-deny permissions"
fi
