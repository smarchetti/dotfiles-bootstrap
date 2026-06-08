# dotfiles-bootstrap

Public cold-start script for [smarchetti/dotfiles](https://github.com/smarchetti/dotfiles).

Solves the chicken-and-egg on a fresh machine: no git, no gh, no SSH key, no repo. Installs the minimum tools to clone the private dotfiles repo, authenticates GitHub, clones, then hands off to its `bootstrap.sh`.

## Usage

One line on a fresh **macOS** or **Debian/Ubuntu** machine:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/smarchetti/dotfiles-bootstrap/main/init.sh)"
```

> Use the `bash -c "$(curl …)"` form, **not** `curl … | bash`. With the
> command-substitution form the shell keeps the terminal as stdin, so every
> interactive prompt — GitHub login, the path questions, and `bootstrap.sh`'s
> profile picker — works.

Forward arguments to `bootstrap.sh` (e.g. preselect a profile, skip its confirm):

```sh
bash -c "$(curl -fsSL .../init.sh)" -- work -y
```

## What it does

1. Detects the OS (macOS or Debian/Ubuntu)
2. Installs the bare minimum to clone + authenticate:
   - **macOS** — Xcode CLT, Homebrew, then `git` + `gh`
   - **Debian/Ubuntu** — `git` + `gh` via apt (adds the GitHub CLI apt repo if needed)
3. Authenticates GitHub via **device-code flow** — `gh` shows a one-time code;
   open the URL on any device (your phone), sign in with 1Password, enter the
   code. No browser needed on the target machine, so this works headless too.
4. Asks where to clone (repo + destination, with defaults)
5. Clones the dotfiles repo over HTTPS (using the `gh` token)
6. Execs the private `bootstrap.sh`, attached to your terminal

Everything past the clone — 1Password, GUI apps, the full package set, SSH key
setup, and profile selection — is owned by the dotfiles repo, not this script.

## Overrides

Pin the repo and/or destination via env vars to skip those prompts:

```sh
DOTFILES_REPO=smarchetti/dotfiles \
DOTFILES_DIR=$HOME/Development/smarchetti/dotfiles \
  bash -c "$(curl -fsSL .../init.sh)"
```

## Why public

The private dotfiles repo needs an authed `gh` (or SSH keys) to clone. This script gets you to that point and nothing more. It contains no secrets, no hostnames, no profile logic — everything machine-specific lives in the private repo.
