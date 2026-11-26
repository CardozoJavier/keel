#!/bin/bash
# FR-019 / plan §Review: a verified finding whose fix needs a different design (scope
# changes-design) halts review. The approved plan chose a double return type, while the spec requires
# results exact to the cent, so no fix is possible inside the chosen design. Review must halt: no REV
# commit, and no `review done` row.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
f=001-discount
scn_light_feature "$r" "$f" "Percentage discount" "Price MUST offer discounted(int percent) for percent 0..100; the result MUST be exact to the cent (rounded half up) and MUST never be negative."
# the approved design: return the discounted amount in euros as a double
python3 -I - "$r/specs/$f/plan.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("Implement FR-001 directly in the existing type, test-first.",
              "`Price.discounted(int percent)` returns the discounted amount **in euros as a `double`** "
              "(`minor * (100 - percent) / 10000.0`). Callers format it for display.")
open(p, "w").write(s)
PY
scn_analyzed "$r" "$f" "- [ ] T001 [US1] Add Price.discounted(int) in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)"
python3 -I - "$r/src/main/java/shop/Price.java" "$r/src/test/java/shop/PriceTest.java" <<'PY'
import sys
p, t = sys.argv[1], sys.argv[2]
s = open(p).read().rstrip()
assert s.endswith("}")
s = s[:-1] + """
    /** The discounted amount in euros (plan: Design Decision). */
    public double discounted(int percent) {
        if (percent < 0 || percent > 100) {
            throw new IllegalArgumentException("percent must be 0..100");
        }
        return minor * (100 - percent) / 10000.0;
    }
}
"""
open(p, "w").write(s)
s = open(t).read().rstrip()
assert s.endswith("}")
s = s[:-1] + """
    @org.junit.jupiter.api.Test
    void should_return_discounted_euros_when_percent_is_valid() {
        org.junit.jupiter.api.Assertions.assertEquals(0.9, new Price(100).discounted(10), 1e-9);
    }
}
"""
open(t, "w").write(s)
PY
sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"
git -C "$r" add -A -- src specs; git -C "$r" commit -q -m "feat(shop): T001 add Price.discounted"
printf '# Test Quality: %s\n\n**Result**: not-run (scenario fixture)\n' "$f" > "$r/specs/$f/test-quality.md"
git -C "$r" add -A -- specs; git -C "$r" commit -q -m "test($f): test-quality"
assert_eq review "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged at review"
before=$(git -C "$r" rev-parse HEAD)
out=$(scn_claude "$r" 80 "/keel:review --feature $f" --output-format stream-json --verbose)
assert_eq 3 "$(scn_dispatches "$out" code-reviewer)" "three code-reviewers run, one per lens (out: $out)"
g=$(git -C "$r" rev-parse --absolute-git-dir)
assert_eq yes "$([ -f "$g/keel/$f/review/diff.patch" ] && echo yes)" "the review diff is written by keel-diff --base"
assert_eq yes "$(ls "$g/keel/$f/review/"findings-*.md >/dev/null 2>&1 && echo yes)" "findings are stored with keel-put"
assert_eq "$before" "$(git -C "$r" rev-parse HEAD)" "no REV commit when the fix changes the design"
assert_contains "$(tr 'A-Z' 'a-z' < "$out")" "design" "the halt names the design conflict"
assert_eq review "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "no review done row: keel-state stays at review"
t_summary
