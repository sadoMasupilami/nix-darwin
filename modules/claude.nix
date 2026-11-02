{ pkgs, ... }:
let
  # Claude Code against the FULLSTACKS endpoint. Only the two FULLSTACKS
  # values are read from ~/secrets.env, so the other secrets stay out of the
  # environment.
  fs-claude = pkgs.writeShellApplication {
    name = "fs-claude";
    text = ''
      secrets="$HOME/secrets.env"
      # shellcheck source=/dev/null
      base_url=$(. "$secrets" && printf '%s' "''${FULLSTACKS_ANTHROPIC_BASE_URL:?missing in $secrets}")
      # shellcheck source=/dev/null
      auth_token=$(. "$secrets" && printf '%s' "''${FULLSTACKS_ANTHROPIC_AUTH_TOKEN:?missing in $secrets}")

      # A leftover API key would compete with the auth token.
      unset ANTHROPIC_API_KEY
      export ANTHROPIC_BASE_URL="$base_url" ANTHROPIC_AUTH_TOKEN="$auth_token"
      exec claude "$@"
    '';
  };
in
{
  # Global instructions Claude Code loads in every session.
  home.file.".claude/CLAUDE.md".source = ../config/claude/CLAUDE.md;

  home.packages = [ fs-claude ];
}
