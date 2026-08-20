# First Boot — NixOS on the Raspberry Pi 5

Two images are released side by side. Which you flashed decides what "first
boot" looks like:

- **`v0.1` — Desktop image (2-part split).** This is the guide below: boots
  straight into a **Hyprland + Noctalia v5 desktop** with the `ryuzaki` user
  and wifi auto-connected. Least hassle.
- **`v0.2` — Minimal image (single file).** See
  [§ 0 — Minimal image first boot](#0-minimal-image-first-boot) instead: a
  light console base where you choose your own username, hostname and wifi.

Before you start, confirm the card is flashed and the partition was grown to
the full card size (done by the flasher with `growpart` + `resize2fs`).

---

## 0. Minimal image first boot

The minimal image gives you a bare NixOS console with `wifitui`, ssh and Nix
flakes — no desktop, no baked wifi profile, no pre-created personal user. You
define your own machine on first boot by cloning this repo and rebuilding.

1. **Boot** (follow § 1 below for hardware steps). You land on the NixOS
   console (tty1). Log in as the default bootstrap user:

   ```text
   login: bootstrap
   password: changeme   # change it on first login: passwd
   ```

2. **Join your wifi** (or plug in Ethernet):

   ```sh
   sudo wifitui     # interactive TUI: pick a network, enter the password
   ```

   Once connected, the Pi is reachable over ssh (password auth, user
   `bootstrap`) at `nixos-rpi5.local` — or use the console directly.

3. **Clone this repo and configure your machine:**

   ```sh
   git clone https://github.com/Ryuzaki5100/rpi-nixos
   cd rpi-nixos
   ./setup.sh
   ```

   `setup.sh` asks for your **username, password, hostname and wifi**, writes
   them into `local.nix` / `secrets.nix` (gitignored, safe to commit later),
   then runs `nixos-rebuild switch --flake .#rpi5`. After it finishes (a few
   minutes — closures come from the binary caches), reboot and you're in your
   own Hyprland + Noctalia desktop as your user.

4. **Manage it from then on** — same as the desktop guide below
   (`sudo nixos-rebuild switch --flake /etc/nixos#rpi5`).

> Prefer to bake a known machine straight into the image? `setup.sh --no-rebuild`
> prints the config and lets you run the switch yourself, or you can edit
> `local.nix`/`secrets.nix` by hand before building with `./build-image.sh`.

---

## 1. Boot the Pi (desktop image)

This part covers the **v0.1 desktop image**, which boots straight into the
Hyprland + Noctalia v5 desktop with the `ryuzaki` user.

1. Power the Pi 5 **off** and unplug it.
2. Remove the old Debian SD card and insert the new NixOS card into the SD slot
   (keep the Debian card somewhere safe — it is your fallback).
3. Connect Ethernet (recommended for first boot), HDMI, keyboard/mouse as needed.
4. Plug in the **27 W USB-C** supply (a weaker supply can cause throttling and
   storage errors) and power on.
5. You should see the NixOS console on the HDMI display. Boot chain is:
   RPi EEPROM → Raspberry Pi firmware → U-Boot → NixOS generation bootloader.

## 2. Get network / SSH access

If you are connected over Ethernet, DHCP assigns an address automatically and
mDNS (Avahi) advertises the hostname:

```sh
ssh ryuzaki@ryuzakipi.local
```

Falls back if `ryuzakipi.local` does not resolve:

- Check the Pi's IP on the router / with `arp -a` / `ip neigh`.
- Or log in at the physical console with the initial password.

Note: SSH password authentication is **disabled** — login requires the
`ryuzaki` user's `ssh-ed25519 … atharvaa2210@gmail.com` key (also installed for
`root`). The very first time, accept the new host key (it is freshly generated
per machine).

## 3. First login — set your password

The greeter **auto-logs-in** `ryuzaki` straight into the Hyprland + Noctalia
desktop (no password prompt at boot). The image ships with a one-time bootstrap
password (`changeme`). Replace it immediately in a terminal (Super+Return opens
`foot`):

```sh
passwd
```

Then optionally rotate the root password too:

```sh
sudo passwd root
```

## 4. Verify the install

```sh
uname -a                                  # raspberrypi kernel, e.g. ...-rpi5 aarch64
df -h /                                   # should show the grown rootfs (~238 G free)
free -h                                   # RAM available
ip a                                     # addresses on eth0 / wlan0
sudo fdisk -l /dev/mmcblk0               # confirm the partition table covers the card
```

Check Wi-Fi (if configured) and Bluetooth:

```sh
ip a show wlan0                          # has an IPv4 if connected
bluetoothctl list                        # shows the controller
```

If the card was not grown to full size, do it once:

```sh
sudo growpart /dev/mmcblk0 2
sudo resize2fs /dev/mmcblk0p2
```

## 5. Manage the system with the flake

The flake is **baked into `/etc/nixos`** at activation, so you can rebuild
on-device without cloning anything:

```sh
# on the Pi
sudo nixos-rebuild switch --flake /etc/nixos#rpi5
```

This copies the updated repo into `/etc/nixos` on every activation, so your
edits in the repo stay in sync. Alternatively clone/edit from your workstation
and `scp -r ~/nixos-rpi5 ryuzaki@ryuzakipi.local:~/`, then rebuild from there.

### Useful commands

```sh
# apply config changes after editing configuration.nix
sudo nixos-rebuild switch --flake /etc/nixos#rpi5

# update the nixos-raspberrypi / nixpkgs inputs, then rebuild
cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .#rpi5

# roll back to the previous generation
sudo nixos-rebuild switch --rollback

# list generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system
```

## 6. Wi-Fi configuration

Wi-Fi is handled by NetworkManager. The image already contains a declarative
profile for your network (`Ryuzaki`) — it should auto-connect on boot. To check
or change it:

```sh
nmcli device wifi list            # see available networks
nmcli device wifi show            # current status
sudo nmcli device wifi connect "YOUR_SSID" password "YOUR_PASS"   # attach manually
```

To bake a different network in permanently, edit `configuration.nix`:

```nix
networking.networkmanager.ensureProfiles.profiles."YOUR_SSID" = {
  connection = { id = "YOUR_SSID"; type = "wifi"; autoconnect = true; };
  wifi = { ssid = "YOUR_SSID"; mode = "infrastructure"; };
  wifi-security = { key-mgmt = "wpa-psk"; psk = "YOUR_PASSPHRASE"; };
  ipv4 = { method = "auto"; };
  ipv6 = { method = "auto"; };
};
```

then `sudo nixos-rebuild switch --flake /etc/nixos#rpi5`.

## 7. A short desktop tour

- **Hyprland** is the compositor, started by greetd (autologin) through uWSM.
- **Noctalia** is the shell: top bar, launcher, clipboard, control center.
  - `Super+Space` — launcher
  - `Super+V` — clipboard
  - `Super+N` — control center
  - `Super+L` — lock screen
- **Terminal:** `foot` (`Super+Return`); **Browser:** `firefox`.
- Config lives in `~/.config/noctalia/config.toml` (seeded from
  `modules/noctalia.toml`, changes hot-reload) and
  `~/.config/hypr/hyprland.conf` (seeded from `modules/hyprland.conf`).
- To remove the autologin and show a login prompt instead, drop the `user`
  line from `services.greetd.settings.default_session` in `modules/desktop.nix`.

## 8. Troubleshooting

- **No HDMI output after U-Boot:** the kernel needs `console=tty0` for display
  output. Add `boot.kernelParams = [ "console=tty0" ];` and rebuild.
- **`ryuzakipi.local` doesn't resolve:** mDNS may be blocked by the network;
  find the IP via the router or `arp -a` and use that.
- **Pi won't boot / constant crashes:** undervoltage is the usual cause — use
  the official 27 W PSU and a decent USB-C cable.
- **Wi-Fi is slow / drops:** disable NetworkManager powersave
  (`networking.networkmanager.wifi.powersave = false;`) if you later switch to
  NetworkManager.
- **Something went wrong:** power off, swap back to the old Debian card, mount
  the NixOS card and fix/rebuild it from there.

## 9. References

- Flake: <https://github.com/nvmd/nixos-raspberrypi>
- Image builder: `./build-image.sh`
- NixOS on ARM wiki: <https://wiki.nixos.org/wiki/NixOS_on_ARM/Raspberry_Pi_5>
