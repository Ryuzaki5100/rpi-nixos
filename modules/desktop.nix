{
  pkgs,
  ...
}:

let
  # Starter files are copied to the user's home on first activation only
  # (`cp -n`), so user edits are never overwritten afterwards.
  seedUserConfig = {
    text = ''
      mkdir -p /home/ryuzaki/.config/noctalia
      mkdir -p /home/ryuzaki/.config/hypr
      cp -n ${../modules/noctalia.toml} /home/ryuzaki/.config/noctalia/config.toml || true
      cp -n ${../modules/hyprland.conf} /home/ryuzaki/.config/hypr/hyprland.conf || true
      chown -R ryuzaki:users /home/ryuzaki/.config/noctalia /home/ryuzaki/.config/hypr
    '';
    deps = [ ];
  };
in
{
  # ---------------------------------------------------------------------------
  # Hyprland compositor, wrapped by UWSM so it starts graphical-session.target
  # (the target the Noctalia shell runs under).
  # ---------------------------------------------------------------------------
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # ---------------------------------------------------------------------------
  # Noctalia v5: sleek Wayland desktop shell (bar, launcher, notifications...).
  # Available in this nixpkgs; runs as a systemd user service bound to the
  # Hyprland session.
  # ---------------------------------------------------------------------------
  programs.noctalia = {
    enable = true;
    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
    recommendedServices.enable = true;
  };

  # ---------------------------------------------------------------------------
  # Autologin: greetd drops straight into the Hyprland + Noctalia desktop.
  # ---------------------------------------------------------------------------
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.uwsm}/bin/uwsm start hyprland";
        user = "ryuzaki";
      };
    };
  };

  # Seed starter dotfiles on first boot.
  system.activationScripts.seed-user-config = seedUserConfig;

environment.systemPackages = with pkgs; [
    foot
    firefox
    wl-clipboard
    brightnessctl
  ];

  # Let the desktop user control brightness (RP1 backlight) and access DRM/input
  # devices for the compositor.
  users.users.ryuzaki.extraGroups = [ "video" "input" ];
}