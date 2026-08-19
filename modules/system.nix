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

    # TODO
    overlays = [
      # avro-cpp 1.12's Exception.hh calls fmt::format but only includes
      # <fmt/core.h>. Since fmt 11 that header no longer pulls in format.h
      # unless FMT_DEPRECATED_HEAVY_CORE is defined, so every consumer of the
      # header fails to compile against fmt 12 — here libserdes' C++ half,
      # which breaks kcat and with it the whole home-manager profile.
      # Passing the define through --CXXFLAGS does not work: libserdes uses
      # mklove, whose configure splits that value on whitespace and rejects
      # the second token. Drop this once avro-cpp includes <fmt/format.h>.
      (final: prev: {
        libserdes = prev.libserdes.overrideAttrs (old: {
          NIX_CFLAGS_COMPILE = toString [
            (old.NIX_CFLAGS_COMPILE or "")
            "-DFMT_DEPRECATED_HEAVY_CORE"
          ];
        });
      })
    ];
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
