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
# Visual vocabulary mirrors the dotfiles' scripts/lib.sh so this cold-start stub
# and the bootstrap.sh it hands off to read as one program. Colors auto-disable
# when stderr isn't a TTY. All diagnostics go to stderr; ask() keeps stdout clean
# for command substitution.
if [[ -t 2 ]]; then
  BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
  BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  BLUE=""; GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi
header() { printf '\n%s━━ %s ━━%s\n' "$BOLD"  "$*" "$RESET" >&2; }
log()    { printf '%s•%s %s\n'        "$BLUE"   "$RESET" "$*" >&2; }
step()   { printf '  %s\n'            "$*"                    >&2; }
ok()     { printf '%s✓%s %s\n'        "$GREEN"  "$RESET" "$*" >&2; }
warn()   { printf '%s!%s %s\n'        "$YELLOW" "$RESET" "$*" >&2; }
die()    { printf '%s✗%s %s\n'        "$RED"    "$RESET" "$*" >&2; exit 1; }
have()   { command -v "$1" &>/dev/null; }

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
  header "Prerequisites · macOS"
  # Quiet Homebrew: no auto-update churn, no post-install env hints.
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
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

  # Only install what's missing — avoids brew's "already installed" warnings.
  local pkgs=() p
  for p in git gh; do have "$p" || pkgs+=("$p"); done
  if (( ${#pkgs[@]} )); then
    log "Installing ${pkgs[*]} via Homebrew…"
    brew install "${pkgs[@]}"
  else
    step "git, gh already present"
  fi
}

# ── prerequisites: Debian/Ubuntu ──────────────────────────────────────────────
prereqs_debian() {
  header "Prerequisites · Debian"
  have sudo || die "sudo is required on Debian/Ubuntu"

  # Only run apt (and its network update) for tools that aren't already present.
  # dpkg-query catches ca-certificates, which has no binary for `have` to find.
  local need=() p
  for p in git curl ca-certificates; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' \
      || need+=("$p")
  done
  if (( ${#need[@]} )); then
    log "Installing ${need[*]} via apt…"
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${need[@]}"
  else
    step "base tools already present"
  fi

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
header "GitHub"
if gh auth status &>/dev/null; then
  step "Already authenticated"
else
  log "Authenticating with GitHub…"
  step "→ gh will show a one-time code. Open the shown URL on any device"
  step "  (e.g. your phone), sign in with 1Password, and enter the code."
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth status &>/dev/null || die "GitHub authentication did not complete"

# ── ask where things go (skipped if pinned via env) ──────────────────────────
header "Dotfiles"
[[ -n "$_REPO_FROM_ENV" ]] || DOTFILES_REPO="$(ask 'GitHub repo to clone:' "$DOTFILES_REPO")"
[[ -n "$_DIR_FROM_ENV"  ]] || DOTFILES_DIR="$(ask 'Clone dotfiles to:'     "$DOTFILES_DIR")"
DOTFILES_DIR="${DOTFILES_DIR/#\~/$HOME}"   # expand a leading ~

# ── clone ─────────────────────────────────────────────────────────────────────
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
  log "Cloning $DOTFILES_REPO → $DOTFILES_DIR"
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  gh repo clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  step "Already cloned at $DOTFILES_DIR"
fi

# ── hand off to the private bootstrap ─────────────────────────────────────────
cd "$DOTFILES_DIR"
[[ -x ./bootstrap.sh ]] || die "bootstrap.sh not found or not executable in $DOTFILES_DIR"

log "Handing off to $DOTFILES_DIR/bootstrap.sh…"
exec ./bootstrap.sh "$@"
