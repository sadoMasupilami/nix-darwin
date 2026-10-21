{ username, ... }:
let
  caches = [
    "https://cache.nixos.org"
    "https://devenv.cachix.org"
  ];
in
{
  # Determinate writes these to /etc/nix/nix.custom.conf. Its module also turns
  # off nix-darwin's own Nix management, so nix.settings would have no effect.
  determinateNix = {
    enable = true;
    customSettings = {
      # Preserve the existing trusted local-development behavior.
      sandbox = false;
      trusted-users = [
        "root"
        username
      ];
      substituters = caches;
      trusted-substituters = caches;
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
    };
  };
}
