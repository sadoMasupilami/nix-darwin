{
  lib,
  pkgs,
  repoDirectory,
  ...
}:
let
  isSupported = pkgs.stdenv.hostPlatform.isDarwin || pkgs.stdenv.hostPlatform.isLinux;
  helpers = [
    "nix-config-update"
    "nix-config-preflight"
    "nix-config-apply"
  ];
in
{
  home.file = lib.mkIf isSupported (
    builtins.listToAttrs (
      map (name: {
        name = ".bin/${name}";
        value = {
          executable = true;
          text = ''
            #!/usr/bin/env bash
            exec env NIX_CONFIG_REPO=${lib.escapeShellArg repoDirectory} \
              ${lib.escapeShellArg "${repoDirectory}/config/nix-config/${name}"} "$@"
          '';
        };
      }) helpers
    )
  );
}
