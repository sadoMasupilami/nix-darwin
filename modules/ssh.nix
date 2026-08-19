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
}
