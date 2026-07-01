{
  description = "Michaels Macos system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs =
    inputs@{
      nix-darwin,
      nixpkgs,
      home-manager,
      nix-homebrew,
      determinate,
      homebrew-core,
      homebrew-cask,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      machineConfig = import ./machine-config.nix;
      inherit (machineConfig) username;
      inherit (machineConfig.darwin)
        homeDirectory
        hostName
        repoDirectory
        ;
    in
    {
      darwinConfigurations."macos" = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit
            inputs
            username
            homeDirectory
            hostName
            repoDirectory
            ;
        };
        modules = [
          ./darwin.nix
          # Determinate manages /etc/nix/nix.conf and /etc/nix/nix.custom.conf
          determinate.darwinModules.default
          {
            determinateNix = {
              enable = true;
              customSettings = {
                trusted-users = [
                  "root"
                  username
                ];
                substituters = "https://cache.nixos.org https://devenv.cachix.org https://nixpkgs-unfree.cachix.org";
                trusted-substituters = "https://cache.nixos.org https://devenv.cachix.org https://nixpkgs-unfree.cachix.org";
                trusted-public-keys = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs=";
              };
            };
          }
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              # Install Homebrew under the default prefix
              enable = true;

              # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
              enableRosetta = true;

              # User owning the Homebrew prefix
              user = username;

              # Automatically migrate existing Homebrew installations
              autoMigrate = true;

              taps = {
                "homebrew/homebrew-core" = homebrew-core;
                "homebrew/homebrew-cask" = homebrew-cask;
              };
            };
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              inherit
                username
                homeDirectory
                hostName
                repoDirectory
                ;
            };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };

      formatter.${system} = pkgs.writeShellApplication {
        name = "nix-darwin-fmt";
        runtimeInputs = [
          pkgs.fd
          pkgs.nixfmt
        ];
        text = ''
          has_path=false
          for arg in "$@"; do
            case "$arg" in
              -*) ;;
              *) has_path=true ;;
            esac
          done

          if [ "$#" -gt 0 ] && [ "$has_path" = true ]; then
            exec nixfmt "$@"
          fi

          fd --extension nix --type f --exec-batch nixfmt "$@" {}
        '';
      };
    };
}
