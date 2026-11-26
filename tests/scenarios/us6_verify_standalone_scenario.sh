#!/bin/bash
# FR-027 / SC-011 / T045: /keel:verify outside a feature run detects the host's build, runs it,
# shows the evidence and claims only what it shows. It writes no feature state and commits nothing.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
before=$(git -C "$r" rev-parse HEAD)
out=$(scn_claude "$r" 20 "/keel:verify" --output-format stream-json --verbose)
o=$(scn_result "$out")
assert_eq yes "$(scn_bash_ran "$out" 'keel-state (guard|require)')" "the skill runs the guard self-check first"
assert_contains "$o" "mvn" "the build-and-test command is named (out: $out)"
assert_eq yes "$(printf '%s' "$o" | grep -qiE 'tests run: 2|2 run|2 tests|2/2|2 passed' && echo yes)" "the evidence shows the 2 tests that ran"
assert_eq yes "$(printf '%s' "$o" | tr 'A-Z' 'a-z' | grep -qE 'pass|success' && echo yes)" "and the result"
assert_eq no "$([ -d "$(git -C "$r" rev-parse --absolute-git-dir)/keel" ] && echo yes || echo no)" "no feature state is written"
assert_eq "$before" "$(git -C "$r" rev-parse HEAD)" "nothing is committed"
assert_eq "" "$(git -C "$r" status --porcelain)" "the tree is unchanged"
t_summary
