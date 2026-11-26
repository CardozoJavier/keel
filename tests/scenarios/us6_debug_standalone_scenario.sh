#!/bin/bash
# FR-027 / FR-016 / T044: /keel:debug outside a feature run finds the root cause of a failing test
# before fixing it, fixes the production code (not the test), and shows passing output. It writes
# no feature state and commits nothing.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
# plant the bug: plus subtracts
sed -i '' 's/Math.addExact(minor, other.minor)/Math.subtractExact(minor, other.minor)/' "$r/src/main/java/shop/Price.java"
git -C "$r" add -A; git -C "$r" commit -q -m "refactor(shop): tidy plus"
before=$(git -C "$r" rev-parse HEAD)
test_before=$(git -C "$r" hash-object src/test/java/shop/PriceTest.java)
out=$(scn_claude "$r" 40 "/keel:debug PriceTest.should_add_minor_units_when_adding_two_prices fails" --output-format stream-json --verbose)
o=$(scn_result "$out" | tr 'A-Z' 'a-z')
assert_eq yes "$(scn_bash_ran "$out" 'keel-state (guard|require)')" "the skill runs the guard self-check first"
assert_contains "$(cat "$r/src/main/java/shop/Price.java")" "Math.addExact(minor, other.minor)" "the root cause is fixed in production code (out: $out)"
assert_eq "$test_before" "$(git -C "$r" hash-object src/test/java/shop/PriceTest.java)" "the failing test is not weakened"
assert_eq yes "$(printf '%s' "$o" | grep -qE 'root cause|subtract' && echo yes)" "the report names the root cause"
assert_eq yes "$(printf '%s' "$o" | grep -qE 'tests run: 2|2 tests|2/2|pass' && echo yes)" "and shows passing output"
assert_eq 0 "$(cd "$r" && mvn -q test >/dev/null 2>&1; echo $?)" "the suite passes afterwards"
assert_eq no "$([ -d "$(git -C "$r" rev-parse --absolute-git-dir)/keel" ] && echo yes || echo no)" "no feature state is written"
assert_eq "$before" "$(git -C "$r" rev-parse HEAD)" "nothing is committed"
t_summary
