#!/usr/bin/env bash
# Lints the given files: the pre-commit hook and the flake's "shell" check both
# run this. A file counts as a script only by a real shebang on line 1: zsh
# scripts go through `zsh -n`, bash and sh scripts through ShellCheck. Files
# without a shebang (sourced libraries, templates) are checked by name: *.zsh
# with `zsh -n`, *.sh and *.sh.in as Bash. Anything else is skipped. Every
# failing file is reported, not just the first one.
set -euo pipefail

status=0
# -x follows `source` into lib.sh, so variables it defines are known.
lint() {
  shellcheck --external-sources --source-path=SCRIPTDIR --severity=warning "$@" || status=1
}
parse_zsh() {
  zsh -n "$1" || status=1
}

for file in "$@"; do
  first_line=
  IFS= read -r first_line <"$file" || true

  if [[ $first_line =~ ^#!.*[/[:space:]]zsh([[:space:]]|$) ]]; then
    parse_zsh "$file"
  elif [[ $first_line =~ ^#!.*[/[:space:]](ba)?sh([[:space:]]|$) ]]; then
    lint "$file"
  elif [[ $first_line != '#!'* ]]; then
    case "$file" in
      *.zsh) parse_zsh "$file" ;;
      *.sh | *.sh.in) lint --shell=bash "$file" ;;
    esac
  fi
done

exit "$status"
