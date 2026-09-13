{
  config,
  lib,
  pkgs,
  ponytailSource,
  ...
}:
let
  plugin = pkgs.callPackage ../packages/ponytail { src = ponytailSource; };
  # The version names upstream, our patch and the Node.js runtime, so a
  # changed hook set always gets a fresh cache directory.
  cacheVersion = builtins.unsafeDiscardStringContext plugin.version;
  cachePath = ".codex/plugins/cache/nix-ponytail/ponytail/${cacheVersion}";
  marketplace = pkgs.runCommand "ponytail-marketplace" { } ''
    mkdir -p "$out/.agents/plugins" "$out/plugins"
    ln -s ${plugin} "$out/plugins/ponytail"
    cp ${
      pkgs.writeText "ponytail-marketplace.json" (
        builtins.toJSON {
          name = "nix-ponytail";
          interface.displayName = "Ponytail (Nix)";
          plugins = [
            {
              name = "ponytail";
              source = {
                source = "local";
                path = "./plugins/ponytail";
              };
              policy = {
                installation = "AVAILABLE";
                authentication = "ON_INSTALL";
              };
              category = "Productivity";
            }
          ];
        }
      )
    } "$out/.agents/plugins/marketplace.json"
  '';
in
{
  # Whole-directory links preserve Claude's command/agent discovery. Personal
  # plugins require Claude Code >= 2.1.157 (including our Homebrew client).
  home.file.".claude/skills/ponytail".source = plugin;
  home.file.${cachePath}.source = plugin;

  # Codex can replace a plugin-cache symlink with a real directory. Like Home
  # Manager's Codex module, discard only this managed, reproducible cache so a
  # second activation can restore the immutable link. Never touch other caches.
  home.activation.cleanPonytailCache = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    ponytail_cache=${lib.escapeShellArg "${config.home.homeDirectory}/${cachePath}"}
    if [[ -d "$ponytail_cache" && ! -L "$ponytail_cache" ]]; then
      run ${pkgs.coreutils}/bin/rm -rf -- "$ponytail_cache"
    fi
  '';

  # Both apps retain ownership of their main configuration files.
  home.activation.reconcilePonytail = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${plugin.reconcilePython}/bin/python3 ${../config/ponytail/reconcile.py} \
      ${lib.escapeShellArg config.home.homeDirectory} ${marketplace}
  '';
}
