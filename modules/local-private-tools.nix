# macOS only: flake.nix imports this module just for the nix-darwin Home
# Manager user.
{ pkgs, ... }:

let
  runtime = pkgs.callPackage ../packages/qwen-meeting-runtime { };
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

    # teams-people.csv intentionally remains outside the Nix store because it
    # contains names, email addresses, and tenant IDs.
    ".config/raycast/scripts/teams-video-call.sh" = {
      executable = true;
      source = pkgs.replaceVars ../config/raycast/teams-video-call.sh {
        choose = "${pkgs.choose-gui}/bin/choose";
      };
    };
  };
}
