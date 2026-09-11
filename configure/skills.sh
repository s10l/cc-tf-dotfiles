#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${SCRIPT_DIR}/skills.d"
SKILLS_DST="${HOME}/.config/opencode/skills"

if [ ! -d "${SKILLS_SRC}" ]; then
  echo "[skills] skipping: ${SKILLS_SRC} not found"
  exit 0
fi

mkdir -p "${SKILLS_DST}"

for skill_dir in "${SKILLS_SRC}"/*/; do
  [ -d "${skill_dir}" ] || continue
  skill_name="$(basename "${skill_dir}")"

  if [ ! -f "${skill_dir}SKILL.md" ]; then
    echo "[skills] skipping ${skill_name}: SKILL.md not found"
    continue
  fi

  rm -rf "${SKILLS_DST}/${skill_name}"
  cp -R "${skill_dir}" "${SKILLS_DST}/${skill_name}"
  echo "[skills] installed ${skill_name}"
done
