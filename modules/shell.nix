{
  config,
  lib,
  pkgs,
  ...
}:
let
  # hasconfig globs are case-sensitive while GitHub owner names are not, so
  # both spellings in use are listed. `/**` matches every repository below.
  personalRemotes =
    lib.concatMap
      (owner: [
        "https://github.com/${owner}/**"
        "git@github.com:${owner}/**"
      ])
      [
        "sadoMasupilami"
        "sadomasupilami"
      ];
in
{
  programs = {
    git = {
      enable = true;
      settings = {
        # Work identity by default; personal repositories override it below.
        user = {
          name = "michaelklug";
          email = "michael.klug@fullstacks.io";
        };
        github.user = "sadoMasupilami";
        init.defaultBranch = "main";
        pull.rebase = true;
        # `git diff` stays a plain patch; structural diffs via `git dft`.
        alias.dft = "-c diff.external=${lib.getExe config.programs.difftastic.package} diff";
        difftool.prompt = false;
      };
      includes =
        map (url: {
          condition = "hasconfig:remote.*.url:${url}";
          contents.user = {
            name = "sadomasupilami";
            email = "michiklug85@gmail.com";
          };
        }) personalRemotes
        ++ [
          # Unmanaged, unpublished machine-local settings such as customer hosts
          # with http.<url>.sslVerify. Included last so it overrides the above.
          { path = "~/.config/git/local.conf"; }
        ];
    };

    difftastic = {
      enable = true;
      git = {
        enable = true;
        mode = "difftool";
      };
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion = {
        enable = true;
        # Keep suggestions legible with the configured Ghostty color scheme.
        highlight = "fg=10";
      };
      history = {
        ignoreDups = true;
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
          # Plugin directories also land on PATH and fpath, so ship only the file.
          name = "powerlevel10k-config";
          src = lib.fileset.toSource {
            root = ../config;
            fileset = ../config/p10k.zsh;
          };
          file = "p10k.zsh";
        }
      ];
      initContent = lib.mkMerge [
        (lib.mkBefore ''
          # powerlevel10k instant prompt; keep it at the top of .zshrc.
          if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
            source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
          fi
        '')
        ''
          source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh

          # Alt/Option+Left/Right word navigation (WSL terminals often send these).
          bindkey '^[b' backward-word
          bindkey '^[f' forward-word
          bindkey '^[[1;3D' backward-word
          bindkey '^[[1;3C' forward-word
          bindkey '^[[1;5D' backward-word
          bindkey '^[[1;5C' forward-word

          autoload -U bashcompinit && bashcompinit
          complete -o nospace -C ${pkgs.terraform}/bin/terraform terraform
        ''
      ];
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

    # Generates the shell function and its completion at build time instead
    # of running `switcher init` on every shell start.
    kubeswitch = {
      enable = true;
      # Keep the command name in use instead of the module default `kswitch`.
      commandName = "switch";
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  home.sessionPath = [ "$HOME/.bin" ];
}
