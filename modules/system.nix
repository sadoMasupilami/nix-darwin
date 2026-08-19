{
  pkgs,
  username,
  homeDirectory,
  hostName,
  darwinSystem,
  self,
  ...
}:
{
  environment.systemPackages = [
    pkgs.unixtools.watch
    pkgs.docker-credential-helpers
    pkgs.mas
  ];

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = darwinSystem;
  };

  # Determinate Nix owns the daemon and Nix configuration.
  nix.enable = false;

  networking = {
    inherit hostName;
    localHostName = hostName;
    computerName = hostName;
  };

  users.users.${username}.home = homeDirectory;
  programs.zsh.enable = true;

  system = {
    configurationRevision = self.rev or self.dirtyRev or null;
    primaryUser = username;
    stateVersion = 5;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  # Minutes is launched by macOS and does not inherit the interactive shell PATH.
  launchd.user.envVariables.MINUTES_FFMPEG = "/etc/profiles/per-user/${username}/bin/ffmpeg";
}
