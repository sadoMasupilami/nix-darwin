{
  imports = [
    ./modules/packages.nix
    ./modules/shell.nix
    ./modules/ssh.nix
    ./modules/ponytail.nix
  ];

  # Keep stable for backwards compatibility with existing Home Manager state.
  home.stateVersion = "23.11";

  xdg.configFile."ghostty/config".text = ''
    # New tabs and windows start in $HOME instead of inheriting the current cwd.
    working-directory = home
    window-inherit-working-directory = false

    # Restore the last window's size and position on launch (macOS only).
    window-save-state = always
  '';
}
