{ lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  # macOS only lacks telnet. All of inetutils would shadow Apple's ifconfig,
  # ping, traceroute, hostname, whois and logger.
  inetutilsTelnet = pkgs.runCommandLocal "inetutils-telnet" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.inetutils}/bin/telnet "$out/bin/telnet"
  '';
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
      go
      kubectl
      kubernetes-helm
      wget
      tilt
      terraform
      terragrunt
      pre-commit
      # On macOS, Rancher Desktop provides the daemon and links the compose and
      # buildx plugins into ~/.docker/cli-plugins.
      docker-client
      skopeo
      tree
      nmap
      glab
      gh
      bat
      fd
      azure-cli
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
    ++ lib.optionals isDarwin [ inetutilsTelnet ]
    ++ lib.optionals (!isDarwin) [ inetutils ];
}
