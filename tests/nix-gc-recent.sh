#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/nix-gc-recent-tests.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

fake_bin="$fixture/bin"
log_file="$fixture/commands.log"
roots_dir="$fixture/gcroots/nix-gc-recent"
mkdir -p "$fake_bin" "$fixture/gcroots"

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

# BSD wc pads its counts, so the counts are matched with a regex.
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

# Fakes are created at runtime, after any patchShebangs, and the Linux sandbox
# has no /usr/bin/env, so they use the interpreter running this test.
write_fake() {
  { printf '#!%s\n' "$BASH"; cat; } >"$1"
  chmod +x "$1"
}

write_fake "$fake_bin/id" <<'EOF'
printf '%s\n' "${FAKE_UID:-0}"
EOF

# 1000 KiB in total, FAKE_FREE_PERCENT of it available.
write_fake "$fake_bin/df" <<'EOF'
printf 'df' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/disk3s7 1000 %d %d %d%% /nix\n' \
  $((1000 - FAKE_FREE_PERCENT * 10)) $((FAKE_FREE_PERCENT * 10)) $((100 - FAKE_FREE_PERCENT))
EOF

# The dead paths do not exist, so their registration time comes from a table.
write_fake "$fake_bin/stat" <<'EOF'
set -euo pipefail
[[ "$1" == -c && "$2" == '%X %n' ]] || exit 64
shift 2
for path in "$@"; do
  printf '%s %s\n' "$(awk -v path="$path" '$2 == path { print $1 }' "$FAKE_ATIMES")" "$path"
done
EOF

# Records which protection roots exist at the moment of collection.
write_fake "$fake_bin/nix-store" <<'EOF'
set -euo pipefail
printf 'nix-store' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
case "$*" in
  '--gc --print-dead') awk '{ print $2 }' "$FAKE_ATIMES" ;;
  '--gc --quiet')
    for root in "$NIX_GC_ROOTS_DIR"/*; do
      if [[ -L "$root" ]]; then
        printf 'root %s -> %s\n' "${root##*/}" "$(readlink "$root")" >>"$FAKE_COMMAND_LOG"
      fi
    done
    ;;
  *) exit 64 ;;
esac
EOF

# The real lockf is macOS-only; this one only reports a held lock on request.
write_fake "$fake_bin/lockf" <<'EOF'
printf 'lockf' >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
[[ "$*" == '-s -t 0 9' ]] || exit 64
[[ "${FAKE_LOCK_BUSY:-0}" != 1 ]] || exit 75
EOF

now=$(date +%s)
printf '%s /nix/store/aaaaaaaa-old\n%s /nix/store/bbbbbbbb-recent\n' \
  $((now - 30 * 86400)) $((now - 86400)) >"$fixture/atimes"

export PATH="$fake_bin:$PATH"
export FAKE_COMMAND_LOG=$log_file
export FAKE_ATIMES=$fixture/atimes
export NIX_GC_ROOTS_DIR=$roots_dir
export NIX_GC_LOCK_FILE=$fixture/nix-gc-recent.lock
export NIX_GC_VOLUME=/fake-nix
export NIX_GC_MIN_AGE_DAYS=14
export NIX_GC_START_BELOW_FREE_PERCENT=20
export NIX_GC_URGENT_BELOW_FREE_PERCENT=5

# Invoke through $BASH: the script's own shebang may not be patched here.
gc_recent() {
  "$BASH" "$repo_root/config/nix-gc/nix-gc-recent" "$@"
}

# Enough free space: only df runs, nothing is locked or collected.
: >"$log_file"
FAKE_FREE_PERCENT=50 gc_recent >"$fixture/out"
[[ ! -s "$fixture/out" ]] || fail 'idle run printed output'
assert_contains 'df <-Pk> </fake-nix>' "$log_file"
assert_not_contains 'nix-store' "$log_file"
assert_not_contains 'lockf' "$log_file"

if gc_recent --bogus >/dev/null 2>&1; then
  fail 'unknown option unexpectedly accepted'
fi

# A real run needs root; a dry run does not.
: >"$log_file"
if FAKE_UID=501 FAKE_FREE_PERCENT=10 gc_recent >/dev/null 2>"$fixture/err"; then
  fail 'non-root collection unexpectedly ran'
fi
assert_contains 'must run as root' "$fixture/err"
assert_not_contains 'nix-store' "$log_file"

: >"$log_file"
FAKE_UID=501 FAKE_FREE_PERCENT=50 gc_recent --force --dry-run >"$fixture/out"
assert_matches 'sparing +1 of +2 unreachable paths younger than 14 days' "$fixture/out"
assert_contains 'dry run, nothing collected' "$fixture/out"
assert_contains 'nix-store <--gc> <--print-dead>' "$log_file"
[[ "$(grep -c '^nix-store' "$log_file")" == 1 ]] || fail 'dry run collected garbage'
assert_not_contains 'lockf' "$log_file"
[[ ! -e "$roots_dir" ]] || fail 'dry run created the roots dir'

# Low on space: recent dead paths are rooted before the collection, old ones
# are not, stale roots of an interrupted run are gone, and the roots are
# removed afterwards.
: >"$log_file"
mkdir -p "$roots_dir"
ln -s /nix/store/cccccccc-stale "$roots_dir/cccccccc-stale"
FAKE_FREE_PERCENT=15 gc_recent >"$fixture/out"
assert_contains '15% free on /fake-nix' "$fixture/out"
assert_matches 'sparing +1 of +2 unreachable paths younger than 14 days' "$fixture/out"
assert_before 'lockf <-s> <-t> <0> <9>' 'nix-store <--gc> <--print-dead>' "$log_file"
assert_matches '^nix-store <--gc> <--quiet>$' "$log_file"
# The fake collection logs the roots it sees.
assert_contains 'root bbbbbbbb-recent -> /nix/store/bbbbbbbb-recent' "$log_file"
assert_not_contains 'aaaaaaaa-old ->' "$log_file"
assert_not_contains 'cccccccc-stale' "$log_file"
[[ ! -e "$roots_dir" ]] || fail 'protection roots were left behind'

# Nearly full: the age protection is dropped.
: >"$log_file"
FAKE_FREE_PERCENT=3 gc_recent >"$fixture/out"
assert_contains 'below 5% free, ignoring age protection' "$fixture/out"
assert_matches 'sparing +0 of +2 unreachable paths younger than 0 days' "$fixture/out"
assert_matches '^nix-store <--gc> <--quiet>$' "$log_file"
assert_not_contains 'root ' "$log_file"

# An overlapping run must leave the active run's roots alone.
: >"$log_file"
mkdir -p "$roots_dir"
ln -s /nix/store/bbbbbbbb-recent "$roots_dir/bbbbbbbb-recent"
FAKE_LOCK_BUSY=1 FAKE_FREE_PERCENT=15 gc_recent >/dev/null 2>"$fixture/err"
assert_contains 'another run is active' "$fixture/err"
assert_not_contains 'nix-store' "$log_file"
[[ -L "$roots_dir/bbbbbbbb-recent" ]] || fail 'overlapping run removed the active roots'
rm -rf -- "$roots_dir"

# No dead paths: nothing to stat, nothing to protect.
: >"$log_file"
: >"$fixture/atimes"
FAKE_FREE_PERCENT=15 gc_recent >"$fixture/out"
assert_matches 'sparing +0 of +0 unreachable paths' "$fixture/out"

printf 'nix-gc-recent tests passed\n'
