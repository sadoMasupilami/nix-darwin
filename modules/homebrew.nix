{
  config,
  inputs,
  username,
  ...
}:
let
  entryNames = entries: map (entry: if builtins.isString entry then entry else entry.name) entries;
  brewNames = entryNames config.homebrew.brews;
  caskNames = entryNames config.homebrew.casks;
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

    # Updates happen only by changing flake.lock. Activation upgrades the
    # declared packages to the versions provided by those locked tap sources.
    global.autoUpdate = false;
    onActivation = {
      autoUpdate = false;
      upgrade = true;
      cleanup = "zap";
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
      "azd"
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
      "claude-code"
      "google-chrome"
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
      "ultrastardeluxe"
      "codex"
      "codex-app"
      "silverstein/tap/minutes"
      "visual-studio-code"
      "slack"
      "tigervnc"
      "ollamac"
      "muesli"
    ];

    masApps = {
      "Goodnotes" = 1444383602;
      "1Password-Safari" = 1569813296;
      "WireGuard" = 1451685025;
    };
  };

  assertions = [
    {
      assertion = builtins.elem "codex-app" caskNames;
      message = "The Homebrew manifest must retain the codex-app cask.";
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
