{ pkgs, ... }: {
  environment.systemPackages =
    [
      #pkgs.awscli2
      pkgs.yq-go
      pkgs.jq
      pkgs.lens
      pkgs.direnv
      pkgs.nix-direnv
      pkgs.argocd
      pkgs.signal-desktop
      pkgs.k9s
      # pkgs.azure-cli # currently not working
      pkgs.eza
      pkgs.fzf
      pkgs.fzf-zsh
      pkgs.zsh-fzf-tab
      pkgs.oh-my-zsh
      pkgs.zsh-powerlevel10k
      pkgs.go
      pkgs.kubectl
      pkgs.kubernetes-helm
      pkgs.kubectx
      pkgs.wget
      pkgs.unixtools.watch
      pkgs.tilt
      pkgs.terraform
      pkgs.terragrunt
      pkgs.pre-commit
      pkgs.inetutils
      pkgs.zsh-autosuggestions
      pkgs.zsh-syntax-highlighting
      pkgs.snyk
      pkgs.vscode
      pkgs.docker-client
      pkgs.tree
      pkgs.raycast
      pkgs.discord
      pkgs.mas
      pkgs.iterm2
      pkgs.slack
      # kgs.telegram-desktop # currently not working
      pkgs.nmap
      pkgs.nix-index
    ];

  # allow packages which are not open source
  nixpkgs.config.allowUnfree = true;

  users.users.michaelklug.home = "/Users/michaelklug";

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh = {
    enable = true;
  };

  # Set Git commit hash for darwin-version.
  system.configurationRevision = null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  nix.configureBuildUsers = true;

  # enables touch id authentication in shell
  security.pam.enableSudoTouchIdAuth = true;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    onActivation.autoUpdate = true;
    onActivation.upgrade = true;
    casks = [
      "1password"
      "roon"
      "microsoft-office"
      "microsoft-auto-update"
      "microsoft-remote-desktop"
      "microsoft-teams"
      "devpod"
      "jetbrains-toolbox"
      "obs"
      "sony-ps-remote-play"
      "qobuz"
      "rancher"
      "telegram"
      "tidal"
      "whatsapp"
      "wifiman"
      "google-chrome"
      "steam"
      "doll"
    ];
    masApps = {
      "Goodnotes" = 1444383602;
    };
  };

  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false; # i love this, macos will not rearrange the desktops
    dock.magnification = true;
    dock.persistent-apps = [
      "${pkgs.google-chrome}/Applications/Google Chrome.app"
      "${pkgs.iterm2}/Applications/iTerm2.app"
      "${pkgs.slack}/Applications/Slack.app"
      "/Applications/Microsoft Outlook.app"
      "/Applications/Microsoft Teams.app"
      "/Applications/Roon.app"
      "/Applications/1Password.app"
    ];
    dock.persistent-others = [
      # sadly need to use CustomUserPreferences at the moment because you can not configure fan etc. here
      #"/Users/michaelklug/Downloads"
      #"/Applications"
    ];
    CustomUserPreferences = {
      # Sets Downloads folder with fan view in Dock
      "com.apple.dock" = {
        persistent-others = [
          {
            "tile-data" = {
              "file-data" = {
                "_CFURLString" = "/Users/michaelklug/Downloads"; # TODO: don't hardcode this
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

    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "clmv"; # does not work

    loginwindow.LoginwindowText = "FullStacks Oida!";
  };
}
