{ lib, pkgs, ... }:
let
  minAgeDays = 14;
  startBelowFreePercent = 20;
  urgentBelowFreePercent = 5;

  nix-gc-recent =
    pkgs.runCommand "nix-gc-recent"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p "$out/bin" "$out/libexec"
        cp ${../config/nix-gc/nix-gc-recent} "$out/libexec/nix-gc-recent"
        chmod +x "$out/libexec/nix-gc-recent"
        substituteInPlace "$out/libexec/nix-gc-recent" \
          --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
        makeWrapper "$out/libexec/nix-gc-recent" "$out/bin/nix-gc-recent" \
          --set-default NIX_GC_MIN_AGE_DAYS ${toString minAgeDays} \
          --set-default NIX_GC_START_BELOW_FREE_PERCENT ${toString startBelowFreePercent} \
          --set-default NIX_GC_URGENT_BELOW_FREE_PERCENT ${toString urgentBelowFreePercent} \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gawk
            ]
          }:/nix/var/nix/profiles/default/bin
      '';
in
{
  # Determinate Nixd's own collector has no retention setting, so it is replaced
  # by nix-gc-recent, which spares recently registered store paths.
  determinateNix.determinateNixd.garbageCollector.strategy = "disabled";

  environment.systemPackages = [ nix-gc-recent ];

  launchd.daemons.nix-gc-recent = {
    command = "${nix-gc-recent}/bin/nix-gc-recent";
    serviceConfig = {
      # Cheap when there is enough free space: it checks the disk and exits.
      StartInterval = 3600;
      RunAtLoad = true;
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/var/log/nix-gc-recent.log";
      StandardErrorPath = "/var/log/nix-gc-recent.log";
    };
  };
}
