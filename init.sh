#!/usr/bin/env bash
#
# Public bootstrap for Sean Marchetti's dotfiles.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/smarchetti/dotfiles-bootstrap/main/init.sh | bash
#
# Handles the cold-start problem: installs the minimum tools needed to clone
# the private dotfiles repo, then hands off to its bootstrap.sh.
#
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-smarchetti/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Development/smarchetti/dotfiles}"
MIN_MACOS_MAJOR=14

log()  { printf '\033[1;34m[init]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- preflight ----------------------------------------------------------
[[ "$(uname)" == "Darwin" ]] || die "macOS only (for now)"

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( macos_major < MIN_MACOS_MAJOR )); then
  die "macOS ${MIN_MACOS_MAJOR}+ required (found ${macos_major})"
fi

# ---- step 1: Xcode Command Line Tools -----------------------------------
if ! xcode-select -p &>/dev/null; then
  log "Installing Xcode Command Line Tools (a GUI prompt will appear)…"
  xcode-select --install || true
  read -rp "Press enter once the CLT install completes… "
  xcode-select -p &>/dev/null || die "CLT install did not complete"
fi

# ---- step 2: Homebrew ---------------------------------------------------
if ! command -v brew &>/dev/null; then
  log "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
else
  die "brew not found on PATH after install"
fi

# ---- step 3: minimum tools to clone the repo ----------------------------
log "Installing git, gh, 1Password…"
brew install git gh
brew install --cask 1password 1password-cli || \
  warn "1Password cask install skipped or already present"

# ---- step 4: GitHub auth ------------------------------------------------
if ! gh auth status &>/dev/null; then
  log "Authenticating with GitHub (browser will open)…"
  gh auth login --web --git-protocol https --hostname github.com
fi

# ---- step 5: clone dotfiles --------------------------------------------
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
  log "Cloning $DOTFILES_REPO → $DOTFILES_DIR"
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  gh repo clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  log "Dotfiles already cloned at $DOTFILES_DIR"
fi

# ---- step 6: hand off to private bootstrap ------------------------------
cd "$DOTFILES_DIR"
[[ -x ./bootstrap.sh ]] || die "bootstrap.sh not found or not executable in $DOTFILES_DIR"

log "Handing off to $DOTFILES_DIR/bootstrap.sh…"
exec ./bootstrap.sh "$@"
