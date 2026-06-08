#!/usr/bin/env bash
#
# Public cold-start bootstrap for Sean Marchetti's dotfiles.
#
# Run on a fresh macOS or Debian/Ubuntu machine:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/smarchetti/dotfiles-bootstrap/main/init.sh)"
#
# Forward args to the dotfiles bootstrap.sh (e.g. pick a profile, skip confirm):
#
#   bash -c "$(curl -fsSL .../init.sh)" -- work -y
#
# Must be run via `bash -c "$(curl …)"` (not `curl … | bash`) so the shell
# keeps the terminal as stdin and every prompt — GitHub login, the path
# questions, and bootstrap.sh's profile picker — works.
#
# What it does: installs the minimum tools to clone the private dotfiles repo,
# authenticates GitHub via device-code flow (approve on your phone), clones the
# repo, then hands off to its bootstrap.sh.
#
set -euo pipefail

# ── config — env vars pin a value and skip its prompt ───────────────────────
_REPO_FROM_ENV="${DOTFILES_REPO+yes}"
_DIR_FROM_ENV="${DOTFILES_DIR+yes}"
DOTFILES_REPO="${DOTFILES_REPO:-smarchetti/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Development/smarchetti/dotfiles}"
MIN_MACOS_MAJOR=14

# ── helpers ─────────────────────────────────────────────────────────────────
log()  { printf '\033[1;34m[init]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" &>/dev/null; }

# ask <prompt> <default> -> echoes the answer
ask() {
  local prompt="$1" default="$2" ans
  read -rp "$prompt [$default]: " ans || ans=""
  printf '%s' "${ans:-$default}"
}

# ── detect OS ───────────────────────────────────────────────────────────────
OS=""
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)
    if [[ -f /etc/debian_version ]] || grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null; then
      OS=debian
    fi
    ;;
esac
[[ -n "$OS" ]] || die "Unsupported OS — this bootstrap handles macOS and Debian/Ubuntu."

# ── prerequisites: macOS ────────────────────────────────────────────────────
prereqs_macos() {
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= MIN_MACOS_MAJOR )) || die "macOS ${MIN_MACOS_MAJOR}+ required (found ${major})"

  if ! xcode-select -p &>/dev/null; then
    log "Installing Xcode Command Line Tools (a GUI prompt will appear)…"
    xcode-select --install || true
    read -rp "Press Enter once the CLT install completes… "
    xcode-select -p &>/dev/null || die "CLT install did not complete"
  fi

  if ! have brew; then
    log "Installing Homebrew…"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew   ]]; then eval "$(/usr/local/bin/brew shellenv)"
  else die "brew not found on PATH after install"
  fi

  log "Installing git, gh…"
  brew install git gh
}

# ── prerequisites: Debian/Ubuntu ──────────────────────────────────────────────
prereqs_debian() {
  have sudo || die "sudo is required on Debian/Ubuntu"

  log "Installing base tools via apt…"
  sudo apt-get update -qq
  sudo apt-get install -y -qq git curl ca-certificates

  # GitHub CLI — add the official apt repo if gh isn't already present.
  if ! have gh; then
    log "Adding the GitHub CLI apt repo…"
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq gh
  fi
}

case "$OS" in
  macos)  prereqs_macos ;;
  debian) prereqs_debian ;;
esac

# ── GitHub auth — device-code flow (approve on your phone) ───────────────────
# Works the same headless or with a GUI: gh prints a one-time code; open the
# URL on any device, sign in (1Password), enter the code. This also sets up the
# git credential helper, so later HTTPS git operations stay authenticated.
if ! gh auth status &>/dev/null; then
  log "Authenticating with GitHub…"
  log "  → gh will show a one-time code. Open the shown URL on any device"
  log "    (e.g. your phone), sign in with 1Password, and enter the code."
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth status &>/dev/null || die "GitHub authentication did not complete"

# ── ask where things go (skipped if pinned via env) ──────────────────────────
[[ -n "$_REPO_FROM_ENV" ]] || DOTFILES_REPO="$(ask 'GitHub repo to clone:' "$DOTFILES_REPO")"
[[ -n "$_DIR_FROM_ENV"  ]] || DOTFILES_DIR="$(ask 'Clone dotfiles to:'     "$DOTFILES_DIR")"
DOTFILES_DIR="${DOTFILES_DIR/#\~/$HOME}"   # expand a leading ~

# ── clone ─────────────────────────────────────────────────────────────────────
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
  log "Cloning $DOTFILES_REPO → $DOTFILES_DIR"
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  gh repo clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  log "Dotfiles already cloned at $DOTFILES_DIR"
fi

# ── hand off to the private bootstrap ─────────────────────────────────────────
cd "$DOTFILES_DIR"
[[ -x ./bootstrap.sh ]] || die "bootstrap.sh not found or not executable in $DOTFILES_DIR"

log "Handing off to $DOTFILES_DIR/bootstrap.sh…"
exec ./bootstrap.sh "$@"
