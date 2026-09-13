{
  lib,
  pkgs,
  repoDirectory,
  ...
}:
let
  isSupported = pkgs.stdenv.hostPlatform.isDarwin || pkgs.stdenv.hostPlatform.isLinux;
  names = [
    "nix-config-update"
    "nix-config-preflight"
    "nix-config-apply"
  ];
  helpers =
    pkgs.runCommand "nix-config-helpers"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p "$out/bin" "$out/libexec"
        cp ${../config/nix-config}/* "$out/libexec/"
        chmod -R u+w "$out/libexec"
        for name in ${lib.concatStringsSep " " names}; do
          substituteInPlace "$out/libexec/$name" \
            --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
          chmod +x "$out/libexec/$name"
          makeWrapper "$out/libexec/$name" "$out/bin/$name" \
            --set-default NIX_CONFIG_REPO ${lib.escapeShellArg repoDirectory} \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.jq
                pkgs.git
                pkgs.gnugrep
              ]
            }
        done
      '';

in
{
  home.file = lib.mkIf isSupported (
    builtins.listToAttrs (
      map (name: {
        name = ".bin/${name}";
        value = {
          executable = true;
          source = "${helpers}/bin/${name}";
        };
      }) names
    )
  );
}
