{ homeDirectory, ... }:
{
  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;
      tilesize = 45;
      largesize = 70;
      magnification = true;
      persistent-apps = [
        "/System/Cryptexes/App/System/Applications/Safari.app"
        "/Applications/Ghostty.app"
        "/Applications/Slack.app"
        "/Applications/Microsoft Outlook.app"
        "/Applications/Microsoft Teams.app"
        "/Applications/Spotify.app"
        "/Applications/1Password.app"
      ];
    };

    CustomUserPreferences = {
      "com.apple.GameController".bluetoothPrefsMenuLongPressAction = 0;

      # SuperCmd v2 is installed outside Homebrew and updates itself. Only the
      # script keys are set; local-private-tools.nix installs the Teams script
      # there as a regular file.
      "com.supercmd.SuperCmd" = {
        "settings.scripts.enabled" = true;
        "settings.scripts.directories" = [ "${homeDirectory}/.config/raycast/scripts" ];
      };

      "com.apple.dock".persistent-others = [
        {
          "tile-data" = {
            "file-data" = {
              "_CFURLString" = "${homeDirectory}/Downloads";
              "_CFURLStringType" = 0;
            };
            arrangement = 2;
            displayas = 0;
            showas = 1;
          };
          "tile-type" = "directory-tile";
        }
        {
          "tile-data"."file-data" = {
            "_CFURLString" = "/Applications";
            "_CFURLStringType" = 0;
          };
          "tile-type" = "directory-tile";
        }
      ];
    };

    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "Nlsv";
      NewWindowTarget = "Other";
      NewWindowTargetPath = "file://${homeDirectory}/Downloads";
      ShowPathbar = true;
      _FXShowPosixPathInTitle = true;
      _FXSortFoldersFirst = true;
    };

    loginwindow.LoginwindowText = "FullStacks Oida!";
    NSGlobalDomain = {
      "com.apple.keyboard.fnState" = true;
      AppleShowAllFiles = true;
    };
    WindowManager.EnableStandardClickToShowDesktop = false;
  };
}
