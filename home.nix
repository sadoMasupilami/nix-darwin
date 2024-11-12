{ config, lib, pkgs, ... }:

{
  home.stateVersion = "23.11";

  home.packages = with pkgs; [
    unixtools.ifconfig
    unixtools.netstat
  ];

  programs.git = {
    enable = false;
    userName = "sadomasupilami";
    userEmail = "michiklug85@gmail.com";
    extraConfig = {
      github.user = "sadoMasupilami";
      init = { defaultBranch = "trunk"; };
      diff = { external = "${pkgs.difftastic}/bin/difft"; };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    history.share = false;
    syntaxHighlighting.enable = true;
    oh-my-zsh.enable = true;
    autocd = true;
    # if zsh startup time is slow, try this to debug
    # zprof.enable = true;
    initExtra = ''
      source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      source ${pkgs.terraform}/share/bash-completion/completions/terraform
      compdef __start_kubectl k
      compdef __start_helm h
      compdef __start_terraform t
      '';
    shellAliases = {
      ls="eza --icons --classify --group-directories-first";
      ll="ls -lh";
      l="ls -lah";
      la="ls -lah -a";
      k="kubectl";
      h="helm";
      t="terraform";
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
}
