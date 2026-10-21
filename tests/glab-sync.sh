#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/glab-sync-tests.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
# glab-sync works with $PWD, so compare against the canonical path.
fixture=$(cd -- "$fixture" && pwd -P)

fake_bin="$fixture/bin"
log_file="$fixture/commands.log"
remotes="$fixture/remotes"
base="$fixture/base"
mkdir -p "$fake_bin" "$remotes" "$base" "$fixture/home"

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

# Fakes are created at runtime, after any patchShebangs, and the Linux sandbox
# has no /usr/bin/env, so they use the interpreter running this test.
write_fake() {
  { printf '#!%s\n' "$BASH"; cat; } >"$1"
  chmod +x "$1"
}

# Answers the project listing from a JSON file and logs the request together
# with the GitLab host it was sent to. Nothing goes over the network.
write_fake "$fake_bin/glab" <<'EOF'
printf 'glab host=%s' "${GITLAB_HOST:-}" >>"$FAKE_COMMAND_LOG"
printf ' <%s>' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
[[ "${1:-} ${2:-}" == 'api --paginate' ]] || exit 64
cat "$FAKE_PROJECTS"
EOF

# Isolated Git: no user or system config, a fixed identity for the fixtures.
export HOME="$fixture/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$fixture/gitconfig"
git config --global user.name 'glab-sync test'
git config --global user.email 'glab-sync@example.test'
git config --global init.defaultBranch main
export PATH="$fake_bin:$PATH"
export FAKE_COMMAND_LOG=$log_file
export FAKE_PROJECTS=$fixture/projects.json
unset GITLAB_HOST

# A bare remote with one commit, plus a work tree to push follow-ups from.
make_remote() {
  local path=$1
  git init --quiet --bare "$remotes/$path.git"
  git clone --quiet "$remotes/$path.git" "$fixture/work/$path" 2>/dev/null
  git -C "$fixture/work/$path" commit --quiet --allow-empty -m initial
  git -C "$fixture/work/$path" push --quiet origin HEAD
}

make_remote group/app
make_remote group/sub/lib
make_remote other/shared

cat >"$FAKE_PROJECTS" <<EOF
[
  { "path_with_namespace": "group/app", "http_url_to_repo": "$remotes/group/app.git" },
  { "path_with_namespace": "group/sub/lib", "http_url_to_repo": "$remotes/group/sub/lib.git" },
  { "path_with_namespace": "other/shared", "http_url_to_repo": "$remotes/other/shared.git" }
]
EOF

# Invoke through $BASH: the script's own shebang may not be patched here.
glab_sync() {
  "$BASH" "$repo_root/config/glab-sync/glab-sync" "$@"
}

# First run clones the group's projects at their namespace paths, asks GitLab
# for the group's own projects only and skips anything outside the group.
: >"$log_file"
glab_sync -d "$base" group >"$fixture/out" 2>"$fixture/err"
assert_contains 'with_shared=false' "$log_file"
assert_contains '<groups/group/projects?include_subgroups=true&archived=false&with_shared=false&per_page=100>' "$log_file"
[[ -d "$base/group/app/.git" ]] || fail 'group/app was not cloned'
[[ -d "$base/group/sub/lib/.git" ]] || fail 'group/sub/lib was not cloned'
[[ ! -e "$base/other" ]] || fail 'a project outside the group was cloned next to it'
assert_contains 'other/shared: outside group, skipped' "$fixture/err"
assert_contains 'glab-sync: 2 cloned, 0 updated, 0 failed' "$fixture/out"

# A second run fast-forwards the existing clones.
git -C "$fixture/work/group/app" commit --quiet --allow-empty -m follow-up
git -C "$fixture/work/group/app" push --quiet origin HEAD
glab_sync -d "$base" group >"$fixture/out" 2>"$fixture/err"
assert_contains 'glab-sync: 0 cloned, 2 updated, 0 failed' "$fixture/out"
[[ "$(git -C "$base/group/app" log -1 --format=%s)" == follow-up ]] || fail 'group/app was not fast-forwarded'

# The group comparison ignores case, like GitLab paths do.
glab_sync -d "$base" Group >"$fixture/out" 2>"$fixture/err"
assert_not_contains 'group/app: outside' "$fixture/err"
assert_contains 'glab-sync: 0 cloned, 2 updated, 0 failed' "$fixture/out"

# A path occupied by something that is not a clone counts as a failure.
rm -rf -- "$base/group/sub/lib"
mkdir -p "$base/group/sub/lib"
if glab_sync -d "$base" group >"$fixture/out" 2>"$fixture/err"; then
  fail 'a non-repository at a project path unexpectedly succeeded'
fi
assert_contains 'group/sub/lib: exists but is not a git repository' "$fixture/err"
assert_contains '1 failed' "$fixture/out"

# Without GROUP the group comes from the clones below the current folder:
# here only a subgroup clone, two levels down, has a matching https origin.
printf '[]\n' >"$FAKE_PROJECTS"
infer="$fixture/infer/top/team"
mkdir -p "$infer/sub"
git init --quiet "$infer/sub/lib"
git -C "$infer/sub/lib" remote add origin https://gitlab.example.test/top/team/sub/lib.git
: >"$log_file"
(cd "$infer" && glab_sync >"$fixture/out" 2>"$fixture/err")
assert_contains "glab-sync: top/team → $infer" "$fixture/out"
assert_contains 'glab host=gitlab.example.test <api> <--paginate> <groups/top%2Fteam/projects?' "$log_file"

# A clone's working tree is never searched: a nested clone inside a clone
# whose own origin does not match is not used to infer the group.
infer="$fixture/infer-nested/top/team"
mkdir -p "$infer"
git init --quiet "$infer/app"
git -C "$infer/app" remote add origin https://gitlab.example.test/elsewhere/renamed.git
git init --quiet "$infer/app/vendor/lib"
git -C "$infer/app/vendor/lib" remote add origin https://gitlab.example.test/top/team/app/vendor/lib.git
: >"$log_file"
infer_status=0
(cd "$infer" && glab_sync >"$fixture/out" 2>"$fixture/err") || infer_status=$?
[[ "$infer_status" == 2 ]] || fail "nested clone inference returned $infer_status instead of 2"
assert_contains 'no GROUP given and none found' "$fixture/err"
assert_not_contains 'glab' "$log_file"

printf 'glab-sync tests passed\n'
