# dotfiles-bootstrap

Public cold-start script for [smarchetti/dotfiles](https://github.com/smarchetti/dotfiles),
the private mise config that lives at `~/.config/mise`.

A fresh Mac has no git, no mise and no GitHub credential, so it cannot clone a private
repo. This script gets it there and runs the whole setup in the dotfiles README's
"New machine" section.

## Usage

One line on a fresh Mac, from an administrator account:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/smarchetti/dotfiles-bootstrap/main/init.sh)"
```

Use the `bash -c "$(curl …)"` form, not `curl … | bash`. The command-substitution form
keeps the terminal as stdin, so the sudo, GitHub and ssh-keygen prompts work.

The mise profile is detected: a Mac with its own `config.<LocalHostName>.toml` in the
dotfiles repo uses that profile, and any other Mac uses `personal`. Name one to override:

```sh
bash -c "$(curl -fsSL .../init.sh)" -- mac-mini
```

## What it does

1. Asks for your password once and keeps sudo cached for the run.
2. Installs the Xcode Command Line Tools with `softwareupdate`, with no GUI dialog.
3. Installs mise, or updates it to 2026.10.0+.
4. Logs in to GitHub with the device-code flow: open the URL on any device and enter
   the code. It also requests the ssh-key scopes that step 8 needs.
5. Runs `mise bootstrap --adopt`, which clones the dotfiles into `~/.config/mise`,
   installs Homebrew and the shared packages and tools, and links the dotfiles.
6. If the profile has App Store apps, opens the App Store and waits for you to sign in.
7. Runs `mise -E <profile> bootstrap` for the machine's own apps. `--adopt` ignores `-E`,
   so this is a second pass.
8. Creates the SSH keys `~/.ssh/config` expects, adds `id_ed25519` to GitHub as an
   authentication and a signing key, and writes `allowed_signers` and
   `~/.config/git/config.local`.
9. Clones `skills` and `claude-hud` into `~/Code/smarchetti`. Claude Code's config
   depends on both.
10. Restarts the Dock, Finder and SystemUIServer so the macOS defaults take effect,
    and prints `mise bootstrap status`.

Every step checks before acting, so rerunning after a failure picks up where it left
off. The one thing left to do afterwards is to install the `mac-mini` and `pve` public
keys from a Mac that can already reach them, once Tailscale is up.

## Overrides

| Variable | Default |
| --- | --- |
| `DOTFILES_URL` | `https://github.com/smarchetti/dotfiles.git` |
| `DOTFILES_PROFILE` | detected from `LocalHostName` (the first argument wins) |
| `GIT_NAME`, `GIT_EMAIL` | Sean's |

## Why public

The private repo needs an authenticated `gh` to clone. This script contains no secrets
and no hostnames; profiles and everything else machine-specific live in the private repo.
