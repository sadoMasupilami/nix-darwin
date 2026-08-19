{ lib, pkgs, ... }:
{
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

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      # Keep suggestions legible with the configured Ghostty color scheme.
      highlight = "fg=10";
    };
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
        src = lib.cleanSource ../config;
        file = "p10k.zsh";
      }
    ];
    initContent = ''
      source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh

      # Alt/Option+Left/Right word navigation (WSL terminals often send these).
      bindkey '^[b' backward-word
      bindkey '^[f' forward-word
      bindkey '^[[1;3D' backward-word
      bindkey '^[[1;3C' forward-word
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word

      source ${pkgs.terraform}/share/bash-completion/completions/terraform

      if [[ "$OSTYPE" == darwin* ]]; then
        compdef __start_kubectl k
        compdef __start_helm h
        compdef __start_terraform t
      fi

      source <(switcher init zsh)
    '';
    shellAliases = {
      ls = "eza --icons --classify --group-directories-first";
      ll = "ls -lh";
      l = "ls -lah";
      la = "ls -lah -a";
      k = "kubectl";
      h = "helm";
      t = "terraform";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.sessionPath = [ "$HOME/.bin" ];
}
