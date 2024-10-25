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
    enableCompletion = true;
    enableBashCompletion = true;
    enableFzfCompletion = true;
    enableSyntaxHighlighting = true;
  };

  programs.bash = {
    enable = true;
    completion.enable = true;
  };

  # Set Git commit hash for darwin-version.
  system.configurationRevision = null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  nix.configureBuildUsers = true;

  # enables touc id authentication in shell
  security.pam.enableSudoTouchIdAuth = true;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "clmv"; # does not work
    loginwindow.LoginwindowText = "FullStacks Oida!";
  };
}
