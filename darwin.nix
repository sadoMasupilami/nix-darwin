# macos wide configuration

# global packages to install system wide (all users)
{
  pkgs,
  username,
  homeDirectory,
  hostName,
  ...
}:
{
  environment.systemPackages = [
    pkgs.unixtools.watch
    pkgs.docker-credential-helpers
    pkgs.mas
  ];

  # allow packages which are not open source
  nixpkgs.config.allowUnfree = true;

  # allow broken packages
  #nixpkgs.config.allowBroken = true;

  # needed because of determinate installer
  nix.enable = false;

  networking.hostName = hostName;
  networking.localHostName = hostName;
  networking.computerName = hostName;

  users.users.${username}.home = homeDirectory;

  # Necessary for using flakes on this system.
  # manages now by determinate
  #nix.settings.experimental-features = "nix-command flakes";

  # enable zsh integration
  programs.zsh = {
    enable = true;
  };

  # Set Git commit hash for darwin-version.
  system.configurationRevision = null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # enables touch id authentication in shell
  security.pam.services.sudo_local.touchIdAuth = true;

  launchd.daemons.nix-daemon.serviceConfig = {
    SoftResourceLimits.NumberOfFiles = 65536;
    HardResourceLimits.NumberOfFiles = 65536;
  };

  # Minutes is launched by macOS and does not inherit the interactive shell PATH.
  launchd.user.envVariables.MINUTES_FFMPEG = "/etc/profiles/per-user/${username}/bin/ffmpeg";

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # install homebrew apps
  # BEWARE! if onActivation.cleanup is set to "zap" this will delete homebrew
  # apps not managed via nix. This should be the case but list all homebrew apps
  # currently installed below (brew list)
  homebrew = {
    enable = true;
    prefix = "/opt/homebrew";
    onActivation.cleanup = "zap";
    onActivation.autoUpdate = false;
    onActivation.upgrade = true;
    taps = [
      # These taps are provided by nix-homebrew below, but must also be listed
      # in the Brewfile so `brew bundle --cleanup` does not try to untap them.
      {
        name = "homebrew/core";
      }
      {
        name = "homebrew/cask";
      }
      {
        name = "azure/azd";
        trusted = true;
      }
      {
        name = "silverstein/tap";
        trusted = true;
      }
    ];
    brews = [
      "docker-credential-helper"
      "mas"
      "azd"
      "ollama"
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
    ];
    # apps from the apple app store. use cli tool mas to search the numbers
    # mas search <app name>
    # the name on the left is arbitrary
    masApps = {
      "Goodnotes" = 1444383602;
      "1Password-Safari" = 1569813296;
      "WireGuard" = 1451685025;
    };
  };

  system.primaryUser = username;

  system.defaults = {
    # hide the dock
    dock.autohide = true;
    # macos will not rearrange the desktops you should really use this
    dock.mru-spaces = false;
    # size of the dock symbols
    dock.tilesize = 45;
    dock.largesize = 70;
    # magnification if hovering over dock
    dock.magnification = true;
    # Apps to be always in the dock
    dock.persistent-apps = [
      "/System/Cryptexes/App/System/Applications/Safari.app"
      #"/Applications/Brave Browser.app"
      # "${pkgs.ghostty}/Applications/Ghostty.app" # redo after stable again
      "/Applications/Ghostty.app"
      "/Applications/Slack.app"
      "/Applications/Microsoft Outlook.app"
      "/Applications/Microsoft Teams.app"
      "/Applications/Spotify.app"
      "/Applications/1Password.app"
    ];
    # sadly need to use CustomUserPreferences at the moment because you can not configure fan etc. here
    CustomUserPreferences = {
      # Disable opening Games/Arcade when long-pressing the controller Home/PS button.
      "com.apple.GameController" = {
        bluetoothPrefsMenuLongPressAction = 0;
      };

      # Sets Downloads folder with fan view in Dock
      "com.apple.dock" = {
        persistent-others = [
          {
            "tile-data" = {
              "file-data" = {
                "_CFURLString" = "${homeDirectory}/Downloads";
                "_CFURLStringType" = 0;
              };
              # Optional: sorting order
              # 1 -> Name | 2 -> Date Added | 3 -> Date Modified
              # 4 -> Date Created | 5 -> Kind
              "arrangement" = 2;
              # 0 -> Stack | 1 -> Folder
              "displayas" = 0;
              # 0 -> Automatic | 1 -> Fan | 2 -> Grid | 3 -> List
              "showas" = 1;
            };
            "tile-type" = "directory-tile";
          }
          {
            "tile-data" = {
              "file-data" = {
                "_CFURLString" = "/Applications";
                "_CFURLStringType" = 0;
              };
            };
            "tile-type" = "directory-tile";
          }
        ];
      };
    };

    # show extensions in finder!
    finder.AppleShowAllExtensions = true;
    # Change the default finder view.
    # "icnv" = Icon view, "Nlsv" = List view, "clmv" = Column View, "Flwv" = Gallery View
    # The default is icnv.
    finder.FXPreferredViewStyle = "Nlsv";
    # set login message
    loginwindow.LoginwindowText = "FullStacks Oida!";
    # Set F keys to be the default instead of the functions
    NSGlobalDomain."com.apple.keyboard.fnState" = true;
    # no show desktop on clicking wallpaper
    WindowManager.EnableStandardClickToShowDesktop = false;
    # show hidden files in finder
    # finder.AppleShowAllFiles = true;
    NSGlobalDomain.AppleShowAllFiles = true;
    # Change the default folder shown in Finder windows.
    # "Other" corresponds to the value of NewWindowTargetPath.
    # The default is unset ("Recents").
    finder.NewWindowTarget = "Other";
    # Sets the URI to open when NewWindowTarget is "Other".
    # Spaces and similar characters must be escaped.
    # If the value is invalid, Finder will open your home directory.
    finder.NewWindowTargetPath = "file://${homeDirectory}/Downloads";
    # Show path breadcrumbs in finder windows.
    # The default is false.
    finder.ShowPathbar = true;
    # Whether to show the full POSIX filepath in the window title.
    # The default is false.
    finder._FXShowPosixPathInTitle = true;
    # Keep folders on top when sorting by name.
    # The default is false.
    finder._FXSortFoldersFirst = true;
  };
}
