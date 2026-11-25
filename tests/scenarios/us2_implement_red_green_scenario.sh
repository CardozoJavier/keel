#!/bin/bash
# FR-014 / FR-020 / SC-003 / SC-004: implement runs one behavior task as a work unit. The result:
# RED before GREEN recorded by keel-evidence, a passing keel-verify for the task, [X] in tasks.md,
# a commit carrying the task ID in the host's style with no AI co-author trailer, and a clean tree.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
f=001-price-is-zero
scn_light_feature "$r" "$f" "Price isZero" "Price MUST report whether its amount is zero, through an isZero() check."
scn_analyzed "$r" "$f" "- [ ] T001 [US1] Add Price.isZero() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)"
assert_eq implement "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged at implement"
out=$(scn_claude "$r" 120 "/keel:implement --feature $f")
subj=$(git -C "$r" log -1 --format=%s)
assert_contains "$subj" "T001" "the task commit carries the task ID (subject: $subj; out: $out)"
assert_eq yes "$(printf '%s' "$subj" | grep -qE '^(feat|fix|test|refactor|chore|docs)(\([^)]+\))?: ' && echo yes)" "the subject follows the host's Conventional Commits style"
assert_eq no "$(git -C "$r" log -1 --format=%B | grep -qi 'co-authored-by' && echo yes || echo no)" "no AI co-author trailer"
assert_eq yes "$(grep -q '^- \[X\] T001 ' "$r/specs/$f/tasks.md" && echo yes)" "T001 is ticked"
assert_eq 0 "$(scn_keel "$r" keel-evidence check "$f" T001 >/dev/null; echo $?)" "keel-evidence check passes: RED before GREEN"
g=$(git -C "$r" rev-parse --absolute-git-dir)
assert_eq yes "$([ -f "$g/keel/$f/verify/T001.log" ] && echo yes)" "keel-verify ran for T001"
assert_eq "" "$(git -C "$r" status --porcelain | grep -v '\.specify/feature\.json$')" "the tree is clean"
assert_contains "$(cat "$r/src/main/java/shop/Price.java")" "isZero" "the production change is committed"
st=$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')
assert_eq mutate "$st" "keel-state moves on to mutate"
t_summary
