{
  config,
  lib,
  pkgs,
  ...
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  homeDirectory = config.home.homeDirectory;
  minutes = pkgs.callPackage ./packages/minutes.nix { };
  minutesCall = pkgs.writeShellApplication {
    name = "minutes-call";
    runtimeInputs = [ minutes ];
    text = ''
      exec minutes record \
        --intent call \
        --source default \
        --source auto \
        "$@"
    '';
  };
in
{
  # Minutes: high-quality local transcription for this M4 Max. The batch
  # pipeline uses the most accurate Whisper model, while dictation/live mode
  # stays on small for low latency. Runtime data and downloaded models remain
  # writable below ~/.minutes; only the durable configuration is Nix-managed.
  home.packages = lib.optionals isDarwin [
    pkgs.ffmpeg
    minutes
    minutesCall
  ];

  home.file.".config/minutes/config.toml" = lib.mkIf isDarwin {
    source = pkgs.replaceVars ./config/minutes/config.toml {
      inherit homeDirectory;
    };
  };

  # Keep voice-memo imports running without `minutes service install`, whose
  # generated LaunchAgent would otherwise live outside Nix management.
  launchd.agents.minutes-watch = lib.mkIf isDarwin {
    enable = true;
    config = {
      Label = "com.useminutes.watch";
      ProgramArguments = [
        "${minutes}/bin/minutes"
        "watch"
      ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ProcessType = "Background";
      ThrottleInterval = 10;
      StandardOutPath = "${homeDirectory}/.minutes/logs/watch.stdout.log";
      StandardErrorPath = "${homeDirectory}/.minutes/logs/watch.stderr.log";
      EnvironmentVariables = {
        HOME = homeDirectory;
        MINUTES_FFMPEG = "${pkgs.ffmpeg}/bin/ffmpeg";
        PATH = "${minutes}/bin:${pkgs.ffmpeg}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };

  home.activation.ensureMinutesDirectories = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p \
        "${homeDirectory}/meetings" \
        "${homeDirectory}/.minutes/inbox" \
        "${homeDirectory}/.minutes/logs"
    ''
  );

  # Model files are large mutable runtime assets, not configuration. This
  # idempotent helper leaves their network downloads as an explicit action.
  home.file.".bin/minutes-setup" = lib.mkIf isDarwin {
    source = pkgs.replaceVars ./config/minutes/setup.sh {
      minutes = "${minutes}/bin/minutes";
    };
    executable = true;
  };
}
