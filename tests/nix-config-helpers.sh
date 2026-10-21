#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/nix-config-helper-tests.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

# Exercise URL encoding so the production Git flake reference also works for
# checkout paths containing characters with URL semantics.
fake_repo="$fixture/repo with space#fragment"
fake_bin="$fixture/bin"
fake_homebrew="$fixture/homebrew-preflight"
fake_system="$fixture/darwin-system"
log_file="$fixture/commands.log"
mkdir -p "$fake_repo" "$fake_bin" "$fake_homebrew/bin" "$fake_system" "$fixture/tmp" "$fixture/homebrew-prefix"
printf '{}\n' >"$fake_repo/flake.nix"
mkdir "$fake_repo/.git"

# A lock with the real input layout: Homebrew's own taps, two third-party
# taps, nix-homebrew and an unrelated input.
cat >"$fixture/flake.lock" <<'EOF'
{
  "nodes": {
    "homebrew-azd": { "locked": { "type": "github", "owner": "Azure", "repo": "homebrew-azd", "rev": "a000000000000000000000000000000000000001" } },
    "homebrew-cask": { "locked": { "type": "github", "owner": "homebrew", "repo": "homebrew-cask", "rev": "c000000000000000000000000000000000000001" } },
    "homebrew-core": { "locked": { "type": "github", "owner": "homebrew", "repo": "homebrew-core", "rev": "d000000000000000000000000000000000000001" } },
    "homebrew-silverstein-tap": { "locked": { "type": "github", "owner": "silverstein", "repo": "homebrew-tap", "rev": "e000000000000000000000000000000000000001" } },
    "nix-homebrew": { "locked": { "type": "github", "owner": "zhaofengli", "repo": "nix-homebrew", "rev": "f000000000000000000000000000000000000001" } },
    "nixpkgs": { "locked": { "type": "tarball", "url": "https://example.test/nixpkgs.tar.gz" } },
    "root": {
      "inputs": {
        "homebrew-azd": "homebrew-azd",
        "homebrew-cask": "homebrew-cask",
        "homebrew-core": "homebrew-core",
        "homebrew-silverstein-tap": "homebrew-silverstein-tap",
        "nix-homebrew": "nix-homebrew",
        "nixpkgs": "nixpkgs"
      }
    }
  },
  "root": "root",
  "version": 7
}
EOF
cp "$fixture/flake.lock" "$fake_repo/flake.lock"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local needle=$1
  local file=$2
  grep -Fq -- "$needle" "$file" || fail "missing '$needle' in $file"
}

assert_not_contains() {
  local needle=$1
  local file=$2
  if grep -Fq -- "$needle" "$file"; then
    fail "unexpected '$needle' in $file"
  fi
}

assert_matches() {
  local pattern=$1
  local file=$2
  grep -Eq -- "$pattern" "$file" || fail "no line matches '$pattern' in $file"
}

assert_before() {
  local first=$1
  local second=$2
  local file=$3
  local first_match
  local second_match

  assert_contains "$first" "$file"
  assert_contains "$second" "$file"
  first_match=$(grep -Fnm1 -- "$first" "$file")
  second_match=$(grep -Fnm1 -- "$second" "$file")
  if (( ${first_match%%:*} >= ${second_match%%:*} )); then
    fail "'$first' did not precede '$second' in $file"
  fi
}

assert_count() {
  local expected=$1
  local needle=$2
  local file=$3
  local actual
  actual=$(grep -Fc -- "$needle" "$file" || true)
  [[ "$actual" == "$expected" ]] || fail "expected $expected lines with '$needle' in $file, got $actual"
}

# Fakes are created after the build's patchShebangs ran, and the Linux sandbox
# has no /usr/bin/env, so they use the interpreter running this test.
write_fake() {
  { printf '#!%s\n' "$BASH"; cat; } >"$1"
  chmod +x "$1"
}

# Every case starts from an empty log, the pristine lock file, Homebrew
# state that still needs its cleanup and activation checks that pass.
reset() {
  : >"$log_file"
  cp "$fixture/flake.lock" "$fake_repo/flake.lock"
  rm -f "$fixture/cleaned" "$fixture/activate-status"
}

write_fake "$fake_bin/nix" <<'EOF'
set -euo pipefail
printf 'nix' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"

if [[ " $* " == *' flake prefetch '* ]]; then
  if [[ "${FAKE_PREFETCH_STATUS:-0}" != 0 ]]; then exit "$FAKE_PREFETCH_STATUS"; fi
  rev_json=null
  if [[ -n "${FAKE_SNAPSHOT_REV:-}" ]]; then rev_json="\"$FAKE_SNAPSHOT_REV\""; fi
  if [[ -f "$NIX_CONFIG_REPO/mutated" ]]; then
    printf '{"storePath":"/nix/store/changed-source","locked":{"rev":%s}}\n' "$rev_json"
  else
    printf '{"storePath":"/nix/store/test-source","locked":{"rev":%s}}\n' "$rev_json"
  fi
fi

# The GC root for the snapshot itself.
if [[ " $* " == *' build --out-link '* ]] && [[ " $* " == *' /nix/store/'* ]]; then
  exit "${FAKE_ROOT_STATUS:-0}"
fi

if [[ " $* " == *' flake update '* ]] && [[ -n "${FAKE_UPDATE_INPUT:-}" ]]; then
  jq --arg input "$FAKE_UPDATE_INPUT" --arg rev "$FAKE_UPDATE_REV" \
    '.nodes[$input].locked.rev = $rev' "$NIX_CONFIG_REPO/flake.lock" >"$NIX_CONFIG_REPO/flake.lock.new"
  mv "$NIX_CONFIG_REPO/flake.lock.new" "$NIX_CONFIG_REPO/flake.lock"
fi

if [[ " $* " == *' eval '* ]]; then
  if [[ " $* " == *'nix-homebrew.package.version'* ]]; then
    printf '%s' "${FAKE_EXPECTED_BREW_VERSION:-6.0.15}"
  elif [[ "${FAKE_BREWFILE_MODE:-complete}" == missing-chatgpt ]]; then
    printf '%s\n' \
      '# Created by `nix-darwin`'"'"'s `homebrew` module' \
      'cask "silverstein/tap/minutes", args: { appdir: "/Applications" }, trusted: true'
  else
    printf '%s\n' \
      '# Created by `nix-darwin`'"'"'s `homebrew` module' \
      'cask "chatgpt", trusted: true' \
      'cask "silverstein/tap/minutes", args: { appdir: "/Applications" }, trusted: true'
  fi
fi

if [[ " $* " == *' flake check '* ]]; then
  if [[ "${FAKE_MUTATE_REPO:-0}" == 1 ]]; then touch "$NIX_CONFIG_REPO/mutated"; fi
  exit "${FAKE_NIX_CHECK_STATUS:-0}"
fi

if [[ " $* " == *' build '* ]] && [[ " $* " == *'#homebrew-preflight '* ]]; then
  printf '%s\n' "$FAKE_HOMEBREW_PREFLIGHT_OUT"
  exit "${FAKE_NIX_BUILD_STATUS:-0}"
fi

if [[ " $* " == *' build '* ]] && [[ " $* " == *'#darwinConfigurations.macos.system '* ]]; then
  printf '%s\n' "$FAKE_DARWIN_SYSTEM_OUT"
fi
EOF

# Like nix-darwin's activate: `env -i` in the first line clears the
# environment, so the fake can only use builtins and paths baked in here.
{
  printf '#!/usr/bin/env -i %s\n' "$BASH"
  cat <<EOF
printf 'activate checkActivation=%s HOME=%s\\n' "\${checkActivation:-unset}" "\${HOME:-unset}" >>'$log_file'
status=0
if [[ -f '$fixture/activate-status' ]]; then read -r status <'$fixture/activate-status'; fi
exit "\$status"
EOF
} >"$fake_system/activate"
chmod +x "$fake_system/activate"

write_fake "$fake_homebrew/bin/brew" <<'EOF'
set -euo pipefail
printf 'pinned-brew' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"

case "${1:-} ${2:-} ${3:-}" in
  'ruby -e '*) exit "${FAKE_BREW_TAP_CHECK_STATUS:-0}" ;;
  '--version  ')
    printf '%s\n' "${FAKE_BREW_VERSION_OUTPUT:-Homebrew 6.0.15}"
    exit "${FAKE_BREW_VERSION_STATUS:-0}"
    ;;
  'info --json=v2 --formula'|'info --json=v2 --cask')
    for name in "${@:5}"; do
      if [[ "$name" == "${FAKE_BREW_INFO_FAIL_NAME:-__never__}" ]]; then
        exit "${FAKE_BREW_INFO_STATUS:-42}"
      fi
    done
    ;;
  'list --formula ')
    printf '%s\n' "${FAKE_FORMULA_LIST:-openssl@3}"
    exit "${FAKE_BREW_FORMULA_LIST_STATUS:-0}"
    ;;
  'list --cask ')
    printf '%s\n' "${FAKE_CASK_LIST:-chatgpt}"
    exit "${FAKE_BREW_CASK_LIST_STATUS:-0}"
    ;;
  'bundle list --all') exit "${FAKE_BREW_BUNDLE_LIST_STATUS:-0}" ;;
  'bundle check --verbose')
    if [[ "${FAKE_BREW_CHECK_STATUS:-0}" == 1 && "${FAKE_CHECK_CRASH:-0}" != 1 ]]; then
      printf "brew bundle can't satisfy your Brewfile's dependencies.\n" >&2
    fi
    exit "${FAKE_BREW_CHECK_STATUS:-0}"
    ;;
  'bundle cleanup --all')
    if [[ " $* " == *' --force '* ]]; then
      # Like Bundle, report success even when an uninstall failed.
      if [[ "${FAKE_CLEANUP_LEAVES_ITEMS:-0}" != 1 ]]; then touch "$FAKE_STATE_DIR/cleaned"; fi
      # Its trailing `brew cleanup` can still fail and end the run non-zero.
      exit "${FAKE_FORCE_CLEANUP_STATUS:-0}"
    fi
    if [[ -e "$FAKE_STATE_DIR/cleaned" ]]; then
      exit 0
    elif [[ "${FAKE_CLEANUP_CRASH:-0}" == 1 ]]; then
      printf 'Error: undefined method for nil\n' >&2
      exit 1
    elif [[ "${FAKE_CLEANUP_OLD_VERSIONS:-0}" == 1 ]]; then
      printf 'Would `brew cleanup`:\nWould remove: /opt/homebrew/Cellar/example/1.0\n'
    elif [[ "${FAKE_BREW_CLEANUP_STATUS:-0}" == 1 ]]; then
      printf 'Would uninstall casks:\n%s\n' "${FAKE_CLEANUP_ITEM:-example}"
    fi
    exit "${FAKE_BREW_CLEANUP_STATUS:-0}"
    ;;
esac
EOF

write_fake "$fake_bin/brew" <<'EOF'
printf 'live-brew' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
printf 'live-brew must not be called\n' >&2
exit 99
EOF

write_fake "$fake_bin/sudo" <<'EOF'
set -euo pipefail
printf 'sudo' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
if [[ "${1:-}" == -- ]]; then
  shift
fi
# The Linux build sandbox has no /usr/bin/env.
if [[ "${1:-}" == /usr/bin/env ]]; then
  shift
  exec env "$@"
fi
exec "$@"
EOF

write_fake "$fake_bin/nix-collect-garbage" <<'EOF'
set -euo pipefail
printf 'nix-collect-garbage\n' >>"$FAKE_COMMAND_LOG"
EOF

export PATH="$fake_bin:$PATH"
export TMPDIR="$fixture/tmp"
export FAKE_COMMAND_LOG=$log_file
export FAKE_STATE_DIR=$fixture
export NIX_CONFIG_REPO=$fake_repo
export NIX_CONFIG_TESTING=1
export NIX_CONFIG_TEST_TAPS_DIR=$fixture/declarative-taps
export NIX_CONFIG_TEST_HOMEBREW_PREFIX=$fixture/homebrew-prefix
export FAKE_HOMEBREW_PREFLIGHT_OUT=$fake_homebrew
export FAKE_DARWIN_SYSTEM_OUT=$fake_system
fake_flake_ref="git+file://${fake_repo// /%20}"
fake_git_ref=${fake_flake_ref//#/%23}
fake_flake_ref=path:/nix/store/test-source
update="$repo_root/config/nix-config/nix-config-update"
preflight="$repo_root/config/nix-config/nix-config-preflight"
apply="$repo_root/config/nix-config/nix-config-apply"
old_tap_rev=e000000000000000000000000000000000000001
new_tap_rev=e1234567890abcdef00000000000000000000000

# The Homebrew cohort comes from the lock file, not from a hand-kept list.
reset
NIX_CONFIG_TEST_SYSTEM=Linux "$update" homebrew
assert_contains 'nix <flake> <update> <homebrew-azd> <homebrew-cask> <homebrew-core> <homebrew-silverstein-tap> <nix-homebrew>' "$log_file"
assert_not_contains '<nixpkgs>' "$log_file"
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref>" "$log_file"

reset
NIX_CONFIG_TEST_SYSTEM=Linux "$update"
assert_contains 'nix <flake> <update>' "$log_file"
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref>" "$log_file"

if "$update" invalid >/dev/null 2>&1; then
  fail 'invalid update mode unexpectedly succeeded'
fi
if "$update" all homebrew >/dev/null 2>&1; then
  fail 'two update modes unexpectedly succeeded'
fi

# A lock without Homebrew inputs must never fall back to updating everything.
reset
printf '{}\n' >"$fake_repo/flake.lock"
if NIX_CONFIG_TEST_SYSTEM=Linux "$update" homebrew >/dev/null 2>"$fixture/update.err"; then
  fail 'homebrew update without Homebrew inputs unexpectedly succeeded'
fi
assert_contains 'no nix-homebrew or homebrew-* inputs' "$fixture/update.err"
assert_not_contains '<update>' "$log_file"

reset
update_status=0
FAKE_NIX_CHECK_STATUS=23 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$update" homebrew >"$fixture/update.out" 2>"$fixture/update.err" || update_status=$?
[[ "$update_status" == 23 ]] || fail "failed preflight returned $update_status instead of 23"
assert_contains 'flake.lock was intentionally left at the updated revisions' "$fixture/update.err"

# A pending cleanup approval is passed on as exit 3, not reported as a failure.
reset
update_status=0
FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$update" homebrew >"$fixture/update.out" 2>"$fixture/update.err" || update_status=$?
[[ "$update_status" == 3 ]] || fail "cleanup approval returned $update_status instead of 3"
assert_contains 'nix-config-apply --accept-zap' "$fixture/update.err"
assert_not_contains 'preflight failed' "$fixture/update.err"

# A changed third-party tap is shown and needs a confirmation before the
# preflight loads its code.
reset
update_status=0
FAKE_UPDATE_INPUT=homebrew-silverstein-tap FAKE_UPDATE_REV=$new_tap_rev NIX_CONFIG_TEST_SYSTEM=Linux \
  "$update" homebrew </dev/null >"$fixture/update.out" 2>"$fixture/update.err" || update_status=$?
[[ "$update_status" == 1 ]] || fail "unconfirmed tap change returned $update_status instead of 1"
assert_contains 'homebrew-silverstein-tap (silverstein/homebrew-tap): e00000000000 -> e1234567890a' "$fixture/update.err"
assert_contains "https://github.com/silverstein/homebrew-tap/compare/$old_tap_rev...$new_tap_rev" "$fixture/update.err"
assert_not_contains 'homebrew-azd' "$fixture/update.err"
assert_contains 'Stopped before the preflight' "$fixture/update.err"
assert_contains "\"rev\": \"$new_tap_rev\"" "$fake_repo/flake.lock"
assert_not_contains '<check>' "$log_file"

reset
printf 'y\n' | FAKE_UPDATE_INPUT=homebrew-silverstein-tap FAKE_UPDATE_REV=$new_tap_rev NIX_CONFIG_TEST_SYSTEM=Linux \
  "$update" homebrew >/dev/null 2>&1
assert_contains '<check>' "$log_file"

reset
FAKE_UPDATE_INPUT=homebrew-silverstein-tap FAKE_UPDATE_REV=$new_tap_rev NIX_CONFIG_TEST_SYSTEM=Linux \
  "$update" --yes homebrew </dev/null >/dev/null 2>"$fixture/update.err"
assert_contains 'compare/' "$fixture/update.err"
assert_contains '<check>' "$log_file"

# Homebrew's own taps need no extra confirmation.
reset
FAKE_UPDATE_INPUT=homebrew-core FAKE_UPDATE_REV=d000000000000000000000000000000000000002 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$update" homebrew </dev/null >/dev/null 2>"$fixture/update.err"
assert_not_contains 'Third-party' "$fixture/update.err"
assert_contains '<check>' "$log_file"

reset
FAKE_BREW_CHECK_STATUS=1 \
FAKE_BREW_CLEANUP_STATUS=0 \
NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >"$fixture/preflight.out"
assert_contains 'apply will install them' "$fixture/preflight.out"
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref>" "$log_file"
assert_matches "^nix <build> <--out-link> <$fixture/tmp/nix-config-preflight\.[^/>]*/source> </nix/store/test-source>$" "$log_file"
assert_matches "^nix <build> <--out-link> <$fixture/tmp/nix-config-preflight\.[^/>]*/homebrew-preflight> <--print-out-paths> <--no-update-lock-file> <$fake_flake_ref#homebrew-preflight>$" "$log_file"
assert_contains 'pinned-brew <--version>' "$log_file"
assert_contains 'pinned-brew <bundle> <list> <--all>' "$log_file"
assert_contains 'pinned-brew <list> <--formula>' "$log_file"
assert_contains 'pinned-brew <list> <--cask>' "$log_file"
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3>' "$log_file"
assert_contains 'pinned-brew <info> <--json=v2> <--cask> <--> <chatgpt>' "$log_file"
assert_contains 'pinned-brew <bundle> <check> <--verbose> <--no-upgrade>' "$log_file"
assert_contains 'pinned-brew <bundle> <cleanup> <--all> <--zap> <--file=' "$log_file"
assert_not_contains '<--formula> <--cask> <--tap> <--zap>' "$log_file"
assert_not_contains '<--force>' "$log_file"
assert_not_contains 'live-brew' "$log_file"
assert_contains 'export MAS_NO_AUTO_INDEX=1' \
  "$repo_root/config/nix-config/homebrew-preflight-wrapper.sh.in"
assert_contains 'HOMEBREW_VERSION MAS_NO_AUTO_INDEX' "$repo_root/packages/homebrew-preflight/default.nix"
assert_before 'pinned-brew <--version>' 'pinned-brew <bundle>' "$log_file"
assert_before 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3>' \
  'pinned-brew <bundle>' "$log_file"
[[ -z "$(ls -A "$fixture/tmp")" ]] || fail 'preflight left temporary files behind'

# brew's generic crash status 1 is not "dependencies missing".
reset
if FAKE_BREW_CHECK_STATUS=1 FAKE_CHECK_CRASH=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>"$fixture/preflight.err"; then
  fail 'crashed dependency check unexpectedly passed preflight'
fi
assert_contains 'without listing missing dependencies' "$fixture/preflight.err"
assert_not_contains 'pinned-brew <bundle> <cleanup>' "$log_file"

# Nor is it a cleanup list: an error message never receives an approval hash.
reset
preflight_status=0
FAKE_CLEANUP_CRASH=1 FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>"$fixture/preflight.err" || preflight_status=$?
[[ "$preflight_status" == 2 ]] || fail "crashed cleanup preview returned $preflight_status instead of 2"
assert_contains 'without a removal list' "$fixture/preflight.err"
assert_not_contains '--accept-zap' "$fixture/preflight.err"

# Installed packages are loaded in one brew call per kind.
reset
FAKE_FORMULA_LIST=$'openssl@3\nxz' FAKE_CASK_LIST=$'chatgpt\nghostty' NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3> <xz>' "$log_file"
assert_contains 'pinned-brew <info> <--json=v2> <--cask> <--> <chatgpt> <ghostty>' "$log_file"
assert_count 1 'pinned-brew <info> <--json=v2> <--cask>' "$log_file"

# A failed batch is retried by name so the error names the broken package.
reset
if FAKE_FORMULA_LIST=$'openssl@3\nxz' FAKE_BREW_INFO_FAIL_NAME=xz NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'broken installed formula unexpectedly passed preflight'
fi
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <xz>' "$log_file"
assert_not_contains 'pinned-brew <info> <--json=v2> <--cask>' "$log_file"
assert_not_contains 'pinned-brew <bundle> <check>' "$log_file"

reset
mkdir -p "$fixture/legacy-taps"
if NIX_CONFIG_TEST_TAPS_DIR="$fixture/legacy-taps" NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'legacy mutable Taps directory unexpectedly passed preflight'
fi
assert_contains 'pinned-brew <--version>' "$log_file"
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3>' "$log_file"
assert_not_contains 'pinned-brew <bundle>' "$log_file"

reset
if FAKE_BREW_INFO_FAIL_NAME=openssl@3 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'parser compatibility failure unexpectedly succeeded'
fi
assert_not_contains 'pinned-brew <bundle> <check>' "$log_file"

reset
if FAKE_BREW_VERSION_OUTPUT='Homebrew 6.0.14' NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'wrong pinned Homebrew version unexpectedly succeeded'
fi
assert_not_contains 'pinned-brew <info> <--json=v2> <--formula>' "$log_file"

reset
FAKE_EXPECTED_BREW_VERSION=6.0.16 \
FAKE_BREW_VERSION_OUTPUT='Homebrew 6.0.16' \
FAKE_BREW_CHECK_STATUS=1 \
FAKE_BREW_CLEANUP_STATUS=0 \
NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null
assert_contains 'pinned-brew <--version>' "$log_file"
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3>' "$log_file"

# Every name is validated before any of them reaches brew.
reset
if FAKE_FORMULA_LIST='valid-formula
bad formula' NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'malformed installed formula name unexpectedly passed preflight'
fi
assert_not_contains '<valid-formula>' "$log_file"
assert_not_contains '<bad formula>' "$log_file"

reset
if FAKE_BREW_CASK_LIST_STATUS=17 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'installed cask list failure unexpectedly passed preflight'
fi
assert_not_contains 'pinned-brew <bundle> <check>' "$log_file"

reset
if FAKE_BREW_BUNDLE_LIST_STATUS=19 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'Brewfile parser failure unexpectedly passed preflight'
fi
assert_not_contains 'pinned-brew <list> <--formula>' "$log_file"

# The tap/disabled-package check runs on the Brewfile and blocks the apply.
reset
if FAKE_BREW_TAP_CHECK_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" >/dev/null 2>&1; then
  fail 'formula tap conflict or disabled package unexpectedly passed preflight'
fi
assert_contains 'pinned-brew <ruby> <-e>' "$log_file"
assert_matches '> <--> <[^>]*/Brewfile>$' "$log_file"
assert_not_contains 'pinned-brew <bundle> <check>' "$log_file"
assert_not_contains 'sudo' "$log_file"

reset
if FAKE_BREWFILE_MODE=missing-chatgpt NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$preflight" >/dev/null 2>&1; then
  fail 'missing chatgpt unexpectedly succeeded'
fi
assert_not_contains 'pinned-brew <info> <--json=v2> <--cask>' "$log_file"

reset
NIX_CONFIG_TEST_SYSTEM=Linux "$apply" >/dev/null
assert_contains "nix <run> <$fake_flake_ref#home-manager> <--> <switch> <--flake> <$fake_flake_ref#default>" "$log_file"
assert_not_contains 'nix-collect-garbage' "$log_file"
assert_not_contains 'nixpkgs#home-manager' "$log_file"
assert_not_contains 'brew' "$log_file"

# An empty cleanup preview removes nothing before the switch, and the
# activation checks run without touching the system profile first. They
# run activate itself in check mode, not `darwin-rebuild check`, whose
# checkActivation the `env -i` line of activate would drop.
reset
NIX_CONFIG_TEST_SYSTEM=Darwin "$apply" >/dev/null
assert_matches "^nix <build> <--out-link> <$fixture/tmp/nix-config-apply\.[^/>]*/source> </nix/store/test-source>$" "$log_file"
assert_matches "^nix <build> <--out-link> <$fixture/tmp/nix-config-apply\.[^/>]*/homebrew-preflight> " "$log_file"
assert_matches "^nix <build> <--out-link> <$fixture/tmp/nix-config-apply\.[^/>]*/system> <--print-out-paths> <--no-update-lock-file> <$fake_flake_ref#darwinConfigurations\.macos\.system>$" "$log_file"
assert_contains "sudo <--> </usr/bin/env> <-i> <checkActivation=1> <$BASH> <$fake_system/activate>" "$log_file"
assert_contains 'activate checkActivation=1 HOME=unset' "$log_file"
assert_not_contains '<--> <check>' "$log_file"
assert_contains "sudo <--> <$fake_bin/nix> <run> <$fake_flake_ref#darwin-rebuild> <--> <switch> <--flake> <$fake_flake_ref#macos>" "$log_file"
assert_before 'activate checkActivation=1' '#darwin-rebuild> <--> <switch>' "$log_file"
assert_contains "nix <run> <$fake_flake_ref#darwin-rebuild> <--> <switch> <--flake> <$fake_flake_ref#macos>" "$log_file"
assert_not_contains '<--force>' "$log_file"
assert_not_contains 'nix-collect-garbage' "$log_file"
[[ -z "$(ls -A "$fixture/tmp")" ]] || fail 'apply left temporary files behind'

# A failed activation check stops before switch moves the system profile.
reset
printf '2\n' >"$fixture/activate-status"
apply_status=0
NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" >/dev/null 2>"$fixture/check.err" || apply_status=$?
[[ "$apply_status" == 2 ]] || fail "failed activation check returned $apply_status instead of 2"
assert_contains 'system profile is unchanged' "$fixture/check.err"
assert_contains 'activate checkActivation=1' "$log_file"
assert_not_contains '<switch>' "$log_file"
[[ -z "$(ls -A "$fixture/tmp")" ]] || fail 'apply left temporary files behind'

# activate must still start with the `env -i` line the check mode relies on.
reset
cp "$fake_system/activate" "$fixture/activate.orig"
printf '#!/bin/bash\nexit 0\n' >"$fake_system/activate"
apply_status=0
NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" >/dev/null 2>"$fixture/check.err" || apply_status=$?
mv "$fixture/activate.orig" "$fake_system/activate"
[[ "$apply_status" == 2 ]] || fail "unexpected activate interpreter returned $apply_status instead of 2"
assert_contains 'unexpected first line' "$fixture/check.err"
assert_not_contains 'sudo' "$log_file"

# A failed snapshot capture must never fall back to evaluating the checkout.
reset
if FAKE_PREFETCH_STATUS=7 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$apply" >/dev/null 2>&1; then
  fail 'apply continued after snapshot capture failed'
fi
assert_not_contains '<check>' "$log_file"
assert_not_contains '<run>' "$log_file"

# Nor may it continue with a snapshot it could not protect from GC.
reset
if FAKE_ROOT_STATUS=9 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$apply" >/dev/null 2>&1; then
  fail 'apply continued without a GC root for its snapshot'
fi
assert_not_contains '<check>' "$log_file"
assert_not_contains '<run>' "$log_file"

# Approval must match the actual cleanup list and checked source snapshot.
reset
if FAKE_CLEANUP_OLD_VERSIONS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" >"$fixture/old-versions.out" 2>"$fixture/old-versions.err"; then
  fail 'zero-exit preview with old-version removals unexpectedly applied'
fi
assert_not_contains 'Cleanup preview is empty.' "$fixture/old-versions.out"
assert_not_contains 'sudo' "$log_file"
assert_not_contains '<--force>' "$log_file"
old_versions_approval=$(sed -n 's/.*--accept-zap \([a-f0-9]*\)$/\1/p' "$fixture/old-versions.err")
[[ ${#old_versions_approval} == 64 ]] || fail 'missing old-version cleanup approval token'
reset
FAKE_CLEANUP_OLD_VERSIONS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$old_versions_approval" >/dev/null
assert_before 'pinned-brew <bundle> <cleanup> <--all> <--zap> <--force>' 'sudo' "$log_file"

reset
apply_status=0
FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" >"$fixture/zap.out" 2>"$fixture/zap.err" || apply_status=$?
[[ "$apply_status" == 3 ]] || fail "unapproved cleanup returned $apply_status instead of 3"
assert_not_contains 'sudo' "$log_file"
assert_not_contains '<--force>' "$log_file"
# Run from a checkout, the hint names that checkout's apply helper, not an
# older installed one.
expected_helper=$(printf '%q' "$repo_root/config/nix-config/nix-config-apply")
assert_contains "After review, run: $expected_helper --accept-zap " "$fixture/zap.err"
approval=$(sed -n 's/.*--accept-zap \([a-f0-9]*\)$/\1/p' "$fixture/zap.err")
[[ ${#approval} == 64 ]] || fail 'missing approval token'

# The approved list is removed by apply itself, with the pinned brew and the
# checked Brewfile, verified, and only then is the system switched.
reset
FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$approval" >/dev/null
assert_matches "^pinned-brew <bundle> <cleanup> <--all> <--zap> <--force> <--file=$fixture/tmp/nix-config-apply\.[^/>]*/Brewfile>$" "$log_file"
assert_before 'pinned-brew <bundle> <cleanup> <--all> <--zap> <--force>' 'sudo' "$log_file"
assert_before 'activate checkActivation=1' '#darwin-rebuild> <--> <switch>' "$log_file"
assert_count 2 'pinned-brew <bundle> <cleanup> <--all> <--zap> <--file=' "$log_file"
assert_count 1 '<--force>' "$log_file"
assert_not_contains 'live-brew' "$log_file"
assert_contains "nix <run> <$fake_flake_ref#darwin-rebuild>" "$log_file"
[[ -z "$(ls -A "$fixture/tmp")" ]] || fail 'apply left temporary files behind'

# Bundle ignores failed uninstalls; leftovers stop apply before the switch.
reset
if FAKE_CLEANUP_LEAVES_ITEMS=1 FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$approval" >/dev/null 2>"$fixture/zap.err"; then
  fail 'incomplete cleanup unexpectedly continued to the switch'
fi
assert_contains 'did not complete' "$fixture/zap.err"
assert_contains '<--force>' "$log_file"
assert_not_contains 'sudo' "$log_file"

# A failing forced run still gets the re-check and stops with exit 2.
reset
apply_status=0
FAKE_FORCE_CLEANUP_STATUS=1 FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$approval" >/dev/null 2>"$fixture/zap.err" || apply_status=$?
[[ "$apply_status" == 2 ]] || fail "failed forced cleanup returned $apply_status instead of 2"
assert_contains 'the forced cleanup exited with status 1' "$fixture/zap.err"
assert_contains 'did not complete' "$fixture/zap.err"
assert_count 2 'pinned-brew <bundle> <cleanup> <--all> <--zap> <--file=' "$log_file"
assert_not_contains 'sudo' "$log_file"

# Only the prefix owner removes packages, never root or another user.
reset
if NIX_CONFIG_TEST_HOMEBREW_PREFIX="$fixture/not-the-prefix" FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$approval" >/dev/null 2>"$fixture/zap.err"; then
  fail 'cleanup ran without owning the Homebrew prefix'
fi
assert_contains 'owner of' "$fixture/zap.err"
assert_not_contains '<--force>' "$log_file"
assert_not_contains 'sudo' "$log_file"

reset
if FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$(printf '%064d' 0)" >/dev/null 2>&1; then
  fail 'wrong cleanup token unexpectedly applied'
fi
assert_not_contains 'sudo' "$log_file"
assert_not_contains '<--force>' "$log_file"

# Previously approved removals do not authorize a different list or source.
reset
if FAKE_CLEANUP_ITEM=another-app FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$approval" >/dev/null 2>&1; then
  fail 'changed cleanup list reused an old approval'
fi
assert_not_contains 'sudo' "$log_file"
assert_not_contains '<--force>' "$log_file"
touch "$fake_repo/mutated"
if FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$apply" --accept-zap "$approval" >/dev/null 2>&1; then
  fail 'changed snapshot reused an old approval'
fi
rm "$fake_repo/mutated"
assert_not_contains 'sudo' "$log_file"
assert_not_contains '<--force>' "$log_file"

# One captured source is used even if the checkout changes during preflight.
reset
FAKE_MUTATE_REPO=1 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$apply" --gc >/dev/null
assert_contains "<$fake_flake_ref#home-manager>" "$log_file"
assert_contains 'nix-collect-garbage' "$log_file"
[[ $(grep -c '<prefetch>' "$log_file") == 1 ]] || fail 'apply captured more than one source'
assert_contains "<$fake_git_ref>" "$log_file"
rm "$fake_repo/mutated"

# A clean checkout labels the snapshot with its commit; junk is rejected.
clean_rev=$(printf '%040d' 1)
reset
FAKE_SNAPSHOT_REV=$clean_rev NIX_CONFIG_TEST_SYSTEM=Linux \
  "$apply" >/dev/null
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref?rev=$clean_rev>" "$log_file"
assert_contains "nix <run> <$fake_flake_ref?rev=$clean_rev#home-manager> <--> <switch> <--flake> <$fake_flake_ref?rev=$clean_rev#default>" "$log_file"
reset
if FAKE_SNAPSHOT_REV=not-a-commit NIX_CONFIG_TEST_SYSTEM=Linux \
  "$apply" >/dev/null 2>&1; then
  fail 'malformed snapshot revision unexpectedly accepted'
fi
assert_not_contains '<check>' "$log_file"
assert_not_contains '<run>' "$log_file"

printf 'nix-config helper tests passed\n'
