# user wide comnfigiuration
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # basically never chnage this
  home.stateVersion = "23.11";

  # packages only installed for your user
  home.packages = with pkgs; [
    unixtools.ifconfig
    unixtools.netstat
    git
    awscli2
    yq-go
    jq
    direnv
    nix-direnv
    argocd
    argo-workflows
    k9s
    eza
    fzf
    zsh-fzf-tab
    oh-my-zsh
    zsh-powerlevel10k
    go
    kubectl
    kubernetes-helm
    kubectx
    wget
    tilt
    terraform
    terragrunt
    pre-commit
    inetutils
    zsh-autosuggestions
    zsh-syntax-highlighting
    docker-client
    skopeo
    tree
    nmap
    nix-index
    glab
    bat
    fd
    difftastic
    azure-cli
    kubeswitch
    rar
    talosctl
    kcat
    openshift
    nixd
    nixfmt
    uv
  ];

  # git configuration see this and follwing for options(https://nix-community.github.io/home-manager/options.xhtml#opt-programs.git.enable)
  programs.git = {
    enable = false;
    userName = "sadomasupilami"; # TODO: CHANGEME
    userEmail = "michiklug85@gmail.com"; # TODO: CHANGEME
    extraConfig = {
      github.user = "sadoMasupilami"; # TODO: CHANGEME
      init = {
        defaultBranch = "trunk";
      };
      diff = {
        external = "${pkgs.difftastic}/bin/difft";
      };
    };
  };

  # in depth zsh configuration see this and follwing for options(https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.enable)
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    autosuggestion.highlight = "fg=10"; # needed as my ghostty color scheme won't be seeable otherwise
    history = {
      ignoreDups = true;
      ignoreSpace = false;
      save = 100000;
      share = false;
      size = 100000;
    };
    syntaxHighlighting.enable = true;
    oh-my-zsh.enable = true;
    autocd = true;
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./config;
        file = "p10k.zsh";
      }
    ];
    initContent = ''
      source "$(fzf-share)/key-bindings.zsh"
      source "$(fzf-share)/completion.zsh"
      source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      source ${pkgs.terraform}/share/bash-completion/completions/terraform
      compdef __start_kubectl k
      compdef __start_helm h
      compdef __start_terraform t
      source <(switcher init zsh)
    '';
    shellAliases = {
      # beautiful ls
      ls = "eza --icons --classify --group-directories-first";
      ll = "ls -lh";
      l = "ls -lah";
      la = "ls -lah -a";
      # quicker aliases
      k = "kubectl";
      h = "helm";
      t = "terraform";
    };
  };

  # great fuzzy completion
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    #fileWidgetCommand = "fd --type f . $PWD";
    #fileWidgetOptions = [ "--preview 'bat --style=numbers --color=always --line-range :500 {}'" ];
    #think about using
    #changeDirWidgetCommand = "fd --type d . $PWD";
    #changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
  };

  # direnv with nix integration
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # add ~/.bin to your path so you can add your own scripts
  home.sessionPath = [ "$HOME/.bin" ];

  # Add this to create a Ghostty configuration file
  home.file.".config/ghostty/config" = {
    text = ''
      # Ghostty configuration content goes here
      font-family = "JetBrains Mono"
      theme = "iTerm2 Solarized Dark"
      window-height = 50
      window-width = 140
      window-inherit-working-directory = false
    '';
  };

  # kubeswitch configuration
  home.file.".kube/switch-config.yaml" = {
    text = ''
      kind: SwitchConfig
      version: v1alpha1
      kubeconfigStores:
      - kind: filesystem
        kubeconfigName: "*.yaml"
        showPrefix: true
        paths:
        - ~/Downloads
        - ~/.kube/
      #- kind: rancher
      #  id: rancher-internal
      #  config:
      #    rancherAPIAddress: https://rancher-internal.lab.cloudstacks.eu/v3
      #    rancherToken: token-9lt57:XXXXX
      #  cache:
      #    kind: filesystem
      #    config:
      #      path: ~/.kube/cache
      #- kind: eks
      #  id: fullstacks-aws
      #  config:
      #    profile: default
      #    region: eu-central-1
      - kind: azure
        id: fullstacks-azure
        config:
          subscriptionID: 0ac1cdf8-3f0b-400e-9059-c7f09e51be66
    '';
  };

  # needed as long as ghossty config is not propagated through ncurses
  home.file.".ssh/config" = {
    text = ''
      Host *
        SetEnv TERM=xterm-256color
      Include ~/.config/devpod/ssh.config
    '';
  };

  # update nix config
  home.file.".bin/nix-config-update" = {
    executable = true;
    text = ''
      cd ~/.config/nix-darwin
      nix flake update
    '';
  };

  # apply nix config
  home.file.".bin/nix-config-apply" = {
    executable = true;
    text = ''
      sudo darwin-rebuild switch --flake ~/.config/nix-darwin#macos
    '';
  };

  #  # helm repos
  #  xdg.configFile."helm/repositories.yaml".text = let
  #    # define all your repos here
  #    repos = {
  #      argo     = "https://argoproj.github.io/argo-helm";
  #      bitnami  = "https://charts.bitnami.com/bitnami";
  #      # …add more if you like
  #    };
  #
  #    # get the list of names ("argo", "bitnami", …)
  #    names = lib.attrNames repos;
  #
  #    # for each name produce a YAML item string
  #    entries = lib.concatStringsSep "\n" (lib.map (name:
  #      "  - name: ${name}\n    url: ${repos.${name}}"
  #    ) names);
  #  in ''
  #    apiVersion: v1
  #    generated: 0001-01-01T00:00:00Z
  #    repositories:
  #${entries}
  #  '';
}
