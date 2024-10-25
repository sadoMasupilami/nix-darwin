{
  description = "Michaels Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    configuration = { pkgs, ... }: {
      environment.systemPackages =
        [
          pkgs.yq-go
          pkgs.jq
          pkgs.lens
          pkgs.direnv
          pkgs.argocd
          pkgs.awscli2
          pkgs.signal-desktop
          pkgs.k9s
          # pkgs.azure-cli # currently not working
          pkgs.eza
          pkgs.fzf
          pkgs.fzf-zsh
          pkgs.zsh-fzf-tab
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
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 5;

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
    };
  in
  {
    darwinConfigurations."macos" = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };

    # Expose the package set, including overlays, for convenience.
    darwinPackages = self.darwinConfigurations."macos".pkgs;
  };
}
