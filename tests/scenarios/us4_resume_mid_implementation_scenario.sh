#!/bin/bash
# US4-AS2 / SC-005: `/keel:run` with no argument resumes a feature interrupted mid-implementation. T001
# is already committed; the run implements only T002, asks no gate again, and carries on through
# mutate, review and finish. (US4-AS1, re-entry after Gate 2, is us1_plan_reentry; the script-level
# matrix is tests/scripts/resume_matrix_test.sh.)
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
f=001-price-checks
scn_light_feature "$r" "$f" "Price checks" "Price MUST offer isZero() (amount is 0) and isPositive() (amount above 0)."
scn_analyzed "$r" "$f" "- [ ] T001 [US1] Add Price.isZero() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)
- [ ] T002 [US1] Add Price.isPositive() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)"
python3 -I - "$r/src/main/java/shop/Price.java" "$r/src/test/java/shop/PriceTest.java" <<'PY'
import sys
p, t = sys.argv[1], sys.argv[2]
s = open(p).read().rstrip(); s = s[:-1] + "\n    public boolean isZero() {\n        return minor == 0;\n    }\n}\n"; open(p, "w").write(s)
s = open(t).read().rstrip(); s = s[:-1] + "\n    @Test\n    void should_be_zero_when_amount_is_zero() {\n        org.junit.jupiter.api.Assertions.assertTrue(new Price(0).isZero());\n        org.junit.jupiter.api.Assertions.assertFalse(new Price(1).isZero());\n    }\n}\n"; open(t, "w").write(s)
PY
scn_keel "$r" keel-ledger append "$f" implement started "$(git -C "$r" rev-parse HEAD)" T001 n/a src/main/java/shop/Price.java >/dev/null
sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"
git -C "$r" add -A -- src specs; git -C "$r" commit -q -m "feat(price): T001 add Price.isZero"
scn_keel "$r" keel-ledger append "$f" implement ok "$(git -C "$r" rev-parse HEAD)" T001 >/dev/null
assert_eq implement "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged mid-implementation"
t001=$(git -C "$r" rev-parse HEAD)

out=$(scn_claude "$r" 250 "/keel:run" --output-format stream-json --verbose)
res=$(scn_result "$out")
assert_eq 1 "$(git -C "$r" log --format=%s | grep -cE '(^|[^A-Za-z0-9])T001([^A-Za-z0-9-]|$)')" "T001 is not redone (out: $out)"
assert_eq "$t001" "$(git -C "$r" log --format=%H --grep=T001 -1)" "its commit is the original one"
assert_eq 1 "$(git -C "$r" log --format=%s | grep -cE '(^|[^A-Za-z0-9])T002([^A-Za-z0-9-]|$)')" "T002 is implemented once"
assert_eq 0 "$(scn_dispatches "$out" architect)" "no design work is redone"
assert_eq no "$(printf '%s' "$res" | tr 'A-Z' 'a-z' | grep -qE '(approve|approval|which design|pick a design|choose a design)[^.]*\?' && echo yes || echo no)" "no gate is asked again"
st=$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')
assert_eq done "$st" "the resumed run finishes the feature (STEP=$st)"
assert_eq "" "$(git -C "$r" log --format=%B "$t001..HEAD" | grep -i 'co-authored-by')" "no AI co-author trailers"
assert_eq yes "$(printf '%s' "$res" | tr 'A-Z' 'a-z' | grep -qE "not pushed|nothing (is |was |has been )?pushed|did not push|didn't push" && echo yes)" "the final report says not pushed"
assert_contains "$(git -C "$r" log -1 --format=%s -- "specs/$f/spec.md")" "001" "the finish commit names the feature number (data-model §3)"
t_summary
