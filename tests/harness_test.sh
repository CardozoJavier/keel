#!/bin/bash
# Tests for keel's own test harness: tests/lib.sh helpers and tests/run.sh.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# assert helpers report pass/fail without aborting
out=$( (assert_eq a a "same"; assert_eq a b "differ"; t_summary) 2>&1 ); rc=$?
assert_eq 1 "$rc" "t_summary fails when an assertion failed"
assert_contains "$out" "FAIL: differ" "failed assertion is reported"
assert_contains "$out" "passes=1 fails=1" "counts are reported"

assert_exit 3 "assert_exit sees the exit code" -- sh -c 'exit 3'
assert_contains "hello world" "lo wo" "assert_contains matches substrings"

# mk_repo: a git repo on main with a test identity
r=$(mk_repo)
assert_eq "main" "$(git -C "$r" symbolic-ref --short HEAD)" "mk_repo starts on main"
assert_eq "keel-test" "$(git -C "$r" config user.name)" "mk_repo sets a test identity"

# mk_bare_remote
b=$(mk_bare_remote)
assert_eq "true" "$(git --git-dir="$b" rev-parse --is-bare-repository)" "mk_bare_remote is bare"

# in_subdir runs in the given directory
mkdir -p "$r/mod/a"
assert_eq "$(cd "$r/mod/a" && pwd -P)" "$(in_subdir "$r/mod/a" pwd -P)" "in_subdir changes cwd"

# fixture_tracked_ignored: a committed file that matches an ignore rule
fixture_tracked_ignored "$r"
assert_contains "$(git -C "$r" ls-files -ci --exclude-standard)" ".mvn/wrapper/maven-wrapper.jar" "tracked-but-ignored fixture"

# run.sh aggregates suites and fails when one fails
td=$(t_tmp)
mkdir -p "$td/a" "$td/slow"
printf '#!/bin/bash\n. "%s"\nassert_eq 1 1 ok\nt_summary\n' "$KEEL_TEST_LIB" > "$td/a/pass_test.sh"
printf '#!/bin/bash\n. "%s"\nassert_eq 1 2 bad\nt_summary\n' "$KEEL_TEST_LIB" > "$td/a/fail_test.sh"
printf '#!/bin/bash\nexit 1\n' > "$td/slow/slowfail_test.sh"
out=$(KEEL_TESTS_DIR="$td" /bin/bash "$KEEL_TESTS_ROOT/run.sh" 2>&1); rc=$?
assert_eq 1 "$rc" "run.sh exits non-zero when a suite fails"
assert_contains "$out" "suites=2 failed=1" "run.sh reports suite counts"
rm "$td/a/fail_test.sh"
out=$(KEEL_TESTS_DIR="$td" /bin/bash "$KEEL_TESTS_ROOT/run.sh" 2>&1); rc=$?
assert_eq 0 "$rc" "run.sh passes when all fast suites pass (slow excluded)"
out=$(KEEL_TESTS_DIR="$td" /bin/bash "$KEEL_TESTS_ROOT/run.sh" --slow 2>&1); rc=$?
assert_eq 1 "$rc" "run.sh --slow includes tests/slow"

t_summary
