{ lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  # The Python environment and model weights are installed only by the explicit
  # qwen-meeting-setup command. Home Manager activation performs no network IO.
  home.file.".bin/qwen-meeting" = lib.mkIf isDarwin {
    executable = true;
    source = ../config/qwen-meeting/qwen-meeting;
  };

  home.file.".bin/qwen-meeting-setup" = lib.mkIf isDarwin {
    executable = true;
    source = ../config/qwen-meeting/qwen-meeting-setup;
  };

  home.file.".config/qwen-meeting/context.txt" = lib.mkIf isDarwin {
    source = ../config/qwen-meeting/context.txt;
  };

  home.file.".config/qwen-meeting/runtime/pyproject.toml" = lib.mkIf isDarwin {
    source = ../config/qwen-meeting/runtime/pyproject.toml;
  };

  home.file.".config/qwen-meeting/runtime/uv.lock" = lib.mkIf isDarwin {
    source = ../config/qwen-meeting/runtime/uv.lock;
  };

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
