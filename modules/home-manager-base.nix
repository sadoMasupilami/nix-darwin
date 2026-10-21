{
  username,
  homeDirectory,
  ...
}:
{
  # Only standalone Home Manager needs this. On macOS the nix-darwin
  # integration derives both values from users.users.
  home = {
    inherit username homeDirectory;
  };
}
