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
2. Run all scripts in `configure/`:
   - **GitHub**: Stores a PAT credential via Infisical secret `/git/ghpat`
   - **GitLab**: Stores a PAT credential + configures mTLS (reads config from `~/.config/gitlab/.env`)
   - **Skills**: Copies skills from `configure/skills.d/` to `~/.config/opencode/skills/`

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
