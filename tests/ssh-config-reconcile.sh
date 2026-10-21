#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
program="$repo_root/config/ssh/reconcile-ssh-config.awk"
managed='Include ~/.ssh/config.d/nix-darwin.conf'
fixture=$(mktemp -d "${TMPDIR:-/tmp}/ssh-config-reconcile-tests.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

reconcile() {
  awk -v managed="$managed" -f "$program" "$1"
}

# Compares the reconciled input with the expected file byte for byte, then
# checks that a second pass over the result changes nothing.
check() {
  local name=$1
  local input=$2
  local expected="$fixture/$name.expected"
  local actual="$fixture/$name.actual"
  local again="$fixture/$name.again"

  cat >"$expected"
  reconcile "$input" >"$actual"
  if ! cmp -s "$expected" "$actual"; then
    diff -u "$expected" "$actual" >&2 || true
    fail "$name: unexpected result"
  fi
  reconcile "$actual" >"$again"
  cmp -s "$actual" "$again" || fail "$name: a second run changed the result"
}

fixture_file() {
  cat >"$fixture/$1.in"
  printf '%s\n' "$fixture/$1.in"
}

# A missing config is read as /dev/null by the activation.
check missing /dev/null <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
EOF

check empty "$(fixture_file empty </dev/null)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
EOF

# The live layout: Coder keeps its include block on top, the managed include
# follows. Nothing may move, or each activation and Coder connect would
# rewrite the file again.
reconciled=$(fixture_file reconciled <<'EOF'
# --- START CODER INCLUDE CODER-REMOTE ---
# Managed by the Coder extension for VS Code and its forks.
# Moves back to the top on connect; override options via coder.sshConfig.
Include "~/Library/Application Support/coder.coder-remote/ssh/*.conf"
# --- END CODER INCLUDE CODER-REMOTE ---

Include ~/.ssh/config.d/nix-darwin.conf
EOF
)
reconcile "$reconciled" | cmp -s - "$reconciled" || fail 'reconciled: an already reconciled file changed'

check old-inline-block "$(fixture_file old-inline-block <<'EOF'
Host *
  SetEnv TERM=xterm-256color
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
EOF

check old-inline-block-after-host "$(fixture_file old-inline-block-after-host <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf

Host coder.workspace
  HostName 10.0.0.5

Host *
  SetEnv TERM=xterm-256color

Match host build-*
  User ci
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf

Host coder.workspace
  HostName 10.0.0.5

Match host build-*
  User ci
EOF

# The remaining options of a `Host *` block must stay under their own header
# instead of being attached to the preceding Host.
check host-star-with-options "$(fixture_file host-star-with-options <<'EOF'
Host coder.workspace
  HostName 10.0.0.5

Host *
  SetEnv TERM=xterm-256color
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  ServerAliveInterval 30
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
Host coder.workspace
  HostName 10.0.0.5

Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  ServerAliveInterval 30
EOF

check host-star-setenv-later "$(fixture_file host-star-setenv-later <<'EOF'
Host *
  ForwardAgent no
  SetEnv TERM=xterm-256color
Host other
  HostName other.example
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
Host *
  ForwardAgent no
Host other
  HostName other.example
EOF

check devpod-include "$(fixture_file devpod-include <<'EOF'
Include ~/.config/devpod/ssh.config
Include ~/.ssh/config.d/nix-darwin.conf

Host build
  HostName build.example
  Include ~/.config/devpod/ssh.config
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf

Host build
  HostName build.example
EOF

# Coder blocks pass through untouched, including a TERM setting that does not
# belong to a `Host *` block.
check coder-blocks "$(fixture_file coder-blocks <<'EOF'
# --- START CODER VSCODE coder.example.com ---
Host coder-vscode.coder.example.com--*
  ConnectTimeout 0
  LogLevel ERROR
  ProxyCommand "/Users/me/Library/Application Support/Code/User/globalStorage/coder.coder-remote/bin/coder" ssh --stdio %h
  SetEnv CODER_SSH_SESSION_TYPE=vscode
  SetEnv TERM=xterm-256color
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
# --- END CODER VSCODE coder.example.com ---
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
# --- START CODER VSCODE coder.example.com ---
Host coder-vscode.coder.example.com--*
  ConnectTimeout 0
  LogLevel ERROR
  ProxyCommand "/Users/me/Library/Application Support/Code/User/globalStorage/coder.coder-remote/bin/coder" ssh --stdio %h
  SetEnv CODER_SSH_SESSION_TYPE=vscode
  SetEnv TERM=xterm-256color
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
# --- END CODER VSCODE coder.example.com ---
EOF

# Below a Host line the include would only apply to that host, so it moves to
# the top; duplicates collapse into one.
check scoped-include "$(fixture_file scoped-include <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
Include ~/.ssh/config.d/nix-darwin.conf
Host jump
  HostName jump.example
Include ~/.ssh/config.d/nix-darwin.conf
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
Host jump
  HostName jump.example
EOF

check include-after-host "$(fixture_file include-after-host <<'EOF'
Host jump
  HostName jump.example
Include ~/.ssh/config.d/nix-darwin.conf
EOF
)" <<'EOF'
Include ~/.ssh/config.d/nix-darwin.conf
Host jump
  HostName jump.example
EOF

# Coder writes the file without a final newline. The activation treats that as
# equal, which relies on the output differing by exactly that newline.
printf '%s' "$managed" >"$fixture/no-final-newline.in"
reconcile "$fixture/no-final-newline.in" \
  | cmp -s - <(cat "$fixture/no-final-newline.in"; printf '\n') \
  || fail 'no-final-newline: output differs by more than the final newline'

# Without the managed value, blank lines would be matched and dropped.
if awk -f "$program" "$reconciled" >"$fixture/no-managed.out" 2>/dev/null; then
  fail 'missing -v managed was accepted'
fi
[[ ! -s "$fixture/no-managed.out" ]] || fail 'missing -v managed still printed output'

printf 'ssh config reconcile tests passed\n'
