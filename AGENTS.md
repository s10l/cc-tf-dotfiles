# Agent Instructions

## What this repository is

A dotfiles repository for a development workstation. There is no application
here: nothing is built, packaged or served. The output of this repo is the
*state of someone's machine* — files written into `$HOME`, global `git config`
entries, and agent configuration.

Consequences:

- No build, no test suite, no lint config, no CI. Verification means running
  the scripts and looking at what they changed.
- Every change is a change to someone's `$HOME`. Ask before running
  `./bootstrap.sh`; never run it just to see what happens.
- Nothing may read, write or log a secret.

## Layout

| Path | Purpose |
| --- | --- |
| `bootstrap.sh` | The only entry point. |
| `lib/common.sh` | Shared helpers, sourced by the modules. |
| `configure/*.sh` | One module per file, applied on every run. |
| `configure/skills.d/<skill>/SKILL.md` | Source of an agent skill. |
| `bin/<tool>/` | Executables put on `PATH`. |

## How deployment works

`./bootstrap.sh` does three things:

1. Appends `bin/infisical` to `PATH` in `~/.bashrc` (guarded by `grep -qF`, so
   it happens once).
2. Discovers every `configure/*.sh` and runs it, in filename order.
3. Prints a summary and exits non-zero if any module failed.

There is no manifest and no file graph: **a module is registered by existing at
`configure/<name>.sh`.** Creating the file is the entire registration step.

Three rules follow:

- **A failing module must not stop the run.** Each module's exit status is
  collected and reported at the end, so an unreachable secret manager still
  leaves skills and agent config applied. Do not reintroduce a hard failure
  part-way through.
- **A module that skips exits 0** and says why with a `[tag] skipping:` line.
  Reserve a non-zero exit for "this should have worked and did not".
- **The run is unattended.** No module may prompt for input. Anything that
  could stop for input — git asking for a username above all — has to fail with
  an actionable message instead. `GIT_TERMINAL_PROMPT=0` is exported for this
  reason.

`./bootstrap.sh --dry-run` validates module order and lists what would run
without touching `$HOME`. Use it to check a change.

### Ordering

Modules run in filename order. A module that needs another to have run first
declares it in a header, and `bootstrap.sh` refuses to start if the resulting
order would be wrong:

```bash
# bootstrap-requires: gitlab.sh
```

Never rely on letters happening to sort correctly.

### PATH is a contract

The `PATH` entry points at the absolute path of the checkout, on purpose: the
tooling is expected at exactly that location. Do not make it relative, and do
not relocate the checkout without updating it.

## Writing a module

Follow the shape of an existing one:

```bash
#!/usr/bin/env bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "${MAIN_DIR}/lib/common.sh"

tag=example
# ...
echo "[${tag}] installed ..."
```

- Prefix all output with `[tag]`.
- Skip with `[tag] skipping: <reason>` and `exit 0` when an optional
  prerequisite is missing (`command -v jq`, a config file only some machines
  have).
- Make writes idempotent: `grep -qF` before appending to a file, or write a
  temp file and `mv` it into place.
- Take secrets from `fetch_secret <name> <path> <tag>` in `lib/common.sh`,
  never from a secret file directly. It rejects a fetch that fails *and* one
  that returns empty — which is what stops an empty token being written out as
  `https://oauth2:@host`.

## Skills

Skills are the main thing configured here. A skill is a directory under
`configure/skills.d/` holding a `SKILL.md`; supporting files can live beside it
in `reference/`. `configure/skills.sh` copies each one to
`~/.config/opencode/skills/<name>/`, replacing what is there.

To add one: create `configure/skills.d/<name>/SKILL.md`, then run
`bash configure/skills.sh`. Editing a skill in the repo has no effect until it
is reinstalled — the installed copy is what runs.

Skills are **copied, never symlinked**, for security reasons: the installed
tree is loaded as agent instructions, and it must not be able to change
because something edited a working tree. Do not "optimise" this into symlinks.
The `rm -rf` in `skills.sh` is safe for the same reason: it only ever deletes a
copy that is about to be replaced.

### Writing a skill

- YAML frontmatter with `name` (matching the directory) and a `description`
  that says when to reach for it.
- `## What I do` — numbered, imperative steps with the exact commands.
- `## When to use me` — the trigger, in the user's words.
- `## Rules` — boundaries, including what must never happen unasked.
- `## Output format notes` — when the skill parses command output, show the
  shape and say which column or line matters.

Write for a shell with no profile loaded: absolute paths, not aliases, and do
not assume environment variables are set. Prefer read-only actions; a skill
that changes remote state must say so and wait to be asked.

## Agent configuration is generated

The module that configures the coding agent owns
`~/.config/opencode/DOTFILES-AGENTS.md` and patches `opencode.json(c)`. That
script is the source of truth; the deployed files are its output.

- Never edit a deployed file to make a change stick — it is overwritten on the
  next run. Change the script.
- Never read `opencode.json(c)`: it can hold provider API keys.
- Keep merges additive. Before overwriting, the script compares everything
  except the keys it owns and refuses to write if anything else moved, so a
  hand-written config survives a bootstrap. Keep it that way.
- Comments and trailing commas in `opencode.jsonc` do not survive a run — it
  is rewritten as plain JSON. The previous version, comments intact, is kept
  next to it as a `.bak`, which is exactly as sensitive: off-limits too.

## Secrets

- Never read, print or commit a secret: no `.env` files, no
  `~/.git-credentials`, no `~/.ssh`, no certificate or key files.
- If the shape of a secret is needed to finish a task, ask for it.
- Secrets come from Infisical at run time. Reference paths in code, never
  values.

## Before you commit

- `bash -n <script>` on every script you touched.
- `shellcheck` if installed — there is no enforced lint config, so this is on
  you.
- `./bootstrap.sh --dry-run`.
- Run the one module you changed (`bash configure/<name>.sh`) instead of the
  whole bootstrap, and say what it will touch first.
- Commits: Conventional Commits, no scope — `feat: ...`, `fix: ...`, never
  `feat(scope): ...`.
