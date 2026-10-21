{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}:
let
  entryNames = entries: map (entry: if builtins.isString entry then entry else entry.name) entries;
  brewNames = entryNames config.homebrew.brews;
  caskNames = entryNames config.homebrew.casks;

  # The launcher nix-config-preflight previews the cleanup with: this
  # generation's Homebrew code and taps over the live Cellar and Caskroom.
  homebrewPreflight = pkgs.callPackage ../packages/homebrew-preflight {
    setupHomebrewText = config.system.activationScripts.setup-homebrew.text;
    brewVersion = config.nix-homebrew.package.version;
    trustedTaps = config.nix-homebrew.trust.taps;
  };
  # The same file nix-darwin writes for its own `brew bundle` call.
  brewfile = pkgs.writeText "Brewfile" config.homebrew.brewfile;
in
{
  # nix-homebrew owns Homebrew itself and every tap checkout. Package selection
  # stays in nix-darwin's Homebrew module below. Fully declarative tap ownership
  # prevents imperative `brew tap` or `brew update` from moving past flake.lock.
  # The preflight blocks while a legacy real Taps directory still needs an
  # explicitly approved, backed-up one-time migration to nix-homebrew's symlink.
  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    user = username;
    autoMigrate = true;
    mutableTaps = false;

    trust.taps = [
      "azure/azd"
      "silverstein/tap"
    ];

    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "azure/homebrew-azd" = inputs.homebrew-azd;
      "silverstein/homebrew-tap" = inputs.homebrew-silverstein-tap;
    };
  };

  homebrew = {
    enable = true;
    prefix = "/opt/homebrew";

    # Homebrew uses locked tap definitions. App-owned updaters and the App
    # Store can still change native apps independently of this lockfile.
    global.autoUpdate = false;
    onActivation = {
      autoUpdate = false;
      upgrade = true;
      # Activation never removes anything; the cleanup gate below aborts it
      # instead.
      cleanup = "none";
    };

    # These are Homebrew names, which intentionally differ from the physical
    # nix-homebrew tap directory names above.
    taps = [
      { name = "homebrew/core"; }
      { name = "homebrew/cask"; }
      {
        name = "azure/azd";
        trusted = true;
      }
      {
        name = "silverstein/tap";
        trusted = true;
      }
    ];

    # mas and docker-credential-helpers are supplied by Nix system packages.
    # Ollama's formula dependencies are listed explicitly as well: Homebrew
    # Bundle's strict `cleanup --all --zap` otherwise proposes removing them
    # even though Ollama needs them at runtime.
    brews = [
      # Core also defines an `azd` alias for azure-dev. Keep using the tap
      # recorded in the installed formula's receipt during Bundle upgrades.
      "azure/azd/azd"
      "ca-certificates"
      "lz4"
      "mlx"
      "mlx-c"
      "mpdecimal"
      "ollama"
      "openssl@3"
      "python@3.14"
      "readline"
      "sqlite"
      "xz"
      "zstd"
    ];

    casks = [
      "1password"
      "microsoft-office"
      "microsoft-auto-update"
      "microsoft-teams"
      "sony-ps-remote-play"
      "rancher"
      "telegram"
      "whatsapp"
      "wifiman"
      "steam"
      "windows-app"
      "chatgpt"
      "claude"
      "claude-code@latest"
      "google-chrome"
      "google-drive"
      "ghostty"
      "raycast"
      "brave-browser"
      "commander-one"
      "daisydisk"
      "bartender"
      "badgeify"
      "webex"
      "spotify"
      "vlc"
      "elgato-stream-deck"
      "elgato-control-center"
      "bambu-studio"
      "orcaslicer"
      "autodesk-fusion"
      "blender"
      "codex"
      # Minutes and Muesli both record meetings on-device; Muesli also covers
      # dictation. qwen-meeting does not record, it re-transcribes existing
      # recordings into ~/Documents/Muesli-Transcripts.
      {
        name = "silverstein/tap/minutes";
        # Homebrew 6.0.20 batches plain casks with formulae and resolves this
        # shared name as a formula. Per-cask args retain the --cask path.
        args.appdir = "/Applications";
      }
      "visual-studio-code"
      "slack"
      "tigervnc"
      "ollamac"
      "muesli"
      # Quotas across several coding assistants, including Codex; the
      # usage-meter mod only covers Claude Code's status line.
      "claudebar"
    ];

    masApps = {
      "Goodnotes" = 1444383602;
      "1Password-Safari" = 1569813296;
      "WireGuard" = 1451685025;
    };
  };

  system.build.homebrewPreflight = homebrewPreflight;

  # The cleanup gate: it aborts activation before any change while undeclared
  # packages are still installed. Removals happen only in nix-config-apply,
  # which zaps exactly the list approved with --accept-zap before switching.
  # Generations built from this never uninstall on activation, so neither a
  # rollback to one nor a direct darwin-rebuild switch can bypass that
  # approval.
  #
  # This replaces nix-darwin's cleanup = "check" for two reasons. "check"
  # lives in system.checks, which the activate-system boot daemon embeds as
  # well, so it would also run Homebrew at every boot and on every reload of
  # that daemon, and a finding there would skip the boot-time /etc relink;
  # preActivation runs only in activate. And "check" runs the live brew,
  # which still has the previous generation's taps until setup-homebrew
  # replaces them later in activate, so a rename in a tap update can make it
  # disagree with the approved preview. The gate runs the preflight's
  # launcher instead: the preview, apply's check after the approved removal
  # and this gate all compute the same list.
  #
  # darwin-rebuild switch and --rollback move the system profile before they
  # run activate, so an aborted activation leaves the profile on a generation
  # that never ran. nix-config-apply therefore first runs activate in check
  # mode, which stops after this gate and nix-darwin's checks; see the README
  # for resetting the profile after a direct switch.
  system.activationScripts.preActivation.text = lib.mkBefore ''
    if [ -f ${config.homebrew.prefix}/bin/brew ]; then
      homebrewCleanupExitCode=0
      homebrewCleanupResult=$(
        PATH="${config.homebrew.prefix}/bin:${lib.makeBinPath [ pkgs.mas ]}:$PATH" \
          sudo --preserve-env=PATH --user=${lib.escapeShellArg config.homebrew.user} --set-home \
          ${homebrewPreflight}/bin/brew bundle cleanup --all --zap --file=${brewfile} </dev/null 2>&1
      ) || homebrewCleanupExitCode=$?
      # Exit status 1 is also brew's generic crash status. Only an actual
      # removal list is a finding that an approval can clear.
      if [ "$homebrewCleanupExitCode" -eq 1 ] \
        && grep -Eq '^Would (uninstall|untap)' <<<"$homebrewCleanupResult"; then
        printf >&2 '\e[1;31merror: found Homebrew packages not listed in the Brewfile, aborting activation\e[0m\n'
        printf >&2 '%s\n' "$homebrewCleanupResult"
        printf >&2 '\nReview them with nix-config-preflight and remove them only with nix-config-apply --accept-zap HASH.\n'
      elif [ "$homebrewCleanupExitCode" -ne 0 ]; then
        printf >&2 '\e[1;31merror: brew bundle cleanup failed, aborting activation\e[0m\n'
        printf >&2 '%s\n' "$homebrewCleanupResult"
      fi
      if [ "$homebrewCleanupExitCode" -ne 0 ]; then
        if [ "''${checkActivation:-0}" != 1 ]; then
          printf >&2 '\nIf darwin-rebuild switch or --rollback started this activation, the system\n'
          printf >&2 'profile already names this generation. Reset it before the next reboot:\n'
          printf >&2 '  sudo nix-env -p /nix/var/nix/profiles/system --set "$(readlink -f /run/current-system)"\n'
        fi
        exit 2
      fi
    fi
  '';

  assertions = [
    {
      assertion = config.homebrew.onActivation.cleanup == "none";
      message = "Homebrew cleanup must stay \"none\": removals belong to nix-config-apply, and the preActivation gate replaces \"check\", which would also run at every boot.";
    }
    {
      assertion = builtins.elem "chatgpt" caskNames;
      message = "The Homebrew manifest must retain the chatgpt cask.";
    }
    {
      assertion = builtins.elem "silverstein/tap/minutes" caskNames;
      message = "The Homebrew manifest must retain the Minutes cask.";
    }
    {
      assertion = !(builtins.elem "mas" brewNames);
      message = "mas must come from Nix, not Homebrew.";
    }
    {
      assertion = !(builtins.elem "docker-credential-helper" brewNames);
      message = "docker-credential-helpers must come from Nix, not Homebrew.";
    }
  ];
}
