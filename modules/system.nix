{
  pkgs,
  inputs,
  username,
  homeDirectory,
  hostName,
  stateVersion,
  ...
}:
{
  environment.systemPackages = [
    pkgs.unixtools.watch
    pkgs.docker-credential-helpers
    pkgs.mas
  ];

  networking = {
    inherit hostName;
    localHostName = hostName;
    computerName = hostName;
  };

  users.users.${username}.home = homeDirectory;
  programs.zsh = {
    enable = true;
    # Home Manager's oh-my-zsh runs compinit with a per-version dump. A second,
    # unversioned dump here is rebuilt whenever Apple's and Nix's zsh alternate.
    enableCompletion = false;
    enableBashCompletion = false;
    # powerlevel10k replaces the prompt anyway.
    promptInit = "";
  };

  system = {
    configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
    primaryUser = username;
    inherit stateVersion;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  # Minutes is launched by macOS and does not inherit the interactive shell PATH.
  launchd.user.envVariables.MINUTES_FFMPEG = "/etc/profiles/per-user/${username}/bin/ffmpeg";
}
