# shellcheck shell=bash
# Shared helpers for keel's own test suites. Source it; bash 3.2 compatible.
# Tests may use $TMPDIR: the no-/tmp rule applies to keel's runtime scripts in target repos,
# not to keel's own test fixtures.

KEEL_TESTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KEEL_TEST_LIB="$KEEL_TESTS_ROOT/lib.sh"
KEEL_REPO_ROOT=$(cd "$KEEL_TESTS_ROOT/.." && pwd)
KEEL_PLUGIN_ROOT="$KEEL_REPO_ROOT/plugin"
KEEL_TEST_PASSES=0
KEEL_TEST_FAILS=0

_t_pass() { KEEL_TEST_PASSES=$((KEEL_TEST_PASSES + 1)); }
_t_fail() { KEEL_TEST_FAILS=$((KEEL_TEST_FAILS + 1)); printf 'FAIL: %s\n' "$*" >&2; }

# assert_eq <expected> <actual> <message>
assert_eq() {
  if [ "$1" = "$2" ]; then _t_pass; else _t_fail "$3: expected [$1] got [$2]"; fi
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
  case "$1" in
    *"$2"*) _t_pass ;;
    *) _t_fail "$3: [$2] not found in [$1]" ;;
  esac
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
  case "$1" in
    *"$2"*) _t_fail "$3: [$2] unexpectedly found in [$1]" ;;
    *) _t_pass ;;
  esac
}

# assert_exit <expected-code> <message> -- <command...>
assert_exit() {
  local exp=$1 msg=$2 rc
  shift 2
  [ "${1:-}" = "--" ] && shift
  "$@" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "$exp" ]; then _t_pass; else _t_fail "$msg: expected exit $exp got $rc"; fi
}

# t_tmp: a fresh temp directory for one fixture
t_tmp() { mktemp -d "${TMPDIR:-/tmp}/keeltest.XXXXXX"; }

# mk_repo: a git repo on main with a test identity and no signing; prints its path
mk_repo() {
  local d
  d=$(t_tmp)
  git -C "$d" init -q -b main
  git -C "$d" config user.email keel-test@example.invalid
  git -C "$d" config user.name keel-test
  git -C "$d" config commit.gpgsign false
  printf '%s\n' "$d"
}

# mk_bare_remote: a bare repo usable as a push target; prints its path
mk_bare_remote() {
  local d
  d=$(t_tmp)
  git init -q --bare "$d/remote.git"
  printf '%s\n' "$d/remote.git"
}

# in_subdir <dir> <command...>: run a command with cwd set to <dir>
in_subdir() {
  local dir=$1
  shift
  (cd "$dir" && "$@")
}

# fixture_tracked_ignored <repo>: commit a file that matches an ignore rule
# (like a force-added maven-wrapper.jar under a '*.jar' rule)
fixture_tracked_ignored() {
  local r=$1
  mkdir -p "$r/.mvn/wrapper"
  printf 'jar' > "$r/.mvn/wrapper/maven-wrapper.jar"
  printf '*.jar\n' >> "$r/.gitignore"
  git -C "$r" add .gitignore
  git -C "$r" add -f .mvn/wrapper/maven-wrapper.jar
  git -C "$r" commit -q -m "fixture: tracked-but-ignored file"
}

# t_summary: print counts; succeed only if nothing failed
t_summary() {
  printf 'passes=%d fails=%d\n' "$KEEL_TEST_PASSES" "$KEEL_TEST_FAILS"
  [ "$KEEL_TEST_FAILS" -eq 0 ]
}
