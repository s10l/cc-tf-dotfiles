---
name: genlic
description: Generate a license file for the repository
---

## What I do

1. Ask the user which license to generate. Default to MIT if not specified.
2. Ask the user for required details (e.g. copyright holder name, year). Use current year as default.
3. Generate the full license text from standard templates — never read from an existing LICENSE file.
4. Write the license to `<repo-root>/LICENSE`, overwriting any existing file.

## Supported licenses

Use standard license text from https://choosealicense.com or https://opensource.org/licenses. Common ones:

- **MIT** — requires copyright holder name
- **Apache-2.0** — requires copyright holder name
- **GPL-3.0** — requires copyright holder name
- **BSD-2-Clause** — requires copyright holder name
- **BSD-3-Clause** — requires copyright holder name
- **ISC** — requires copyright holder name
- **Unlicense** — no details needed

## Rules

- Never read content from an existing LICENSE or LICENSE.md file
- Always confirm the generated license text with the user before writing
- If no git repo is found, do nothing
- Use the repo root (git rev-parse --show-toplevel) as the output directory
