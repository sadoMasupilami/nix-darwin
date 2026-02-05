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
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      nix-homebrew,
      determinate,
      homebrew-core,
      homebrew-cask,
      ...
    }:
    {
      darwinConfigurations."macos" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs; };
        modules = [
          ./darwin.nix
          # Determinate manages /etc/nix/nix.conf and /etc/nix/nix.custom.conf
          determinate.darwinModules.default
          {
            determinateNix = {
              enable = true;
              customSettings = {
                substituters = "https://cache.nixos.org https://nixpkgs-unfree.cachix.org";
                trusted-substituters = "https://cache.nixos.org https://nixpkgs-unfree.cachix.org";
                trusted-public-keys = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs=";
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
              user = "michaelklug";

              # Automatically migrate existing Homebrew installations
              autoMigrate = true;
            };
            nix.settings.experimental-features = [ "nix-command" "flakes" ];
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.michaelklug = import ./home.nix;
          }
        ];
      };
      darwinPackages = self.darwinConfigurations."macos".pkgs;
    };
}
