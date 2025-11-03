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
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      username = "michaelklug";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ../home.nix
          {
            home.username = "michaelklug";
            home.homeDirectory = "/Users/michaelklug";
          }
        ];
      };
    };
}
