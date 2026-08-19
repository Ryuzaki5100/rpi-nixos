{
  config,
  pkgs,
  lib,
  ...
}:

let
  # The flake source (this repo), filtered so we only bake code/docs onto the
  # device - never build artifacts, git metadata or generated images.
  flakeSource = builtins.path {
    path = ./.;
    name = "rpi-nixos-flake";
    filter = path: type:
      let base = baseNameOf path;
      in base != ".git" && base != "result" && base != "images";
  };
in
{
  networking.hostName = "ryuzakipi";

  # ---------------------------------------------------------------------------
  # User accounts
  # ---------------------------------------------------------------------------
  users.users.ryuzaki = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
    ];
    # One-time bootstrap password. Run `passwd` on first login to replace it.
    initialPassword = "39207395";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILei3S6Jr/3WTz7DrVIzmeY/wNdWtfas066HAp/P8Emd atharvaa2210@gmail.com"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILei3S6Jr/3WTz7DrVIzmeY/wNdWtfas066HAp/P8Emd atharvaa2210@gmail.com"
  ];

  # ---------------------------------------------------------------------------
  # SSH
  # ---------------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # mDNS: reachable at ryuzakipi.local
  services.avahi.enable = true;

  # ---------------------------------------------------------------------------
  # Wi-Fi via NetworkManager.
  # The nvmd installer profile enables NetworkManager, so Wi-Fi is configured
  # declaratively as an NM connection profile rather than with wpa_supplicant.
  # To connect to the network interactively later: `nmcli device wifi connect`.
  # ---------------------------------------------------------------------------
  networking.networkmanager = {
    enable = true;
    ensureProfiles.profiles = {
      "Ryuzaki" = {
        connection = {
          id = "Ryuzaki";
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          ssid = "Ryuzaki";
          mode = "infrastructure";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "atharvaditya";
        };
        ipv4 = { method = "auto"; };
        ipv6 = { method = "auto"; };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Extra packages
  # ---------------------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    git
    htop
    tree
    vim
  ];

  # ZFS is not used; silence the sd-image warning about forceImportRoot.
  boot.zfs.forceImportRoot = false;

  # ---------------------------------------------------------------------------
  # Bake the flake into /etc/nixos so the device can be rebuilt on-device:
  #   sudo nixos-rebuild switch --flake /etc/nixos#rpi5
  # ---------------------------------------------------------------------------
  system.activationScripts.etc-nixos = {
    text = ''
      mkdir -p /etc/nixos
      cp -rLf ${flakeSource}/. /etc/nixos/
    '';
    deps = [ ];
  };

  system.stateVersion = "26.05";
}
