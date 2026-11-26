#!/bin/bash
# FR-027 / T053: /keel:respond-review verifies each comment against the code. It declines a wrong
# one with evidence, applies a right one test-first with passing output, and commits nothing.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
before=$(git -C "$r" rev-parse HEAD)
prompt='/keel:respond-review Two review comments on src/main/java/shop/Price.java and its test:
1. Price.plus can overflow silently on large amounts; switch it to Math.addExact.
2. There is no test for what happens when plus overflows; add one.'
out=$(scn_claude "$r" 40 "$prompt" --output-format stream-json --verbose)
o=$(scn_result "$out" | tr 'A-Z' 'a-z')
assert_eq yes "$(scn_bash_ran "$out" 'keel-state (guard|require)')" "the skill runs the guard self-check first"
assert_eq yes "$(printf '%s' "$o" | grep -qE 'already' && echo yes)" "comment 1 is declined: plus already uses Math.addExact (out: $out)"
assert_contains "$(cat "$r/src/main/java/shop/Price.java")" "Math.addExact(minor, other.minor)" "production code is unchanged where the comment was wrong"
assert_contains "$(cat "$r/src/test/java/shop/PriceTest.java")" "ArithmeticException" "comment 2 is applied: an overflow test exists"
assert_eq 0 "$(cd "$r" && mvn -q test >/dev/null 2>&1; echo $?)" "the suite passes with the new test"
assert_eq yes "$(printf '%s' "$o" | grep -qE 'tests run: 3|3 tests|3/3|pass' && echo yes)" "passing output is shown"
assert_eq "$before" "$(git -C "$r" rev-parse HEAD)" "nothing is committed"
t_summary
