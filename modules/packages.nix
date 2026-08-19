{ lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  home.packages =
    with pkgs;
    [
      unixtools.ifconfig
      unixtools.netstat
      awscli2
      yq-go
      jq
      argo-workflows
      k9s
      eza
      zsh-fzf-tab
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
      ffmpeg
      ripgrep
    ]
    ++ lib.optionals isDarwin [ python313 ];
}
