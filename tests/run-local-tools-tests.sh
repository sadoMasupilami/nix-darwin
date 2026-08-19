#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

zsh -n config/qwen-meeting/qwen-meeting config/qwen-meeting/qwen-meeting-setup
bash -n config/raycast/teams-video-call.sh
PYTHONDONTWRITEBYTECODE=1 python3.13 tests/qwen-fetch-models.py
PYTHONDONTWRITEBYTECODE=1 python3.13 tests/test_local_tools.py
uv lock --check --offline --project config/qwen-meeting/runtime --no-python-downloads
