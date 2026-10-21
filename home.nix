{ homeStateVersion, ... }:
{
  # Home Manager entry point for macOS and Linux. flake.nix only adds modules
  # from flake inputs and the platform-specific ones.
  imports = [
    ./modules/claude.nix
    ./modules/claude-mods.nix
    ./modules/glab-sync.nix
    ./modules/nix-config-helpers.nix
    ./modules/nix-index.nix
    ./modules/packages.nix
    ./modules/shell.nix
    ./modules/ssh.nix
  ];

  home.stateVersion = homeStateVersion;

  # The home-configuration.nix(5) page slows down every evaluation, and its
  # options.json build makes `nix flake check` warn about a missing store
  # path context. `home-manager option` and the online option search remain.
  manual.manpages.enable = false;

  xdg.configFile."ghostty/config".text = ''
    # New tabs and windows start in $HOME instead of inheriting the current cwd.
    working-directory = home
    window-inherit-working-directory = false

    # Restore the last window's size and position on launch (macOS only).
    window-save-state = always
  '';
}
