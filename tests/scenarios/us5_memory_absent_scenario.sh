#!/bin/bash
# US5-AS3 / SC-008: with no memory tool at all, plan and finish behave the same and report no error.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
cfg=$(t_tmp)/mcp.json; printf '{"mcpServers":{}}\n' > "$cfg"
r=$(scn_sample)
f=001-price-is-zero
scn_light_feature "$r" "$f" "Price isZero" "Price MUST report whether its amount is zero, through an isZero() check."
rm -f "$r/specs/$f/plan.md"
out1=$(scn_claude "$r" 40 "/keel:plan --feature $f" --mcp-config "$cfg" --strict-mcp-config --output-format stream-json --verbose)
assert_contains "$(cat "$r/specs/$f/plan.md" 2>/dev/null)" "**Plan status**: complete" "plan completes without memory (out: $out1)"
assert_eq tasks "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "and the run moves on"
assert_eq no "$(scn_result "$out1" | tr 'A-Z' 'a-z' | grep -qE 'engram|mem_save|memory (is )?(not available|unavailable|failed)' && echo yes || echo no)" "absence is silent"
scn_analyzed "$r" "$f" "- [X] T001 [US1] Add Price.isZero() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)"
python3 -I - "$r/src/main/java/shop/Price.java" "$r/src/test/java/shop/PriceTest.java" <<'PY'
import sys
p, t = sys.argv[1], sys.argv[2]
s = open(p).read().rstrip(); s = s[:-1] + "\n    public boolean isZero() {\n        return minor == 0;\n    }\n}\n"; open(p, "w").write(s)
s = open(t).read().rstrip(); s = s[:-1] + "\n    @Test\n    void should_be_zero_when_amount_is_zero() {\n        org.junit.jupiter.api.Assertions.assertTrue(new Price(0).isZero());\n    }\n}\n"; open(t, "w").write(s)
PY
git -C "$r" add -A -- src; git -C "$r" commit -q -m "feat(price): T001 add Price.isZero"
printf '# Test Quality: %s\n\n**Result**: not-run (scenario fixture)\n' "$f" > "$r/specs/$f/test-quality.md"
git -C "$r" add -A -- specs; git -C "$r" commit -q -m "test($f): test-quality"
scn_keel "$r" keel-ledger append "$f" review done "$(git -C "$r" rev-parse HEAD)" >/dev/null
out2=$(scn_claude "$r" 60 "/keel:finish --feature $f" --mcp-config "$cfg" --strict-mcp-config --output-format stream-json --verbose)
assert_eq done "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "finish completes without memory (out: $out2)"
assert_eq no "$(scn_result "$out2" | tr 'A-Z' 'a-z' | grep -qE 'mem_save (failed|error)|engram (error|failed)' && echo yes || echo no)" "no memory error is reported"
t_summary
