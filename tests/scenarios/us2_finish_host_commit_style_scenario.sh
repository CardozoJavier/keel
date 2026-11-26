#!/bin/bash
# FR-020 / FR-021: finish runs the full verify, sets Status Implemented and commits it in the host's
# style (Conventional Commits, no AI co-author trailer, CLAUDE.md). The final report says not pushed.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
f=001-price-is-zero
scn_light_feature "$r" "$f" "Price isZero" "Price MUST report whether its amount is zero, through an isZero() check."
scn_analyzed "$r" "$f" "- [ ] T001 [US1] Add Price.isZero() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)"
python3 -I - "$r/src/main/java/shop/Price.java" "$r/src/test/java/shop/PriceTest.java" <<'PY'
import sys
p, t = sys.argv[1], sys.argv[2]
s = open(p).read().rstrip()
s = s[:-1] + """
    public boolean isZero() {
        return minor == 0;
    }
}
"""
open(p, "w").write(s)
s = open(t).read().rstrip()
s = s[:-1] + """
    @org.junit.jupiter.api.Test
    void should_be_zero_when_amount_is_zero() {
        org.junit.jupiter.api.Assertions.assertTrue(new Price(0).isZero());
        org.junit.jupiter.api.Assertions.assertFalse(new Price(1).isZero());
    }
}
"""
open(t, "w").write(s)
PY
sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"
git -C "$r" add -A -- src specs; git -C "$r" commit -q -m "feat(shop): T001 add Price.isZero"
printf '# Test Quality: %s\n\n**Result**: not-run (scenario fixture)\n' "$f" > "$r/specs/$f/test-quality.md"
git -C "$r" add -A -- specs; git -C "$r" commit -q -m "test($f): test-quality"
scn_keel "$r" keel-ledger append "$f" review done "$(git -C "$r" rev-parse HEAD)" >/dev/null
assert_eq finish "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged at finish"
out=$(scn_claude "$r" 60 "/keel:finish --feature $f")
assert_contains "$(git -C "$r" show HEAD:specs/$f/spec.md 2>/dev/null)" "**Status**: Implemented (" "the finish commit sets Status Implemented (out: $out)"
subj=$(git -C "$r" log -1 --format=%s)
assert_contains "$subj" "001" "the finish subject names the feature number (subject: $subj)"
assert_eq yes "$(printf '%s' "$subj" | grep -qE '^(feat|fix|docs|chore)(\([^)]+\))?: ' && echo yes)" "the subject follows Conventional Commits"
assert_eq no "$(git -C "$r" log -1 --format=%B | grep -qi 'co-authored-by' && echo yes || echo no)" "no AI co-author trailer"
assert_eq done "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "keel-state is done"
assert_eq "" "$(git -C "$r" status --porcelain | grep -v '\.specify/feature\.json$')" "the tree is clean"
assert_contains "$(tr 'A-Z' 'a-z' < "$out")" "not pushed" "the final report says not pushed"
t_summary
