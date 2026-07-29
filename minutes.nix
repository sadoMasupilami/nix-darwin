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
  fluidAudio = pkgs.callPackage ./packages/fluidaudio.nix { };
  parakeetModelDirectory = "${homeDirectory}/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3";
  minutesParakeetPostprocess = pkgs.writeShellApplication {
    name = "minutes-parakeet-postprocess";
    text = ''
      exec ${pkgs.python3}/bin/python3 \
        ${./config/minutes/parakeet_postprocess.py} \
        --fluidaudio ${fluidAudio}/bin/fluidaudio \
        "$@"
    '';
  };
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
  # Minutes keeps recording, live transcription, and speaker diarization.
  # FluidAudio adds the faster Parakeet v3 path for high-quality final
  # transcripts. Runtime data and downloaded models remain writable; only the
  # durable tools and configuration are Nix-managed.
  home.packages = lib.optionals isDarwin [
    pkgs.ffmpeg
    fluidAudio
    minutes
    minutesCall
    minutesParakeetPostprocess
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

  # Once Minutes has finished moving a stable WAV into ~/meetings, create a
  # Parakeet v3 transcript and align its word timestamps to Minutes' existing
  # speaker-labelled Markdown. The original Minutes files are never replaced.
  launchd.agents.minutes-parakeet-postprocess = lib.mkIf isDarwin {
    enable = true;
    config = {
      Label = "com.useminutes.parakeet-postprocess";
      ProgramArguments = [
        "${minutesParakeetPostprocess}/bin/minutes-parakeet-postprocess"
        "--root"
        "${homeDirectory}/meetings"
        "--model-dir"
        parakeetModelDirectory
        "--state-dir"
        "${homeDirectory}/.minutes/parakeet-postprocess"
        "--settle-seconds"
        "30"
      ];
      RunAtLoad = true;
      StartInterval = 60;
      WatchPaths = [
        "${homeDirectory}/meetings"
        "${homeDirectory}/.minutes/jobs/archive"
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 5;
      ThrottleInterval = 10;
      StandardOutPath = "${homeDirectory}/.minutes/logs/parakeet-postprocess.stdout.log";
      StandardErrorPath = "${homeDirectory}/.minutes/logs/parakeet-postprocess.stderr.log";
      EnvironmentVariables = {
        HOME = homeDirectory;
        PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };

  home.activation.ensureMinutesDirectories = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p \
        "${homeDirectory}/meetings" \
        "${homeDirectory}/.minutes/inbox" \
        "${homeDirectory}/.minutes/logs" \
        "${homeDirectory}/.minutes/parakeet-postprocess"
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
