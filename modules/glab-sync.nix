{ lib, pkgs, ... }:
let
  glab-sync =
    pkgs.runCommand "glab-sync"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p "$out/bin" "$out/libexec"
        cp ${../config/glab-sync/glab-sync} "$out/libexec/glab-sync"
        chmod +x "$out/libexec/glab-sync"
        substituteInPlace "$out/libexec/glab-sync" \
          --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
        makeWrapper "$out/libexec/glab-sync" "$out/bin/glab-sync" \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.git
              pkgs.glab
              pkgs.jq
            ]
          }
      '';
in
{
  home.packages = [ glab-sync ];
}
