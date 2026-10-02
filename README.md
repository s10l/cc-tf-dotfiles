# cc-tf-dotfiles

A bootstrapping toolkit for setting up development environment dotfiles, including Git credential management (GitHub/GitLab via Infisical secrets) and OpenCode skills installation.

## Installation

```bash
git clone https://github.com/s10l/cc-tf-dotfiles.git
cd cc-tf-dotfiles
./bootstrap.sh
```

## Usage

Running `bootstrap.sh` will:

1. Add `bin/infisical` to your PATH in `~/.bashrc`
2. Run all scripts in `configure/`, in filename order. A failing module does
   not stop the run: every module is attempted, failures are listed at the end,
   and the exit status is non-zero if any failed.
3. Report which modules failed, if any

The modules are:

- **Docker** (`docker.sh`): Creates one `docker context` per
  `DOCKER_CONTEXT_<NAME>_HOST` entry in `~/.config/docker/.env`, updating
  existing ones in place (`_CA`, `_CERT`, `_KEY`, `_DESCRIPTION`, `_SSH_HOST_KEY` optional;
  skips if the env file or `docker` is missing)
- **GitHub** (`github.sh`): Stores a PAT credential via Infisical secret
  `/git/ghpat`
- **GitHub CLI** (`gh.sh`): Authenticates `gh` for github.com with the same PAT
  (skips if `gh` is not installed or already authenticated)
- **GitLab** (`gitlab.sh`): Stores a PAT credential + configures mTLS (reads
  config from `~/.config/gitlab/.env`)
- **GitLab CLI** (`glab.sh`): Converts the P12 bundle to PEM, points `glab` at
  it and authenticates with Infisical secret `/git/glpat-admin`
- **SSH** (`ssh-id.sh`): Installs your `id_ed25519*` keys from Infisical path
  `/ssh` and sets a default identity in `~/.ssh/config`
- **OpenCode** (`oc-config.sh`): Installs the global agent instructions, merges
  the `omlx` provider/models and the hard-deny permissions into
  `opencode.json(c)`. The script is the source of truth; the deployed config is
  its output, and is backed up to `opencode.json(c).bak` on every run
- **Skills** (`skills.sh`): Copies skills from `configure/skills.d/` to
  `~/.config/opencode/skills/`
- **Uber Tools** (`uber-tools.sh`): Clones `https://${GITLAB_HOST}/uber/tools.git` to `~/.config/uber-tools` (or updates it), then adds its directory to PATH and an `ut` alias in both `~/.bashrc` and `~/.zshrc` (skips if `~/.config/gitlab/.env` is missing)

`./bootstrap.sh --dry-run` validates the module order and lists what would run
without touching anything.

## Development

`AGENTS.md` describes the deployment model, the module contract and how to
write a skill.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
