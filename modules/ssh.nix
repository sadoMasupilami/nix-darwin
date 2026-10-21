{
  config,
  lib,
  pkgs,
  ...
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  # Keep stable SSH defaults in a managed fragment. ~/.ssh/config itself stays
  # writable because the Coder VS Code extension adds dynamic Host blocks.
  home.file.".ssh/config.d/nix-darwin.conf" = lib.mkIf isDarwin {
    text = ''
      Host *
        SetEnv TERM=xterm-256color
    '';
  };

  # Reconcile the mutable main SSH config after Home Manager has linked the
  # fragment. The awk program adds the managed include, preserves Coder blocks,
  # and removes the old inline TERM setting and the obsolete DevPod include.
  # The file is only replaced when the result differs, so this is idempotent.
  home.activation.reconcileSshConfig = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ssh_dir="${config.home.homeDirectory}/.ssh"
      ssh_config="$ssh_dir/config"

      reconcile_ssh_config() {
        local input=/dev/null
        if [[ -f "$ssh_config" ]]; then
          input=$ssh_config
        fi
        ${pkgs.gawk}/bin/awk \
          -v managed='Include ~/.ssh/config.d/nix-darwin.conf' \
          -f ${../config/ssh/reconcile-ssh-config.awk} "$input"
      }

      # Coder writes the file without a final newline, which alone is no
      # reason to rewrite it.
      current_ssh_config() {
        if [[ -f "$ssh_config" ]]; then
          cat "$ssh_config"
          if [[ -n "$(tail -c 1 "$ssh_config")" ]]; then
            printf '\n'
          fi
        fi
      }

      if ! reconcile_ssh_config | cmp -s - <(current_ssh_config); then
        if [[ -v DRY_RUN ]]; then
          verboseEcho "Would reconcile $ssh_config"
        else
          run mkdir -p -m 700 "$ssh_dir"
          ssh_config_tmp=$(mktemp "$ssh_dir/.config.XXXXXX")
          reconcile_ssh_config > "$ssh_config_tmp"
          chmod 600 "$ssh_config_tmp"
          mv -f "$ssh_config_tmp" "$ssh_config"
        fi
      fi
    ''
  );
}
