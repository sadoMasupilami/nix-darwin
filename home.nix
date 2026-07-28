{
  config,
  lib,
  pkgs,
  repoDirectory,
  ...
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  imports = [ ./minutes.nix ];

  # basically never change this
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
    #argocd
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
    devenv
    istioctl
    dive
    kind
  ];

  # git configuration see this and following for options(https://nix-community.github.io/home-manager/options.xhtml#opt-programs.git.enable)
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "sadomasupilami";
        email = "michiklug85@gmail.com";
      };
      github.user = "sadoMasupilami";
      init.defaultBranch = "trunk";
      diff.external = "${pkgs.difftastic}/bin/difft";
    };
  };

  # in depth zsh configuration see this and following for options(https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.enable)
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

      # Alt/Option+Left/Right word navigation (WSL terminals often send these)
      bindkey '^[b' backward-word
      bindkey '^[f' forward-word
      bindkey '^[[1;3D' backward-word
      bindkey '^[[1;3C' forward-word
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word

      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      source ${pkgs.terraform}/share/bash-completion/completions/terraform

      if [[ "$OSTYPE" == darwin* ]]; then
        compdef __start_kubectl k
        compdef __start_helm h
        compdef __start_terraform t
      fi

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

  # Raycast Teams caller: people list (NOT managed by Nix; keep it out of the repo)
  # Create this file manually on the machine at:
  #   ~/.config/raycast/teams-people.csv
  # Format (CSV):
  #   name,email,tenantId
  # Lines starting with '#' are treated as comments. Example:
  #   # name,email,tenantId
  #   Jane Doe,jane.doe@company.com,aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee

  # Raycast: tenant-pinned Teams video call picker (Script Command)
  home.file.".config/raycast/scripts/teams-video-call.sh" = lib.mkIf isDarwin {
    executable = true;
    text = builtins.readFile ./config/raycast/teams-video-call.sh;
  };

  # Keep stable SSH defaults in a managed fragment. ~/.ssh/config itself stays
  # writable because the Coder VS Code extension adds dynamic Host blocks.
  home.file.".ssh/config.d/nix-darwin.conf" = lib.mkIf isDarwin {
    text = ''
      Host *
        SetEnv TERM=xterm-256color
    '';
  };

  # Reconcile the mutable main SSH config after Home Manager has linked the
  # fragment. This is idempotent, preserves Coder blocks, and removes the old
  # inline TERM block and obsolete DevPod include.
  home.activation.reconcileSshConfig = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ssh_dir="${config.home.homeDirectory}/.ssh"
      ssh_config="$ssh_dir/config"
      managed_include='Include ~/.ssh/config.d/nix-darwin.conf'

      $DRY_RUN_CMD mkdir -p "$ssh_dir"

      needs_update=false
      if [[ ! -f "$ssh_config" ]] \
        || ! grep -Fqx "$managed_include" "$ssh_config" \
        || grep -Eq '^[[:space:]]*Include[[:space:]]+~/\.config/devpod/ssh\.config[[:space:]]*$' "$ssh_config" \
        || grep -Eq '^[[:space:]]*SetEnv[[:space:]]+TERM=xterm-256color[[:space:]]*$' "$ssh_config"; then
        needs_update=true
      fi

      if [[ "$needs_update" == true ]]; then
        if [[ -n "$DRY_RUN_CMD" ]]; then
          $VERBOSE_ECHO "Would reconcile $ssh_config"
        else
          if [[ -f "$ssh_config" ]]; then
            ssh_config_content="$(${pkgs.gawk}/bin/awk -v managed="$managed_include" '
              BEGIN { print managed }
              {
                line = $0

                if (pending_host != "") {
                  if (line ~ /^[[:space:]]*SetEnv[[:space:]]+TERM=xterm-256color[[:space:]]*$/) {
                    pending_host = ""
                    next
                  }
                  print pending_host
                  pending_host = ""
                }

                if (line == managed) {
                  next
                }
                if (line ~ /^[[:space:]]*Include[[:space:]]+~\/\.config\/devpod\/ssh\.config[[:space:]]*$/) {
                  next
                }
                if (line ~ /^[[:space:]]*Host[[:space:]]+\*[[:space:]]*$/) {
                  pending_host = line
                  next
                }

                print line
              }
              END {
                if (pending_host != "") {
                  print pending_host
                }
              }
            ' "$ssh_config")"
          else
            ssh_config_content="$managed_include"
          fi

          ssh_config_tmp=$(mktemp "$ssh_dir/.config.XXXXXX")
          printf '%s\n' "$ssh_config_content" > "$ssh_config_tmp"
          chmod 600 "$ssh_config_tmp"
          mv -f "$ssh_config_tmp" "$ssh_config"
        fi
      fi
    ''
  );

  # update nix config
  home.file.".bin/nix-config-update" = {
    executable = true;
    text =
      if isDarwin then
        ''
          #!/usr/bin/env bash
          set -euo pipefail
          ulimit -n 65536 2>/dev/null || true

          cd "${repoDirectory}"
          nix flake update

          # Homebrew core/cask taps are nix-homebrew flake inputs. Updating them
          # happens above; applying them happens during darwin-rebuild activation.

          if command -v mas >/dev/null 2>&1; then
            mas upgrade
          fi
        ''
      else if isLinux then
        ''
          #!/usr/bin/env bash
          set -euo pipefail
          ulimit -n 65536 2>/dev/null || true

          cd "${repoDirectory}/home-manager"
          nix flake update
        ''
      else
        throw "Unsupported platform for nix-config-update";
  };

  # apply nix config
  home.file.".bin/nix-config-apply" = {
    executable = true;
    text =
      if isDarwin then
        ''
          #!/usr/bin/env bash
          set -euo pipefail
          ulimit -n 65536 2>/dev/null || true

          sudo darwin-rebuild switch --flake "${repoDirectory}#macos"
          nix-collect-garbage
        ''
      else if isLinux then
        ''
          #!/usr/bin/env bash
          set -euo pipefail
          ulimit -n 65536 2>/dev/null || true

          cd "${repoDirectory}/home-manager"
          nix shell nixpkgs#home-manager -c home-manager switch --flake .#default
          nix-collect-garbage
        ''
      else
        throw "Unsupported platform for nix-config-apply";
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
