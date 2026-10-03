#!/usr/bin/env bash
#
# Public cold-start bootstrap for Sean Marchetti's dotfiles.
#
# Run on a fresh Mac:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/smarchetti/dotfiles-bootstrap/main/init.sh)"
#
# Pick the mise profile instead of detecting it from the hostname:
#
#   bash -c "$(curl -fsSL .../init.sh)" -- personal
#
# Must be run via `bash -c "$(curl …)"` (not `curl … | bash`) so the shell
# keeps the terminal as stdin and every prompt (sudo, GitHub login, ssh-keygen
# passphrases) works.
#
# What it does: installs the Command Line Tools and mise, authenticates GitHub
# via device-code flow (approve on your phone), adopts the private dotfiles repo
# with `mise bootstrap --adopt`, applies the machine's profile, then sets up
# what stays on the machine (SSH keys, signing, the repos Claude Code needs).
# Every step checks first, so rerunning it after a failure is safe.
#
set -euo pipefail

# ── config: env vars override ───────────────────────────────────────────────
DOTFILES_URL="${DOTFILES_URL:-https://github.com/smarchetti/dotfiles.git}"
DOTFILES_PROFILE="${1:-${DOTFILES_PROFILE:-}}"
GIT_NAME="${GIT_NAME:-Sean Marchetti}"
GIT_EMAIL="${GIT_EMAIL:-sean.marchetti@gmail.com}"
CODE_REPOS=(smarchetti/skills smarchetti/claude-hud)   # cloned to ~/Code/<owner>/<repo>
MIN_MISE=2026.10.0   # first release that installs tapped casks (Orca)
MIN_MACOS_MAJOR=14
GH_SCOPES=admin:public_key,admin:ssh_signing_key       # for `gh ssh-key add`

MISE="$HOME/.local/bin/mise"
MISE_DIR="$HOME/.config/mise"

# ── helpers ─────────────────────────────────────────────────────────────────
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
pause()  { read -rp "  $* Press Enter to continue… " _ || true; }

# Before bootstrap there is no gh on PATH; mise runs one. Afterwards use
# Homebrew's, which the repo's git credential helper points at.
gh() {
  if [[ -x /opt/homebrew/bin/gh ]]; then /opt/homebrew/bin/gh "$@"
  else "$MISE" exec gh@latest -- gh "$@"
  fi
}

[[ "$(uname -s)" == Darwin ]] || die "This bootstrap is macOS only."
(( "$(sw_vers -productVersion | cut -d. -f1)" >= MIN_MACOS_MAJOR )) \
  || die "macOS ${MIN_MACOS_MAJOR}+ required"

# ── sudo, once ──────────────────────────────────────────────────────────────
# The CLT install and Homebrew's NONINTERACTIVE installer both need sudo; the
# latter fails rather than prompting, so cache credentials now and keep them warm.
header "sudo"
sudo -v || die "sudo is required (use an administrator account)"
while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done 2>/dev/null &

# ── Command Line Tools ──────────────────────────────────────────────────────
header "Command Line Tools"
if xcode-select -p &>/dev/null; then
  step "Already installed"
else
  # The trigger file makes softwareupdate list the CLT package, so it installs
  # without the GUI dialog (and works over ssh). Labels sort by version.
  clt_trigger=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  touch "$clt_trigger"
  clt_label="$(softwareupdate -l 2>/dev/null \
    | sed -n 's/^\* Label: \(Command Line Tools for Xcode.*\)/\1/p' | sort -V | tail -1)"
  if [[ -n "$clt_label" ]]; then
    log "Installing ${clt_label}…"
    sudo softwareupdate -i "$clt_label" || { rm -f "$clt_trigger"; die "CLT install failed"; }
    rm -f "$clt_trigger"
  else
    rm -f "$clt_trigger"
    warn "softwareupdate did not offer the CLT; falling back to the installer dialog"
    xcode-select --install || true
    pause "Finish the Command Line Tools install."
  fi
  if ! xcode-select -p &>/dev/null && [[ -d /Library/Developer/CommandLineTools ]]; then
    sudo xcode-select --switch /Library/Developer/CommandLineTools
  fi
  xcode-select -p &>/dev/null || die "CLT install did not complete"
  ok "Installed"
fi

# ── mise ────────────────────────────────────────────────────────────────────
header "mise"
if [[ ! -x "$MISE" ]]; then
  log "Installing mise…"
  mise_installer="$(mktemp)"
  curl -fsSL https://mise.run -o "$mise_installer" || { rm -f "$mise_installer"; die "mise download failed"; }
  sh "$mise_installer"
  rm -f "$mise_installer"
fi
mise_version="$("$MISE" --version | awk '{print $1}')"
if [[ "$(printf '%s\n%s\n' "$MIN_MISE" "$mise_version" | sort -V | head -1)" != "$MIN_MISE" ]]; then
  log "Updating mise $mise_version (need $MIN_MISE+)…"
  "$MISE" self-update -y
fi
ok "$("$MISE" --version | awk '{print $1}')"

# mise runs bootstrap hooks with this shell's PATH and adds none of its tools, so
# put the shims and Homebrew on it now, as zprofile will in later shells. Without
# them the post-tools hooks miss node (pi), go, skills and jq. Neither directory
# needs to exist yet; bootstrap creates both.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

# ── GitHub ──────────────────────────────────────────────────────────────────
# Device-code flow: gh prints a one-time code; open the URL on any device and
# enter it. The ssh-key scopes are requested now so step 7 needs no second login.
header "GitHub"
if gh auth status --hostname github.com &>/dev/null; then
  step "Already authenticated"
  scopes="$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: //p')"
  if [[ "$scopes" != *admin:public_key* || "$scopes" != *admin:ssh_signing_key* ]]; then
    log "Adding the ssh-key scopes…"
    gh auth refresh --hostname github.com --scopes "$GH_SCOPES"
  fi
else
  log "Authenticating with GitHub…"
  step "→ gh will show a one-time code. Open the URL on any device and enter it."
  gh auth login --hostname github.com --git-protocol https --web --scopes "$GH_SCOPES"
fi
gh auth status --hostname github.com &>/dev/null || die "GitHub authentication did not complete"
gh auth setup-git --hostname github.com
git ls-remote "$DOTFILES_URL" HEAD &>/dev/null || die "This account cannot read $DOTFILES_URL"
ok "Authenticated"

# ── dotfiles ────────────────────────────────────────────────────────────────
header "Dotfiles"
if [[ -d "$MISE_DIR/.git" ]]; then
  step "Already cloned at $MISE_DIR"
else
  # gh login writes its own config.yml; bootstrap links the repo's in its place.
  gh_config="$HOME/.config/gh/config.yml"
  if [[ -f "$gh_config" && ! -L "$gh_config" ]]; then
    gh_backup="$(mktemp "$gh_config.before-dotfiles.XXXXXX")"
    mv "$gh_config" "$gh_backup"
    step "Saved GitHub CLI preferences to $gh_backup"
  fi
  # --adopt clones into ~/.config/mise and applies config.toml. It ignores -E,
  # so the profile is a second pass below.
  log "Adopting ${DOTFILES_URL}…"
  "$MISE" bootstrap --adopt "$DOTFILES_URL"
fi

# ── profile ─────────────────────────────────────────────────────────────────
# A machine with its own config.<LocalHostName>.toml uses that profile; any
# other Mac is the personal MacBook.
if [[ -z "$DOTFILES_PROFILE" ]]; then
  host="$(scutil --get LocalHostName)"
  if [[ -f "$MISE_DIR/config.$host.toml" ]]; then DOTFILES_PROFILE="$host"
  else DOTFILES_PROFILE=personal
  fi
fi
[[ -f "$MISE_DIR/config.$DOTFILES_PROFILE.toml" ]] \
  || die "No config.$DOTFILES_PROFILE.toml in $MISE_DIR"
header "Profile · $DOTFILES_PROFILE"

if grep -q '^[^#]*"mas:' "$MISE_DIR/config.$DOTFILES_PROFILE.toml"; then
  log "This profile installs App Store apps; Apple has no CLI sign-in."
  open -a "App Store" || true
  pause "Sign in to the App Store (skip if already signed in)."
fi
"$MISE" -E "$DOTFILES_PROFILE" bootstrap

# ── machine-local setup ─────────────────────────────────────────────────────
# SSH keys and the git identity never enter the repo. ~/.ssh/config (linked)
# expects these key names.
header "SSH keys and signing"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
host="$(scutil --get LocalHostName)"
for key in id_ed25519 id_ed25519_mac-mini id_ed25519_pve; do
  if [[ -f "$HOME/.ssh/$key" ]]; then
    step "$key exists"
  else
    comment="$host"; [[ "$key" == id_ed25519 ]] && comment="$GIT_EMAIL"
    log "Generating $key (enter a passphrase, or leave it empty)…"
    ssh-keygen -t ed25519 -f "$HOME/.ssh/$key" -C "$comment"
  fi
done

pub="$(cut -d' ' -f1,2 "$HOME/.ssh/id_ed25519.pub")"
for type in authentication signing; do
  if gh api "user/$([[ $type == signing ]] && echo ssh_signing_keys || echo keys)" \
       --jq '.[].key' | grep -qxF "$pub"; then
    step "GitHub already has id_ed25519 as a $type key"
  else
    gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --type "$type" --title "$host"
  fi
done

signers="$HOME/.ssh/allowed_signers"
grep -qF "$pub" "$signers" 2>/dev/null \
  || printf '%s %s\n' "$GIT_EMAIL" "$(cat "$HOME/.ssh/id_ed25519.pub")" >> "$signers"

git_local="$HOME/.config/git/config.local"
git config -f "$git_local" user.name       "$GIT_NAME"
git config -f "$git_local" user.email      "$GIT_EMAIL"
git config -f "$git_local" user.signingkey "$HOME/.ssh/id_ed25519.pub"
ok "Signing set up"

header "Code"
for repo in "${CODE_REPOS[@]}"; do
  dest="$HOME/Code/$repo"
  if [[ -d "$dest/.git" ]]; then step "$repo already cloned"
  else mkdir -p "$(dirname "$dest")" && gh repo clone "$repo" "$dest"
  fi
done

# ── done ────────────────────────────────────────────────────────────────────
header "Status"
"$MISE" -E "$DOTFILES_PROFILE" bootstrap status || true
ok "Done. Open a new terminal."
step "Pass -E $DOTFILES_PROFILE to every later mise bootstrap command."
step "Once Tailscale is up, from a Mac that can already reach them:"
step "  ssh-copy-id -i ~/.ssh/id_ed25519_mac-mini.pub mac-mini   (likewise pve)"
