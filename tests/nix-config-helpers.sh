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
log_file="$fixture/commands.log"
mkdir -p "$fake_repo" "$fake_bin" "$fake_homebrew/bin"
printf '{}\n' >"$fake_repo/flake.nix"
printf '{}\n' >"$fake_repo/flake.lock"
mkdir "$fake_repo/.git"

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

cat >"$fake_bin/nix" <<'EOF'
#!/usr/bin/env bash
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
EOF

cat >"$fake_homebrew/bin/brew" <<'EOF'
#!/usr/bin/env bash
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
    if [[ "${!#}" == "${FAKE_BREW_INFO_FAIL_NAME:-__never__}" ]]; then
      exit "${FAKE_BREW_INFO_STATUS:-42}"
    fi
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
  'bundle check --verbose') exit "${FAKE_BREW_CHECK_STATUS:-0}" ;;
  'bundle cleanup --all')
    if [[ "${FAKE_CLEANUP_OLD_VERSIONS:-0}" == 1 ]]; then
      printf 'Would `brew cleanup`:\nWould remove: /opt/homebrew/Cellar/example/1.0\n'
    elif [[ "${FAKE_BREW_CLEANUP_STATUS:-0}" == 1 ]]; then
      printf 'Would uninstall casks:\n%s\n' "${FAKE_CLEANUP_ITEM:-example}"
    fi
    exit "${FAKE_BREW_CLEANUP_STATUS:-0}"
    ;;
esac
EOF

cat >"$fake_bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'live-brew' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
printf 'live-brew must not be called\n' >&2
exit 99
EOF

cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sudo' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
if [[ "${1:-}" == -- ]]; then
  shift
fi
exec "$@"
EOF

cat >"$fake_bin/nix-collect-garbage" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'nix-collect-garbage\n' >>"$FAKE_COMMAND_LOG"
EOF

chmod +x \
  "$fake_bin/nix" \
  "$fake_bin/brew" \
  "$fake_bin/sudo" \
  "$fake_bin/nix-collect-garbage" \
  "$fake_homebrew/bin/brew"

export PATH="$fake_bin:$PATH"
export FAKE_COMMAND_LOG=$log_file
export NIX_CONFIG_REPO=$fake_repo
export NIX_CONFIG_TESTING=1
export NIX_CONFIG_TEST_TAPS_DIR=$fixture/declarative-taps
export FAKE_HOMEBREW_PREFLIGHT_OUT=$fake_homebrew
fake_flake_ref="git+file://${fake_repo// /%20}"
fake_git_ref=${fake_flake_ref//#/%23}
fake_flake_ref=path:/nix/store/test-source

: >"$log_file"
NIX_CONFIG_TEST_SYSTEM=Linux "$repo_root/config/nix-config/nix-config-update" homebrew
assert_contains 'nix <flake> <update> <nix-homebrew> <homebrew-core> <homebrew-cask> <homebrew-azd> <homebrew-silverstein-tap>' "$log_file"
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref>" "$log_file"

: >"$log_file"
NIX_CONFIG_TEST_SYSTEM=Linux "$repo_root/config/nix-config/nix-config-update"
assert_contains 'nix <flake> <update>' "$log_file"
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref>" "$log_file"

if "$repo_root/config/nix-config/nix-config-update" invalid >/dev/null 2>&1; then
  fail 'invalid update mode unexpectedly succeeded'
fi

: >"$log_file"
if FAKE_NIX_CHECK_STATUS=23 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$repo_root/config/nix-config/nix-config-update" homebrew >"$fixture/update.out" 2>"$fixture/update.err"; then
  fail 'update unexpectedly succeeded after a failed preflight'
fi
assert_contains 'flake.lock was intentionally left at the updated revisions' "$fixture/update.err"

: >"$log_file"
FAKE_BREW_CHECK_STATUS=1 \
FAKE_BREW_CLEANUP_STATUS=0 \
NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref>" "$log_file"
assert_contains "nix <build> <--no-link> <--print-out-paths> <--no-update-lock-file> <$fake_flake_ref#homebrew-preflight>" "$log_file"
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
assert_contains 'HOMEBREW_VERSION MAS_NO_AUTO_INDEX' "$repo_root/flake.nix"
assert_before 'pinned-brew <--version>' 'pinned-brew <bundle>' "$log_file"
assert_before 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3>' \
  'pinned-brew <bundle>' "$log_file"

: >"$log_file"
mkdir -p "$fixture/legacy-taps"
if NIX_CONFIG_TEST_TAPS_DIR="$fixture/legacy-taps" NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null 2>&1; then
  fail 'legacy mutable Taps directory unexpectedly passed preflight'
fi
assert_contains 'pinned-brew <--version>' "$log_file"
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3>' "$log_file"
assert_not_contains 'pinned-brew <bundle>' "$log_file"

: >"$log_file"
if FAKE_BREW_INFO_FAIL_NAME=openssl@3 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null 2>&1; then
  fail 'parser compatibility failure unexpectedly succeeded'
fi
assert_not_contains 'pinned-brew <bundle> <check>' "$log_file"

: >"$log_file"
if FAKE_BREW_VERSION_OUTPUT='Homebrew 6.0.14' NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null 2>&1; then
  fail 'wrong pinned Homebrew version unexpectedly succeeded'
fi
assert_not_contains 'pinned-brew <info> <--json=v2> <--formula>' "$log_file"

: >"$log_file"
FAKE_EXPECTED_BREW_VERSION=6.0.16 \
FAKE_BREW_VERSION_OUTPUT='Homebrew 6.0.16' \
FAKE_BREW_CHECK_STATUS=1 \
FAKE_BREW_CLEANUP_STATUS=0 \
NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null
assert_contains 'pinned-brew <--version>' "$log_file"
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <openssl@3>' "$log_file"

: >"$log_file"
if FAKE_FORMULA_LIST='valid-formula
bad formula' NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null 2>&1; then
  fail 'malformed installed formula name unexpectedly passed preflight'
fi
assert_contains 'pinned-brew <info> <--json=v2> <--formula> <--> <valid-formula>' "$log_file"
assert_not_contains '<bad formula>' "$log_file"

: >"$log_file"
if FAKE_BREW_CASK_LIST_STATUS=17 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null 2>&1; then
  fail 'installed cask list failure unexpectedly passed preflight'
fi
assert_not_contains 'pinned-brew <bundle> <check>' "$log_file"

: >"$log_file"
if FAKE_BREW_BUNDLE_LIST_STATUS=19 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null 2>&1; then
  fail 'Brewfile parser failure unexpectedly passed preflight'
fi
assert_not_contains 'pinned-brew <list> <--formula>' "$log_file"

: >"$log_file"
if FAKE_BREW_TAP_CHECK_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" >/dev/null 2>&1; then
  fail 'formula tap conflict unexpectedly passed preflight'
fi
assert_contains 'pinned-brew <ruby> <-e>' "$log_file"
assert_not_contains 'pinned-brew <bundle> <check>' "$log_file"
assert_not_contains 'sudo' "$log_file"

: >"$log_file"
if FAKE_BREWFILE_MODE=missing-chatgpt NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-preflight" >/dev/null 2>&1; then
  fail 'missing chatgpt unexpectedly succeeded'
fi
assert_not_contains 'pinned-brew <info> <--json=v2> <--cask>' "$log_file"

: >"$log_file"
NIX_CONFIG_TEST_SYSTEM=Linux "$repo_root/config/nix-config/nix-config-apply" >/dev/null
assert_contains "nix <run> <$fake_flake_ref#home-manager> <--> <switch> <--flake> <$fake_flake_ref#default>" "$log_file"
assert_not_contains 'nix-collect-garbage' "$log_file"
assert_not_contains 'nixpkgs#home-manager' "$log_file"

: >"$log_file"
NIX_CONFIG_TEST_SYSTEM=Darwin "$repo_root/config/nix-config/nix-config-apply" >/dev/null
assert_contains "sudo <--> <$fake_bin/nix> <run> <$fake_flake_ref#darwin-rebuild> <--> <switch> <--flake> <$fake_flake_ref#macos>" "$log_file"
assert_contains "nix <run> <$fake_flake_ref#darwin-rebuild> <--> <switch> <--flake> <$fake_flake_ref#macos>" "$log_file"
assert_not_contains 'nix-collect-garbage' "$log_file"

# A failed snapshot capture must never fall back to evaluating the checkout.
: >"$log_file"
if FAKE_PREFETCH_STATUS=7 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$repo_root/config/nix-config/nix-config-apply" >/dev/null 2>&1; then
  fail 'apply continued after snapshot capture failed'
fi
assert_not_contains '<check>' "$log_file"
assert_not_contains '<run>' "$log_file"

# Approval must match the actual cleanup list and checked source snapshot.
: >"$log_file"
if FAKE_CLEANUP_OLD_VERSIONS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" >"$fixture/old-versions.out" 2>"$fixture/old-versions.err"; then
  fail 'zero-exit preview with old-version removals unexpectedly applied'
fi
assert_not_contains 'Cleanup preview is empty.' "$fixture/old-versions.out"
assert_not_contains 'sudo' "$log_file"
old_versions_approval=$(sed -n 's/.*--accept-zap \([a-f0-9]*\)$/\1/p' "$fixture/old-versions.err")
[[ ${#old_versions_approval} == 64 ]] || fail 'missing old-version cleanup approval token'
: >"$log_file"
FAKE_CLEANUP_OLD_VERSIONS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" --accept-zap "$old_versions_approval" >/dev/null
assert_contains 'sudo' "$log_file"

: >"$log_file"
if FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" >"$fixture/zap.out" 2>"$fixture/zap.err"; then
  fail 'unapproved cleanup unexpectedly applied'
fi
assert_not_contains 'sudo' "$log_file"
approval=$(sed -n 's/.*--accept-zap \([a-f0-9]*\)$/\1/p' "$fixture/zap.err")
[[ ${#approval} == 64 ]] || fail 'missing approval token'
: >"$log_file"
FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" --accept-zap "$approval" >/dev/null
assert_contains 'sudo' "$log_file"
: >"$log_file"
if FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" --accept-zap "$(printf '%064d' 0)" >/dev/null 2>&1; then
  fail 'wrong cleanup token unexpectedly applied'
fi
assert_not_contains 'sudo' "$log_file"

# Previously approved removals do not authorize a different list or source.
: >"$log_file"
if FAKE_CLEANUP_ITEM=another-app FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" --accept-zap "$approval" >/dev/null 2>&1; then
  fail 'changed cleanup list reused an old approval'
fi
assert_not_contains 'sudo' "$log_file"
touch "$fake_repo/mutated"
if FAKE_BREW_CLEANUP_STATUS=1 NIX_CONFIG_TEST_SYSTEM=Darwin \
  "$repo_root/config/nix-config/nix-config-apply" --accept-zap "$approval" >/dev/null 2>&1; then
  fail 'changed snapshot reused an old approval'
fi
rm "$fake_repo/mutated"
assert_not_contains 'sudo' "$log_file"

# One captured source is used even if the checkout changes during preflight.
: >"$log_file"
FAKE_MUTATE_REPO=1 NIX_CONFIG_TEST_SYSTEM=Linux \
  "$repo_root/config/nix-config/nix-config-apply" --gc >/dev/null
assert_contains "<$fake_flake_ref#home-manager>" "$log_file"
assert_contains 'nix-collect-garbage' "$log_file"
[[ $(grep -c '<prefetch>' "$log_file") == 1 ]] || fail 'apply captured more than one source'
assert_contains "<$fake_git_ref>" "$log_file"
rm "$fake_repo/mutated"

# A clean checkout labels the snapshot with its commit; junk is rejected.
clean_rev=$(printf '%040d' 1)
: >"$log_file"
FAKE_SNAPSHOT_REV=$clean_rev NIX_CONFIG_TEST_SYSTEM=Linux \
  "$repo_root/config/nix-config/nix-config-apply" >/dev/null
assert_contains "nix <flake> <check> <--no-update-lock-file> <$fake_flake_ref?rev=$clean_rev>" "$log_file"
assert_contains "nix <run> <$fake_flake_ref?rev=$clean_rev#home-manager> <--> <switch> <--flake> <$fake_flake_ref?rev=$clean_rev#default>" "$log_file"
: >"$log_file"
if FAKE_SNAPSHOT_REV=not-a-commit NIX_CONFIG_TEST_SYSTEM=Linux \
  "$repo_root/config/nix-config/nix-config-apply" >/dev/null 2>&1; then
  fail 'malformed snapshot revision unexpectedly accepted'
fi
assert_not_contains '<check>' "$log_file"
assert_not_contains '<run>' "$log_file"

printf 'nix-config helper tests passed\n'
