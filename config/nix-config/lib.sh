#!/usr/bin/env bash

set -euo pipefail

nix_config_resolve_repo() {
  if [[ -n "${NIX_CONFIG_REPO:-}" ]]; then
    printf '%s\n' "$NIX_CONFIG_REPO"
    return
  fi

  local source_path=${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}
  local source_dir
  source_dir=$(cd -- "$(dirname -- "$source_path")" && pwd -P)

  # Repo checkout: config/nix-config/<helper>. Installed Home Manager links:
  # ~/.bin/<helper> -> <repo>/config/nix-config/<helper>.
  cd -- "$source_dir/../.." && pwd -P
}

nix_config_require_repo() {
  local repo=$1

  if [[ ! -f "$repo/flake.nix" || ! -f "$repo/flake.lock" ]]; then
    printf 'error: %s is not the nix-config repository\n' "$repo" >&2
    return 2
  fi

  if [[ ! -e "$repo/.git" ]]; then
    printf 'error: %s is not a Git checkout; refusing to copy an unfiltered path into the Nix store\n' "$repo" >&2
    return 2
  fi
}

nix_config_git_flake_ref() {
  local repo=$1
  local encoded=
  local byte
  local escaped
  local index
  local LC_ALL=C

  # A Git flake includes tracked working-tree changes but excludes ignored and
  # untracked files. Percent-encoding keeps unusual checkout paths valid URLs.
  for ((index = 0; index < ${#repo}; index++)); do
    byte=${repo:index:1}
    case "$byte" in
      [A-Za-z0-9.~_/-]) encoded+=$byte ;;
      *)
        printf -v escaped '%%%02X' "'$byte"
        encoded+=$escaped
        ;;
    esac
  done

  printf 'git+file://%s\n' "$encoded"
}

nix_config_usage_error() {
  printf 'error: %s\n' "$1" >&2
  return 2
}
