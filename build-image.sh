#!/usr/bin/env bash
#
# build-image.sh — Build the NixOS Raspberry Pi 5 SD image from this flake.
#
# Uses only the standard `nix build` flake interface, so it keeps working with
# current and future versions of Nix. Point it at the flake directory
# (default: this script's directory) and it produces a date-stamped image file
# under --out.
#
set -euo pipefail

FLAKE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="rpi5"
OUT_DIR="$FLAKE_DIR/images"
UPDATE=0
ACCEPT_CONFIG=1
FLASH_DEV=""
LIST_CONFIGS=0
NIX_BIN="${NIX:-nix}"

usage() {
  cat <<'EOF'
Usage: build-image.sh [OPTIONS]

Build the NixOS Raspberry Pi SD image from the flake in this directory.

Options:
  -c, --config NAME    NixOS configuration to build (default: rpi5)
  -d, --flake-dir DIR  Flake directory to build (default: this script's dir)
  -o, --out DIR        Output directory for the image (default: <flake>/images)
  -u, --update         Run 'nix flake update nixos-raspberrypi' before building
  -n, --no-accept      Do NOT pass --accept-flake-config to nix
  -l, --list-configs   List available NixOS configurations and exit
  -f, --flash DEV      After building, write the image to DEV (e.g. /dev/sda),
                       then grow the root partition and resize2fs
  -h, --help           Show this help

Examples:
  ./build-image.sh
  ./build-image.sh --update --out ~/images
  ./build-image.sh --config rpi5 --no-accept
  ./build-image.sh --list-configs
  ./build-image.sh --flash /dev/sda

The produced image can be written to an SD card with, e.g.:
  zstdcat images/nixos-image-rpi5-kernel-*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
  sudo growpart /dev/sdX 2 && sudo resize2fs /dev/sdX2
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config) CONFIG="$2"; shift 2 ;;
    -d|--flake-dir) FLAKE_DIR="$(realpath "$2")"; shift 2 ;;
    -o|--out) OUT_DIR="$2"; shift 2 ;;
    -u|--update) UPDATE=1; shift ;;
    -n|--no-accept) ACCEPT_CONFIG=0; shift ;;
    -l|--list-configs) LIST_CONFIGS=1; shift ;;
    -f|--flash) FLASH_DEV="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

msg() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==!\033[0m %s\n' "$*" >&2; }

# --- Preflight ---------------------------------------------------------------
if ! command -v "$NIX_BIN" >/dev/null 2>&1; then
  echo "error: '$NIX_BIN' not found in PATH (set NIX to override)." >&2
  exit 1
fi

if [[ ! -f "$FLAKE_DIR/flake.nix" ]]; then
  echo "error: no flake.nix found in '$FLAKE_DIR'." >&2
  exit 1
fi

if ! "$NIX_BIN" --extra-experimental-features 'nix-command flakes' --version >/dev/null 2>&1; then
  echo "error: this script requires a Nix build with flake support (nix 2.4+)." >&2
  exit 1
fi

OUT_DIR="$(realpath "$OUT_DIR")"
mkdir -p "$OUT_DIR"

# --- List available configurations (optional) ---------------------------------
if [[ "$LIST_CONFIGS" -eq 1 ]]; then
  msg "NixOS configurations in $FLAKE_DIR:"
  (cd "$FLAKE_DIR" && "$NIX_BIN" flake show --accept-flake-config --json 2>/dev/null) \
    | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for name in d.get("nixosConfigurations", {}):
        print(f"  {name}")
except Exception:
    print("  (could not parse `nix flake show` output)")
'
  exit 0
fi

avail_kb="$(df -Pk "$OUT_DIR" | awk 'NR==2 { print $4 }')"
if [[ -n "$avail_kb" && "$avail_kb" -lt $((10 * 1024 * 1024)) ]]; then
  warn "less than 10 GiB free in $OUT_DIR ($((avail_kb / 1024 / 1024)) GiB); the image/build may not fit."
fi

# --- Update flake input (optional) --------------------------------------------
if [[ "$UPDATE" -eq 1 ]]; then
  msg "Updating nixos-raspberrypi input to latest main branch..."
  (cd "$FLAKE_DIR" && "$NIX_BIN" flake update nixos-raspberrypi)
fi

# --- Build the SD image --------------------------------------------------------
ATTR=".#nixosConfigurations.$CONFIG.config.system.build.sdImage"
msg "Building $ATTR ..."
if [[ "$ACCEPT_CONFIG" -eq 1 ]]; then
  (cd "$FLAKE_DIR" && "$NIX_BIN" build --accept-flake-config "$ATTR")
else
  (cd "$FLAKE_DIR" && "$NIX_BIN" build "$ATTR")
fi

RESULT_DIR="$FLAKE_DIR/result"
if [[ ! -e "$RESULT_DIR" ]]; then
  echo "error: build finished but '$RESULT_DIR' does not exist." >&2
  exit 1
fi

# sdImage output is a directory; the image files live under $out/sd-image,
# but handle a direct *.img output as well.
IMG_DIR="$RESULT_DIR"
if [[ -d "$RESULT_DIR/sd-image" ]]; then
  IMG_DIR="$RESULT_DIR/sd-image"
fi

# --- Collect and copy the produced image file(s) -------------------------------
stamp="$(date +%Y-%m-%d)"
found=0

while IFS= read -r img; do
  [[ -n "$img" ]] || continue
  base="$(basename "$img")"
  name="${base%.img}"          # strip .img and .img.zst extension
  ext="${base#"$name"}"        # remainder, e.g. .img or .img.zst
  dest="$OUT_DIR/${name}-${stamp}${ext}"

  if [[ -e "$dest" ]]; then
    warn "skipping $dest (already exists)."
  else
    cp -a "$img" "$dest"
  fi

  printf '\033[1;32m%s\033[0m  (%s)\n' "$dest" "$(du -h "$dest" | cut -f1)"
  sha256sum "$dest" | awk '{ printf "  sha256: %s\n", $1 }'
  found=1
done < <(find "$IMG_DIR" -maxdepth 1 -type f \( -name '*.img' -o -name '*.img.zst' \))

if [[ "$found" -eq 0 ]]; then
  echo "error: no .img / .img.zst file found in $IMG_DIR." >&2
  exit 1
fi

msg "Done. Write the image to your SD card (see ./build-image.sh --help for the dd command)."

# --- Flash to a device (optional) ---------------------------------------------
if [[ -z "$FLASH_DEV" ]]; then
  exit 0
fi

if [[ "$found" -ne 1 ]]; then
  echo "error: no image file produced to flash." >&2
  exit 1
fi
IMG_FILE="$(find "$IMG_DIR" -maxdepth 1 -type f \( -name '*.img' -o -name '*.img.zst' \) | head -1)"

if [[ ! -b "$FLASH_DEV" ]]; then
  echo "error: '$FLASH_DEV' is not a block device." >&2
  exit 1
fi

for p in /dev/disk/by-id/*; do
  if [[ "$(readlink -f "$p")" == "$(readlink -f "$FLASH_DEV")" ]]; then
    echo "  detected: $p ($(basename "$p"))"
  fi
done

echo
warn "Flash '$IMG_FILE' to $FLASH_DEV ? THIS WILL WIPE EVERYTHING ON IT."
sudo -v
read -r -p "Type 'yes' to continue: " ans
if [[ "$ans" != "yes" ]]; then
  echo "aborted." >&2
  exit 1
fi

# Unmount any mounted partitions first.
for mp in $(findmnt -rn -o TARGET -S "$FLASH_DEV" 2>/dev/null); do
  msg "Unmounting $mp..."
  sudo umount "$mp"
done

msg "Flashing $FLASH_DEV..."
if [[ "$IMG_FILE" == *.zst ]]; then
  zstdcat "$IMG_FILE" | sudo dd of="$FLASH_DEV" bs=4M status=progress conv=fsync
else
  sudo dd if="$IMG_FILE" of="$FLASH_DEV" bs=4M status=progress conv=fsync
fi
sync

msg "Growing root partition and filesystem..."
sudo growpart "$FLASH_DEV" 2 || true
ROOT_PART="$FLASH_DEV"2
[[ "$FLASH_DEV" =~ [0-9]$ ]] && ROOT_PART="${FLASH_DEV}p2"
sudo e2fsck -f "$ROOT_PART" || true
sudo resize2fs "$ROOT_PART"

msg "Flash complete. Eject and boot from $FLASH_DEV."
