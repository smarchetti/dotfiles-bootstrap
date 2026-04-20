# dotfiles-bootstrap

Public cold-start script for [smarchetti/dotfiles](https://github.com/smarchetti/dotfiles).

Handles the chicken-and-egg on a fresh Mac: no git, no gh, no SSH key, no repo. Installs the minimum tools required to clone the private dotfiles repo, then hands off to its `bootstrap.sh`.

## Usage

On a fresh machine:

```sh
curl -fsSL https://raw.githubusercontent.com/smarchetti/dotfiles-bootstrap/main/init.sh | bash
```

Pass flags through to the private bootstrap:

```sh
curl -fsSL https://raw.githubusercontent.com/smarchetti/dotfiles-bootstrap/main/init.sh | bash -s -- --only stow
```

## What it does

1. Verifies macOS (14+)
2. Installs Xcode Command Line Tools
3. Installs Homebrew
4. Installs `git`, `gh`, and 1Password (app + CLI)
5. Runs `gh auth login` (HTTPS — no SSH key needed yet)
6. Clones `smarchetti/dotfiles` to `~/Development/smarchetti/dotfiles`
7. Execs the private `bootstrap.sh`

## Overrides

```sh
DOTFILES_REPO=smarchetti/dotfiles \
DOTFILES_DIR=$HOME/Development/smarchetti/dotfiles \
  bash init.sh
```

## Why public

The private dotfiles repo needs SSH keys (or an authed `gh`) to clone. This script gets you to that point. It contains no secrets, no hostnames, no profile logic — everything machine-specific lives in the private repo.
