#!/bin/bash
# US1-AS6 / FR-028 / SC-010: a small change accepted for the light path gets exactly one approval;
# plan writes a single-design plan with no competing designs or plan review, and keel-state moves
# on to tasks.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_repo); scn_constitution "$r"
mkdir -p "$r/src/main/java/shop"
printf 'package shop;\n\npublic record Price(long minor) {\n    public Price {\n        if (minor < 0) throw new IllegalArgumentException("negative");\n    }\n}\n' > "$r/src/main/java/shop/Price.java"
printf '# Shop\n\n- Build and test: `mvn -q verify`\n- Commits: Conventional Commits; never add an AI co-author trailer.\n' > "$r/CLAUDE.md"
git -C "$r" add -A; git -C "$r" commit -q -m init
prompt='/keel:run Add an isZero() method to the Price record that returns true when the amount is 0.

Clarification answers, so you do not need to ask anything:
- Intent and why: callers repeat `price.minor() == 0` in several places.
- Goals: a readable isZero() check.
- Non-goals: any other Price behavior.
- Anti-goals: changing how prices are stored or serialized.
- Missing requirements: none.'
out1=$(scn_claude "$r" 60 "$prompt")
spec=$(ls "$r"/specs/001-*/spec.md 2>/dev/null | head -1)
assert_eq yes "$(grep -qiE '\*\*Qualifies as small\*\*: *yes' "$spec" 2>/dev/null && echo yes)" "a pure in-memory helper qualifies as small (out: $out1)"
out2=$(scn_continue "$r" 60 "I approve the spec with the light path.")
assert_contains "$(cat "$spec")" "**Path**: light" "Gate 1 records the light path"
plan=$(ls "$r"/specs/001-*/plan.md 2>/dev/null | head -1)
assert_contains "$(cat "$plan" 2>/dev/null)" "single design (light path)" "the plan states the single design"
assert_not_contains "$(cat "$plan" 2>/dev/null)" "## Plan Review" "no plan review on the light path"
assert_not_contains "$(tr 'A-Z' 'a-z' < "$out2")" "which design" "no Gate 2 on the light path (out: $out2)"
f=$(basename "$(dirname "$spec")")
st=$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')
case "$st" in tasks | analyze | implement | mutate | review | finish | done) _t_pass ;; *) _t_fail "keel-state moved past plan (STEP=$st)" ;; esac
t_summary
