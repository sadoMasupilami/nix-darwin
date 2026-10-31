# macOS only: flake.nix imports this module just for the nix-darwin Home
# Manager user.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  runtime = pkgs.callPackage ../packages/qwen-meeting-runtime { };

  teamsVideoCall = pkgs.replaceVars ../config/raycast/teams-video-call.sh {
    choose = "${pkgs.choose-gui}/bin/choose";
  };
in
{
  home.file = {
    # Python is an immutable generation dependency. Only model weights require
    # the explicit setup command; existing mutable virtualenvs are left alone.
    ".bin/qwen-meeting" = {
      executable = true;
      text = ''
        #!${pkgs.zsh}/bin/zsh
        export QWEN_MEETING_ASR=${runtime}/bin/mlx-qwen3-asr
        exec ${pkgs.zsh}/bin/zsh ${../config/qwen-meeting/qwen-meeting} "$@"
      '';
    };

    ".bin/qwen-meeting-setup" = {
      executable = true;
      text = ''
        #!${pkgs.zsh}/bin/zsh
        export QWEN_MEETING_PYTHON=${runtime}/bin/python
        export QWEN_MEETING_ASR=${runtime}/bin/mlx-qwen3-asr
        export QWEN_MEETING_RUNTIME=${../config/qwen-meeting/runtime}
        exec ${pkgs.zsh}/bin/zsh ${../config/qwen-meeting/qwen-meeting-setup} "$@"
      '';
    };

    ".config/qwen-meeting/context.txt".source = ../config/qwen-meeting/context.txt;

    # The setup command only needs the model fetcher; pyproject.toml and uv.lock
    # feed the Nix runtime package instead.
    ".config/qwen-meeting/runtime/fetch-models.py".source =
      ../config/qwen-meeting/runtime/fetch-models.py;
  };

  # Raycast and SuperCmd both read the Teams script from this folder, but
  # SuperCmd skips symlinked files and folders, so the script is installed as
  # a regular file instead of a home.file link. It runs after linkGeneration,
  # which removes the link of older generations, and replaces the file
  # atomically only when the content differs. teams-people.csv intentionally
  # remains outside the Nix store because it contains names, email addresses,
  # and tenant IDs.
  home.activation.installTeamsScriptCommand = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    scripts_dir="${config.home.homeDirectory}/.config/raycast/scripts"
    script="$scripts_dir/teams-video-call.sh"

    if [[ -L "$script" ]] || ! cmp -s ${teamsVideoCall} "$script"; then
      run mkdir -p "$scripts_dir"
      if [[ -v DRY_RUN ]]; then
        verboseEcho "Would install $script"
      else
        script_tmp=$(mktemp "$scripts_dir/.teams-video-call.XXXXXX")
        install -m 755 ${teamsVideoCall} "$script_tmp"
        mv -f "$script_tmp" "$script"
      fi
    fi
  '';
}
