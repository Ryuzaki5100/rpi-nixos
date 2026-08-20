#!/usr/bin/env bash
#
# first-run.sh — First-run / repair script for a freshly flashed NixOS card.
#
# On a new image the desktop activation script seeds ~/.config as root, which
# stops the desktop user from creating any new config file (apps then only
# open under sudo). This script:
#
#   1. Detects the NixOS "normal" users on the machine (uid >= 1000 with a
#      home under /home). If exactly one exists it is used directly; if there
#      are several you are asked which one(s) to fix.
#   2. Restores full ownership of each selected home to its user (fixes the
#      root-owned ~/.config class of problems).
#   3. Offers to remove orphaned home directories (/home/* whose owner no
#      longer exists in /etc/passwd, left behind after a rebuilt removed a
#      user).
#
# It requires root and re-executes itself under sudo when needed. Run it on
# first boot, or any time apps refuse to open without sudo:
#
#     ./scripts/first-run.sh
#
set -euo pipefail

msg() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Re-exec under sudo if needed. ${SUDO_USER} survives so the invoking user can
# still be defaulted to later.
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    warn "Re-running as root via sudo..."
    exec sudo "$0" "$@"
  fi
  die "must be run as root (e.g. sudo $0)"
fi

# ---------------------------------------------------------------------------
# 1. Detect normal users
# ---------------------------------------------------------------------------
users=()
while IFS=: read -r name _ uid _ _ home _; do
  [[ "$uid" -ge 1000 && "$home" == /home/* && -d "$home" ]] && users+=("$name")
done < <(getent passwd)

if [[ ${#users[@]} -eq 0 ]]; then
  die "no normal users found (uid >= 1000 with a home under /home). Nothing to fix."
fi

current="${SUDO_USER:-$USER}"
if [[ -z "$current" || ! " ${users[*]} " =~ " $current " ]]; then
  current=""
fi

selected=()
if [[ ${#users[@]} -eq 1 ]]; then
  selected=("${users[0]}")
  msg "Single user detected: ${selected[0]}"
else
  msg "Multiple users detected on this machine:"
  for i in "${!users[@]}"; do
    printf '   %d) %s%s\n' "$((i + 1))" "${users[$i]}" \
      "$([[ "${users[$i]}" == "$current" ]] && printf ' (current)' || true)"
  done
  echo
  if [[ -n "$current" ]]; then
    printf 'Which user(s) do you want to fix? [1-%d, a=all, Enter=%s]: ' \
      "${#users[@]}" "$current"
  else
    printf 'Which user(s) do you want to fix? [1-%d, a=all]: ' "${#users[@]}"
  fi
  read -r ans
  case "$ans" in
    "") [[ -n "$current" ]] && selected=("$current") || selected=("${users[0]}") ;;
    a|A) selected=("${users[@]}") ;;
    *) i=$((ans - 1))
       [[ "$ans" =~ ^[0-9]+$ && "$i" -ge 0 && "$i" -lt ${#users[@]} ]] \
         && selected=("${users[$i]}") \
         || die "invalid choice: '$ans'" ;;
  esac
fi

# ---------------------------------------------------------------------------
# 2. Fix home ownership for each selected user
# ---------------------------------------------------------------------------
for user in "${selected[@]}"; do
  home="$(getent passwd "$user" | cut -d: -f6)"
  gid="$(getent passwd "$user" | cut -d: -f4)"
  [[ -n "$home" && -d "$home" ]] || { warn "skip $user: no home dir ($home)"; continue; }

  chown "$user:$gid" "$home"
  fixed=0
  while IFS= read -r -d '' path; do
    chown -R "$user:$gid" "$path"
    printf '   fixed: %s\n' "$path"
    fixed=$((fixed + 1))
  done < <(find "$home" -mindepth 1 -maxdepth 1 ! -user "$user" -print0)

  if [[ "$fixed" -eq 0 ]]; then
    ok "$user: home is clean, nothing to fix ($home)."
  else
    ok "$user: repaired $fixed path(s) under $home."
  fi
done

# ---------------------------------------------------------------------------
# 3. Orphaned home directories (owner no longer in /etc/passwd)
# ---------------------------------------------------------------------------
orphans=()
for d in /home/*; do
  [[ -d "$d" ]] || continue
  owner_uid="$(stat -c %u "$d")"
  if ! getent passwd "$owner_uid" >/dev/null 2>&1; then
    orphans+=("$d")
  fi
done

if [[ ${#orphans[@]} -gt 0 ]]; then
  echo
  warn "Orphaned home directory(ies) without a matching user in /etc/passwd:"
  printf '   %s\n' "${orphans[@]}"
  read -r -p "Remove them? This deletes the data inside. [y/N] " ans
  if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
    for d in "${orphans[@]}"; do
      rm -rf "$d" && ok "removed $d"
    done
  else
    msg "Left orphaned homes untouched."
  fi
else
  msg "No orphaned home directories found."
fi

echo
ok "Done. You should now be able to open apps without sudo."