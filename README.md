# rpi-nixos

Declarative **NixOS** for the **Raspberry Pi 5** (and any other Pi you add),
powered by the [`nvmd/nixos-raspberrypi`](https://github.com/nvmd/nixos-raspberrypi)
installer. The image boots straight into a **Hyprland + Noctalia v5** desktop.

## What's here

```
flake.nix              Flake: nvmd installer + Noctalia v5 (upstream flake)
configuration.nix      Host config: ryuzakipi (user, ssh, wifi, /etc/nixos baking)
modules/desktop.nix    Hyprland + Noctalia + greetd autologin
modules/noctalia.toml  Seed config for the Noctalia shell (→ ~/.config/noctalia/config.toml)
modules/hyprland.conf  Seed config for Hyprland (→ ~/.config/hypr/hyprland.conf)
build-image.sh         Build the image; optionally flash + grow an SD card
FIRST_BOOT.md          First-boot guide for a freshly flashed card
```

## Build the image

On any machine with Nix flakes:

```sh
./build-image.sh              # builds the rpi5 image into ./images/
./build-image.sh --list-configs
./build-image.sh --config rpi5 --out ~/images
```

### Flash + grow an SD card

```sh
./build-image.sh --flash /dev/sda    # dd image, growpart, resize2fs
```

or manually:

```sh
zstdcat images/nixos-image-rpi5-kernel-*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sudo growpart /dev/sdX 2 && sudo resize2fs /dev/sdX2
```

## Reproduce on another Pi

1. Give it a hostname/user/ssh key: either edit `configuration.nix` (single
   device) or copy it per-host and add a new `nixosConfigurations` entry in
   `flake.nix`.
2. `./build-image.sh --config <name> --flash /dev/sdX`.
3. Boot, then keep it updated on-device with
   `sudo nixos-rebuild switch --flake /etc/nixos#<name>` (the flake is baked
   into `/etc/nixos` at activation).

The build trusts the [`nixos-raspberrypi` cachix](https://nixos-raspberrypi.cachix.org)
for prebuilt kernel/firmware; Noctalia/Hyprland come from `cache.nixos.org`
via the pinned unstable nixpkgs.

## Layout gotchas

- `modules/desktop.nix` uses an **unstable** nixpkgs for the Noctalia package
  (binary-cached); the rest of the system builds from `nixos-26.05`.
- Editing `configuration.nix` (or the `modules/`) takes effect on the next
  `nixos-rebuild switch`; the activation script syncs the repo to `/etc/nixos`.