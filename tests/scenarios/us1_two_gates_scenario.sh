#!/bin/bash
# US1 independent test / SC-002 / FR-006..FR-010: on the full path a run reaches plan GO with
# exactly two approvals: Gate 1 (spec) and Gate 2 (design). Three sessions:
#   1. /keel:run with all clarification answers given: stops at Gate 1.
#   2. "approve, full path": explorers and 2-3 architects run, and it stops at Gate 2.
#   3. the design pick: Design Decision, plan artifacts, fresh reviewer rounds to GO, then keel-state
#      moves to tasks without a third question.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_repo); scn_constitution "$r"
mkdir -p "$r/src/main/java/shop"
printf 'package shop;\n\npublic record Price(long minor) {\n    public Price {\n        if (minor < 0) throw new IllegalArgumentException("negative");\n    }\n}\n' > "$r/src/main/java/shop/Price.java"
printf '# Shop\n\n- Build and test: `mvn -q verify`\n- Commits: Conventional Commits; never add an AI co-author trailer.\n' > "$r/CLAUDE.md"
git -C "$r" add -A; git -C "$r" commit -q -m init
prompt='/keel:run Prices can be discounted by a percentage between 0 and 100.

Clarification answers, so you do not need to ask anything:
- Intent and why: marketing runs percentage promotions and enters final prices by hand today.
- Goals: a price can be reduced by a whole-number percentage, rounding half up to the cent.
- Non-goals: stacking discounts; currencies.
- Anti-goals: a discount that ever produces a negative price.
- Missing requirements: none.'

# 1. Gate 1
out1=$(scn_claude "$r" 60 "$prompt")
spec=$(ls "$r"/specs/001-*/spec.md 2>/dev/null | head -1)
f=$(basename "$(dirname "$spec")")
assert_contains "$(cat "$spec" 2>/dev/null)" "**Status**: Draft" "session 1 ends at Gate 1 with a draft spec (out: $out1)"
assert_eq clarify "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "keel-state waits at clarify (Gate 1)"

# 2. Gate 2
out2=$(scn_continue "$r" 80 "I approve the spec. Use the full path." --output-format stream-json --verbose)
assert_contains "$(cat "$spec")" "**Path**: full" "Gate 1 records the full path"
assert_contains "$(cat "$spec")" "**Status**: Approved (Gate 1," "Gate 1 records the approval"
n=$(scn_dispatches "$out2" architect)
case "$n" in 2 | 3) _t_pass ;; *) _t_fail "2-3 architects are dispatched, one per lens (got $n; out: $out2)" ;; esac
assert_eq yes "$([ "$(scn_dispatches "$out2" explorer)" -ge 1 ] && echo yes)" "explorers map the code first"
assert_eq no "$(grep -qs '^\*\*Chosen\*\*' "$r/specs/$f/plan.md" && echo yes || echo no)" "no design is chosen before Gate 2 is answered"

# 3. design pick -> plan GO, no third gate
out3=$(scn_continue "$r" 150 "Go with the pragmatic balance design." --output-format stream-json --verbose)
plan="$r/specs/$f/plan.md"
assert_contains "$(cat "$plan" 2>/dev/null)" "**Chosen**: " "the Design Decision records the pick (out: $out3)"
assert_contains "$(cat "$plan" 2>/dev/null)" "### Rejected designs" "rejected designs are recorded with trade-offs"
assert_contains "$(cat "$plan" 2>/dev/null)" "**Plan status**: complete" "plan artifacts are complete"
assert_contains "$(cat "$plan" 2>/dev/null)" "## Plan Review" "plan review rounds are appended"
assert_eq yes "$(grep -qE '^\*\*Verdict\*\*: GO' "$plan" 2>/dev/null && echo yes)" "the last round is GO"
assert_eq yes "$([ "$(scn_dispatches "$out3" plan-reviewer)" -ge 1 ] && echo yes)" "a fresh plan-reviewer is dispatched"
assert_eq 0 "$(scn_dispatches "$out3" architect)" "architects are not re-run after Gate 2"
st=$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')
case "$st" in tasks | analyze | implement | mutate | review | finish | done) _t_pass ;; *) _t_fail "after two approvals keel-state is past plan (STEP=$st)" ;; esac
t_summary
