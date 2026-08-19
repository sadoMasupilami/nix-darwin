{
  username,
  homeDirectory,
  ...
}:
{
  home = {
    inherit username homeDirectory;
  };
}
