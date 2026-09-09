---
name: genreadme
description: Generate a README.md for the repository with user-confirmed content
---

## What I do

1. Understand the project before prompting:
   - `git remote get-url origin` for repo name (fall back to directory basename)
   - Check manifest files for metadata: `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `setup.py`
   - Check for build/run scripts: `Makefile`, `package.json scripts`, `Justfile`
   - Inspect the directory structure for entry points and layout
   - Never read the existing README.md

2. Generate the README using the structure below. For every user prompt, recommend a value based on what you learned about the project, and let the user confirm or override.

## Structure

```markdown
# <project-name>

<description>

## Installation

<install instructions>

## Usage

<usage examples>

## License

This project is licensed under the <license-name> - see the [LICENSE](LICENSE) file for details.
```

## Prompts (always offer a recommendation)

- **Project name**: recommend from `package.json name` or git remote, else directory basename
- **Description**: recommend from manifest `description` field, else summarize from code inspection
- **Install**: recommend from detected package manager or build system
- **Usage**: recommend from detected entry points or scripts
- **License**: auto-detect from existing `LICENSE` or `LICENSE.md` in repo root. If absent, run the `genlic` skill first, then reference the generated license.

## Rules

- Never read content from an existing README.md
- Confirm each generated section with the user before writing
- Use `git rev-parse --show-toplevel` as the output directory
- If no git repo is found, do nothing