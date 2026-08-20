#!/usr/bin/env bash
#
# setup.sh — First-run setup for a freshly cloned rpi-nixos repo.
#
# Interactive prompts fill in the per-device files that the NixOS config reads:
#   local.nix    hostname, username, ssh key, wifi ssid
#   secrets.nix  initial password, wifi psk
#
# Then it runs `nixos-rebuild switch` to build the full desktop (rpi5).
# Both generated files are gitignored and marked intent-to-add + skip-worktree,
# so Nix can see them during evaluation but they can never be committed.
#
usage() {
  cat <<'EOF'
Usage: setup.sh [OPTIONS]

Prompts for your personal NixOS configuration, writes `local.nix` and
`secrets.nix` into this repo, then runs:

    nixos-rebuild switch --flake .#rpi5

Options:
  -n, --no-rebuild   Write config files only; skip nixos-rebuild switch
  -c, --config NAME  NixOS configuration to build (default: rpi5)
  -h, --help         Show this help
EOF
}

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="rpi5"
REBUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--no-rebuild) REBUILD=0; shift ;;
    -c|--config) CONFIG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# --- Nix string escaping: backslash and double-quote (and ${) ----------------
nix_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\${/\\\${/g'
}

ask() {
  local prompt="$1" var="$2" default="$3"
  local ans
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " ans
  else
    read -r -p "$prompt: " ans
  fi
  printf -v "$var" '%s' "${ans:-$default}"
}

ask_secret() {
  local prompt="$1" var="$2"
  local a b
  while :; do
    read -r -s -p "$prompt: " a; echo
    read -r -s -p "Confirm $prompt: " b; echo
    if [[ -z "$a" ]]; then
      echo "password cannot be empty" >&2
      continue
    fi
    if [[ "$a" != "$b" ]]; then
      echo "password mismatch, try again" >&2
      continue
    fi
    printf -v "$var" '%s' "$a"
    return
  done
}

msg() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==!\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
msg "rpi-nixos first-run setup"
# ---------------------------------------------------------------------------

ask "Machine hostname" HOSTNAME ryuzakipi
ask "Desktop username" USERNAME user
ask_secret "Initial password for '$USERNAME'" USER_PASSWORD
ask "ssh public key (optional, empty to skip)" SSH_KEY ""
ask "Wi-Fi SSID (empty to skip wifi profile)" WIFI_SSID ""
if [[ -n "$WIFI_SSID" ]]; then
  ask_secret "Wi-Fi password for '$WIFI_SSID'" WIFI_PSK
fi

# --- Guard: username must be a valid NixOS user name --------------------------
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_]*$ ]]; then
  echo "error: '$USERNAME' is not a valid username (lowercase letters/digits/_)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Write local.nix
# ---------------------------------------------------------------------------
if [[ -n "$SSH_KEY" ]]; then
  SSH_KEY_NIX="\"$(nix_escape "$SSH_KEY")\""
else
  SSH_KEY_NIX="null"
fi

cat > "$REPO_DIR/local.nix" <<EOF
{
  hostName = "$(nix_escape "$HOSTNAME")";
  userName = "$(nix_escape "$USERNAME")";
  sshKey = ${SSH_KEY_NIX};
  wifi = {
    ssid = "$(nix_escape "$WIFI_SSID")";
  };
}
EOF

# ---------------------------------------------------------------------------
# Write secrets.nix
# ---------------------------------------------------------------------------
if [[ -n "$WIFI_PSK" ]]; then
  WIFI_PSK_NIX="\"$(nix_escape "$WIFI_PSK")\""
else
  WIFI_PSK_NIX="null"
fi

cat > "$REPO_DIR/secrets.nix" <<EOF
{
  userPassword = "$(nix_escape "$USER_PASSWORD")";
  wifiPsk = ${WIFI_PSK_NIX};
}
EOF

msg "Wrote local.nix and secrets.nix"

# --- Make Nix able to see the gitignored files, without ever committing them ---
# git add -N (intent-to-add) makes the git flake-fetcher include them during
# evaluation; --skip-worktree hides them from git add -A / git commit.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add -N -f -- local.nix secrets.nix
  git update-index --skip-worktree -- local.nix secrets.nix
  msg "Marked local.nix + secrets.nix intent-to-add (safe from committing)."
else
  warn "Not a git work tree; skipping git bookkeeping. local.nix/secrets.nix are written."
fi

# ---------------------------------------------------------------------------
if [[ "$REBUILD" -eq 0 ]]; then
  msg "Done. Run the rebuild yourself when ready:"
  echo "  sudo nixos-rebuild switch --flake $REPO_DIR#$CONFIG"
  exit 0
fi

if ! command -v nixos-rebuild >/dev/null 2>&1; then
  echo "error: nixos-rebuild not found in PATH. Run with --no-rebuild and" >&2
  echo "       rebuild once nix is available." >&2
  exit 1
fi

warn "About to rebuild the full system. This downloads/builds the desktop"
warn "closure and can take a while; the current image will not lose data."
read -r -p "Continue with 'sudo nixos-rebuild switch --flake .#$CONFIG'? [y/N] " ok
if [[ "${ok,,}" != "y" && "${ok,,}" != "yes" ]]; then
  echo "aborted. Run it manually: sudo nixos-rebuild switch --flake $REPO_DIR#$CONFIG" >&2
  exit 0
fi

msg "Rebuilding: sudo nixos-rebuild switch --flake .#$CONFIG"
sudo nixos-rebuild switch --flake "$REPO_DIR#$CONFIG"
msg "Done. Reboot into your new desktop, or start it with uwsm start hyprland."