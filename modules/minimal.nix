{
  pkgs,
  lib,
  ...
}:

# ---------------------------------------------------------------------------
# Vanilla bootstrap image (rpi5-minimal).
#
# Deliberately INDEPENDENT of local.nix / secrets.nix: a shared image has no
# personal config baked in. A brand-new user logs in as `bootstrap` at the
# console, joins wifi with `wifitui`, clones this repo, runs ./setup.sh (which
# writes their own local.nix/secrets.nix), and rebuilds to the desktop (rpi5).
# ---------------------------------------------------------------------------
{
  # mDNS: reached at <hostName>.local
  networking.hostName = "nixos-rpi5";

  # Generic bootstrap account for the first login. `passwd` on first login to
  # change it (or replace it entirely by rebuilding with setup.sh).
  users.users.bootstrap = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
    ];
    initialPassword = "changeme";
  };

  # The nvmd/nixpkgs installer profile declares a default `nixos` user account.
  # Neutralize and purge it so the only accounts are the ones above (bootstrap,
  # and later the user chosen in setup.sh).
  users.users.nixos = lib.mkForce {
    isSystemUser = true;
    group = "nogroup";
    home = "/var/empty";
    createHome = false;
    shell = "/run/current-system/sw/bin/nologin";
    hashedPassword = lib.mkForce null;
    openssh.authorizedKeys.keys = lib.mkForce [ ];
  };
  services.getty.autologinUser = lib.mkForce "bootstrap";

  # ---------------------------------------------------------------------------
  # SSH enabled out of the box so the Pi is reachable once wifi is joined.
  # Password auth stays on for the bootstrap user; the desktop config switches
  # to key auth.
  # ---------------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
    };
  };

  # Wi-Fi: NetworkManager + wifitui (interactive TUI to scan/join networks).
  # No wifi profile is baked by design, so the image is safe to share.
  networking.networkmanager.enable = true;
  services.avahi.enable = true;

  environment.systemPackages = with pkgs; [
    wifitui
    git
    htop
    vim
    nixos-rebuild
  ];

  # Nix flakes, so `nixos-rebuild switch --flake .#rpi5` works on-device.
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  # ZFS is not used; silence the sd-image warning about forceImportRoot.
  boot.zfs.forceImportRoot = false;

  system.stateVersion = "26.05";
}