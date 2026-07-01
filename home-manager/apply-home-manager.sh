#!/usr/bin/env nix-shell
#!nix-shell -i bash -p home-manager

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

home-manager switch --flake .#default

echo "home-manager switch executed successfully."
