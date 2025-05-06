# macos wide configuration

# global packages to install system wide (all users)
{ pkgs, ... }: {
  environment.systemPackages =
    [
      pkgs.awscli2
      pkgs.yq-go
      pkgs.jq
      pkgs.lens
      pkgs.direnv
      pkgs.nix-direnv
      pkgs.argocd
      # pkgs.signal-desktop # currently not working
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
      # pkgs.snyk # curretnly not working
      pkgs.vscode
      pkgs.docker-client
      pkgs.tree
      pkgs.discord
      pkgs.mas
      pkgs.iterm2
      pkgs.slack
      # kgs.telegram-desktop # currently not working
      pkgs.nmap
      pkgs.nix-index
      pkgs.glab
      pkgs.bat
      pkgs.fd
      pkgs.difftastic
#      pkgs.ghostty # currently not building remove from brew again if working
      pkgs.azure-cli
      pkgs.kubeswitch
      pkgs.rar
    ];

  # allow packages which are not open source e.g. terraform
  nixpkgs.config.allowUnfree = true;

  # allow broken packages
  nixpkgs.config.allowBroken = true;

  # needed because of determinate installer
  nix.enable = false;

  networking.hostName = "fs-macbook-pro-m4";
  networking.localHostName = "fs-macbook-pro-m4";
  networking.computerName = "fs-macbook-pro-m4";

  users.users.michaelklug.home = "/Users/michaelklug";

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

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

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # install homebrew apps
  # BEWARE! if onActivation.cleanup is set to "zap" this will delete homebrew
  # apps not managed via nix. This should be the case but list all homebrew apps
  # currently installed below (brew list)
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    onActivation.autoUpdate = true;
    onActivation.upgrade = true;
    brews = [
      "docker-credential-helper"
      "mas"
    ];
    casks = [
      "1password"
      "roon"
      "microsoft-office"
      "microsoft-auto-update"
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
      "steam"
      "calibre"
      "windows-app"
      "chatgpt"
      "google-chrome"
      "ghostty" # remove me after working again from the nix store
      "raycast" # remove if it works via nix pkgs
      "brave-browser"
      "commander-one"
      "daisydisk"
      "bartender"
      "webex"
    ];
    # apps from the apple app store. use cli tool mas to search the numbers
    # mas search <app name>
    # the name on the left is arbitrary
    masApps = {
      "Goodnotes" = 1444383602;
      "1Password-Safari" = 1569813296;
      "Harvest" = 506189836;
    };
  };

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
      #"/System/Cryptexes/App/System/Applications/Safari.app"
      "/Applications/Brave Browser.app"
      # "${pkgs.ghostty}/Applications/Ghostty.app" # redo after stable again
      "/Applications/Ghostty.app"
      "${pkgs.slack}/Applications/Slack.app"
      "/Applications/Microsoft Outlook.app"
      "/Applications/Microsoft Teams.app"
      "/Applications/Roon.app"
      "/Applications/1Password.app"
    ];
    # sadly need to use CustomUserPreferences at the moment because you can not configure fan etc. here
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

    # show extensions in finder!
    finder.AppleShowAllExtensions = true;
    # column view, use clmv: Column view | Nlsv: List view |
    # glyv gallery view | icnv icon view (default)
    finder.FXPreferredViewStyle = "clmv";
    # set login message
    loginwindow.LoginwindowText = "FullStacks Oida!";
    # Set F keys to be the default instead of the functions
    NSGlobalDomain."com.apple.keyboard.fnState" = true;
    # no show desktop on clicking wallpaper
    WindowManager.EnableStandardClickToShowDesktop = false;
  };
}
