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

  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    dock.persistent-apps = [
      "/Applications/Roon.app"
    ];
    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "clmv"; # does not work
    loginwindow.LoginwindowText = "FullStacks Oida!";
  };

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
    ];
    masApps = {
      "Goodnotes" = 1444383602;
    };
  };
}
