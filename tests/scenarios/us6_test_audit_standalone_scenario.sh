#!/bin/bash
# FR-027 / T067: /keel:test-audit <module> outside a feature run audits a module's tests with mutation
# analysis and writes its report under .git/keel/audit/<ts>/report.md (through keel's scripts). It
# finds the seeded weaknesses, edits nothing, and commits nothing.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
d="$(t_tmp)/repo"
/bin/bash "$KEEL_REPO_ROOT/tests/fixtures/mk-sample.sh" "$d" maven-weak >/dev/null
r=$d; before=$(git -C "$r" rev-parse HEAD)
out=$(scn_claude "$r" 40 "/keel:test-audit ." --output-format stream-json --verbose)
assert_eq yes "$(scn_bash_ran "$out" 'keel-state (guard|require)')" "the guard self-check runs first (out: $out)"
assert_eq yes "$(scn_bash_ran "$out" 'keel-mutate .*--module')" "keel-mutate runs in audit mode"
g=$(git -C "$r" rev-parse --absolute-git-dir)
rep=$(ls "$g"/keel/audit/*/report.md 2>/dev/null | head -1)
assert_eq yes "$([ -n "$rep" ] && echo yes)" "the report is written under .git/keel/audit/<ts>/"
txt=$(tr 'A-Z' 'a-z' < "${rep:-/dev/null}")
assert_contains "$txt" "should_compute_fee_when_amount_is_large" "it names the test that kills nothing"
assert_eq yes "$(printf '%s' "$txt" | grep -qE 'overlap|duplicate|redundan' && echo yes)" "it reports the duplicate tests"
assert_eq yes "$(printf '%s' "$txt" | grep -qE 'feecalculator:8|line 8|coverage gap' && echo yes)" "it reports the untested branch"
assert_eq "$before" "$(git -C "$r" rev-parse HEAD)" "nothing is committed"
assert_eq "" "$(git -C "$r" status --porcelain)" "nothing in the tree changes (build files included)"
t_summary
