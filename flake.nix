{
  description = "NixOS for Raspberry Pi 5 (ryuzakipi), with the Noctalia v5 desktop shell";

  inputs = {
    # Stable branch; follows nixpkgs pins maintained by nvmd.
    # git+https (not github:) avoids GitHub's archive-download rate limits.
    nixos-raspberrypi.url = "git+https://github.com/nvmd/nixos-raspberrypi?ref=main";

    # Noctalia v5 is not yet in the stable nixpkgs branch we build from, so we
    # pull the upstream flake (module + package) and an unstable nixpkgs for a
    # binary-cached package.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    noctalia.url = "github:noctalia-dev/noctalia";
    noctalia.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  # Trust the nixos-raspberrypi binary cache (prebuilt kernel/firmware).
  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs =
    { nixos-raspberrypi, noctalia, nixpkgs-unstable, ... }@inputs:
    let
      # Prefer the binary-cached unstable-nixpkgs build of Noctalia (v5) over
      # compiling the upstream flake's package from source on the Pi.
      unstableNoctalia = nixpkgs-unstable.legacyPackages.aarch64-linux.noctalia;
    in
    {
      nixosConfigurations.rpi5 = nixos-raspberrypi.lib.nixosInstaller {
        specialArgs = inputs;
        modules = [
          nixos-raspberrypi.nixosModules.raspberry-pi-5.base
          nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
          nixos-raspberrypi.nixosModules.raspberry-pi-5.bluetooth

          # Noctalia v5 NixOS module (defines programs.noctalia).
          noctalia.nixosModules.default

          # Use the binary-cached package from unstable nixpkgs.
          ({ lib, ... }:
            {
              programs.noctalia.package = lib.mkForce unstableNoctalia;
            })

          # libadwaita's GUI test suite needs a display and fails in the
          # headless build sandbox; skip it (gtk4 tests still run).
          ({ lib, ... }:
            {
              nixpkgs.overlays = [
                (final: prev: {
                  libadwaita = prev.libadwaita.overrideAttrs { doCheck = false; };
                })
              ];
            })

          ./configuration.nix
          ./modules/desktop.nix
        ];
      };
    };
}