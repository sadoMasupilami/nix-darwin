{
  imports = [
    ./modules/packages.nix
    ./modules/shell.nix
    ./modules/ssh.nix
    ./modules/ponytail.nix
  ];

  # Keep stable for backwards compatibility with existing Home Manager state.
  home.stateVersion = "23.11";
}
