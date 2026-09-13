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

  # The installed helpers live in the Nix store and get NIX_CONFIG_REPO from
  # their wrapper. Running config/nix-config/<helper> from a checkout resolves
  # that checkout instead.
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

# Nix copies the tracked working-tree contents into its immutable store. Reuse
# that exact path for checks and activation, even if the checkout changes
# meanwhile. A clean checkout also passes its commit on, so the generation
# keeps its configurationRevision; a dirty tree stays unlabeled.
nix_config_snapshot() {
  local git_ref
  local metadata
  local store_path
  local rev
  git_ref=$(nix_config_git_flake_ref "$1")
  # `nix flake metadata` reports no store path once lazy trees are enabled
  # (the Determinate Nix default); `prefetch` always materializes the tree.
  metadata=$(nix flake prefetch --json "$git_ref") || return
  store_path=$(jq -er '.storePath | select(startswith("/nix/store/"))' <<<"$metadata") || return
  rev=$(jq -r '.locked.rev // empty' <<<"$metadata") || return
  if [[ -n "$rev" && ! "$rev" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'error: unexpected snapshot revision: %s\n' "$rev" >&2
    return 2
  fi
  printf 'path:%s%s\n' "$store_path" "${rev:+?rev=$rev}"
}
