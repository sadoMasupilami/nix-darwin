{ lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  runtime = pkgs.callPackage ../packages/qwen-meeting-runtime { };
in
{
  # Python is an immutable generation dependency. Only model weights require
  # the explicit setup command; existing mutable virtualenvs are left alone.
  home.file.".bin/qwen-meeting" = lib.mkIf isDarwin {
    executable = true;
    text = ''
      #!${pkgs.zsh}/bin/zsh
      export QWEN_MEETING_ASR=${runtime}/bin/mlx-qwen3-asr
      exec ${pkgs.zsh}/bin/zsh ${../config/qwen-meeting/qwen-meeting} "$@"
    '';
  };

  home.file.".bin/qwen-meeting-setup" = lib.mkIf isDarwin {
    executable = true;
    text = ''
      #!${pkgs.zsh}/bin/zsh
      export QWEN_MEETING_PYTHON=${runtime}/bin/python
      export QWEN_MEETING_ASR=${runtime}/bin/mlx-qwen3-asr
      export QWEN_MEETING_RUNTIME=${../config/qwen-meeting/runtime}
      exec ${pkgs.zsh}/bin/zsh ${../config/qwen-meeting/qwen-meeting-setup} "$@"
    '';
  };

  home.file.".config/qwen-meeting/context.txt" = lib.mkIf isDarwin {
    source = ../config/qwen-meeting/context.txt;
  };

  # The setup command only needs the model fetcher; pyproject.toml and uv.lock
  # feed the Nix runtime package instead.
  home.file.".config/qwen-meeting/runtime/fetch-models.py" = lib.mkIf isDarwin {
    source = ../config/qwen-meeting/runtime/fetch-models.py;
  };

  # teams-people.csv intentionally remains outside the Nix store because it
  # contains names, email addresses, and tenant IDs.
  home.file.".config/raycast/scripts/teams-video-call.sh" = lib.mkIf isDarwin {
    executable = true;
    source = ../config/raycast/teams-video-call.sh;
  };

}
