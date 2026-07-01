# ignore this file until you really know you need to change it :)
# this is used only for linux not macos
{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      machineConfig = import ../machine-config.nix;
      inherit (machineConfig)
        username
        ;
      inherit (machineConfig.linux)
        system
        homeDirectory
        repoDirectory
        ;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      hmModules = [
        ../home.nix
        {
          home.username = username;
          home.homeDirectory = homeDirectory;
        }
      ];
    in
    {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = hmModules;
        extraSpecialArgs = { inherit repoDirectory; };
      };
      homeConfigurations.default = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = hmModules;
        extraSpecialArgs = { inherit repoDirectory; };
      };
    };
}
