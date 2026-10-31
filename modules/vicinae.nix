# macOS only: flake.nix imports this module just for the nix-darwin Home
# Manager user. The Vicinae app itself is a Homebrew cask.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  configDir = "${config.home.homeDirectory}/.config/vicinae";
in
{
  # Vicinae rewrites settings.json from its settings window, so that file stays
  # mutable and only imports this managed one. Values in settings.json take
  # precedence over imports, which keeps changes made in the GUI working.
  # In shortcuts, "control" means the Command key on macOS.
  home.file.".config/vicinae/nix.json".text = builtins.toJSON {
    telemetry.system_info = false;
    providers = {
      clipboard = {
        preferences.evictionThreshold = "never";
        entrypoints.history.shortcut = "control+shift+V";
      };
      # local-private-tools.nix installs the Teams script command here.
      scripts.preferences.customDirs = [ "${config.home.homeDirectory}/.config/raycast/scripts" ];
    };
  };

  # Add nix.json to the imports of settings.json. Vicinae writes the file as
  # JSON behind a header of // comment lines, which are dropped before jq
  # parses it; Vicinae restores the header on its next write. A file that
  # does not parse is left alone with a warning instead of failing activation.
  home.activation.importVicinaeNixConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    vicinae_settings="${configDir}/settings.json"

    vicinae_settings_json() {
      grep -v '^[[:space:]]*//' "$vicinae_settings"
    }

    if [[ -L "$vicinae_settings" ]]; then
      warnEcho "$vicinae_settings is a symlink; not adding the nix.json import"
    elif [[ ! -e "$vicinae_settings" ]]; then
      if [[ -v DRY_RUN ]]; then
        verboseEcho "Would create $vicinae_settings"
      else
        run mkdir -p "${configDir}"
        printf '{\n  "imports": ["nix.json"]\n}\n' > "$vicinae_settings"
      fi
    elif ! vicinae_settings_json | ${pkgs.jq}/bin/jq empty 2>/dev/null; then
      warnEcho "Cannot parse $vicinae_settings; add \"nix.json\" to its imports by hand"
    elif ! vicinae_settings_json \
      | ${pkgs.jq}/bin/jq -e '(.imports // []) | index("nix.json") != null' >/dev/null; then
      if [[ -v DRY_RUN ]]; then
        verboseEcho "Would add the nix.json import to $vicinae_settings"
      else
        vicinae_settings_tmp=$(mktemp "${configDir}/.settings.json.XXXXXX")
        vicinae_settings_json \
          | ${pkgs.jq}/bin/jq '.imports = ((.imports // []) + ["nix.json"])' > "$vicinae_settings_tmp"
        mv -f "$vicinae_settings_tmp" "$vicinae_settings"
      fi
    fi
  '';
}
