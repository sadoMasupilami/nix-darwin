#!/usr/bin/env bash
set -euo pipefail

minutes_bin=/opt/homebrew/bin/minutes
if [[ ! -x "$minutes_bin" ]]; then
  echo "Minutes is not installed yet; run nix-config-apply first." >&2
  exit 1
fi

"$minutes_bin" setup --model large-v3
"$minutes_bin" setup --diarization
"$minutes_bin" health
