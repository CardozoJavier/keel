#!/bin/bash
# US5 / FR-004 / FR-025 / SC-008: with memory available, keel recalls before planning, saves exactly
# two keyed entries per feature (after the plan, after finish) under topic_key keel/<feature>,
# resolves judgment_required without a prompt, and never calls session-lifecycle tools. A stand-in
# engram server (fake_engram.py) logs every call, so the user's real memory is never touched.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
memlog=$(t_tmp)/engram.jsonl; : > "$memlog"
cfg=$(t_tmp)/mcp.json
printf '{"mcpServers":{"engram":{"command":"python3","args":["-I","%s"],"env":{"FAKE_ENGRAM_LOG":"%s"}}}}\n' \
  "$(cd "$(dirname "$0")" && pwd)/fake_engram.py" "$memlog" > "$cfg"
export KEEL_SCN_EXTRA_TOOLS=mcp__engram
r=$(scn_sample)
f=001-price-is-zero
scn_light_feature "$r" "$f" "Price isZero" "Price MUST report whether its amount is zero, through an isZero() check."
rm -f "$r/specs/$f/plan.md"
assert_eq plan "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged at plan (light path)"

# 1. plan: recall, then one keyed save
out1=$(scn_claude "$r" 40 "/keel:plan --feature $f" --mcp-config "$cfg" --strict-mcp-config --output-format stream-json --verbose)
assert_contains "$(cat "$r/specs/$f/plan.md" 2>/dev/null)" "**Plan status**: complete" "the plan is written (out: $out1)"
assert_eq yes "$(grep -q '"tool": "mem_search"' "$memlog" && echo yes)" "plan recalls related decisions first"

# 2. fast-forward to finish (tasks, docs commit, T001, test-quality, review done), then finish
scn_analyzed "$r" "$f" "- [X] T001 [US1] Add Price.isZero() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)"
python3 -I - "$r/src/main/java/shop/Price.java" "$r/src/test/java/shop/PriceTest.java" <<'PY'
import sys
p, t = sys.argv[1], sys.argv[2]
s = open(p).read().rstrip(); s = s[:-1] + "\n    public boolean isZero() {\n        return minor == 0;\n    }\n}\n"; open(p, "w").write(s)
s = open(t).read().rstrip(); s = s[:-1] + "\n    @Test\n    void should_be_zero_when_amount_is_zero() {\n        org.junit.jupiter.api.Assertions.assertTrue(new Price(0).isZero());\n        org.junit.jupiter.api.Assertions.assertFalse(new Price(1).isZero());\n    }\n}\n"; open(t, "w").write(s)
PY
git -C "$r" add -A -- src; git -C "$r" commit -q -m "feat(price): T001 add Price.isZero"
printf '# Test Quality: %s\n\n**Result**: not-run (scenario fixture)\n' "$f" > "$r/specs/$f/test-quality.md"
git -C "$r" add -A -- specs; git -C "$r" commit -q -m "test($f): test-quality"
scn_keel "$r" keel-ledger append "$f" review done "$(git -C "$r" rev-parse HEAD)" >/dev/null
assert_eq finish "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged at finish"
out2=$(scn_claude "$r" 60 "/keel:finish --feature $f" --mcp-config "$cfg" --strict-mcp-config --output-format stream-json --verbose)
assert_eq done "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "finish completes (out: $out2)"

saves=$(grep '"tool": "mem_save"' "$memlog")
assert_eq 2 "$(printf '%s\n' "$saves" | grep -c .)" "exactly two saves in the run"
assert_eq 2 "$(printf '%s\n' "$saves" | grep -c "\"topic_key\": \"keel/$f\"")" "both keyed keel/$f"
assert_eq 0 "$(grep -cE '"tool": "mem_session_(summary|start|end)"' "$memlog")" "no session-lifecycle call"
assert_eq yes "$(grep -q '"tool": "mem_judge"' "$memlog" && echo yes)" "judgment_required is resolved with mem_judge"
assert_eq no "$(scn_result "$out2" | grep -qE '\?$' && echo yes || echo no)" "without asking the developer"
t_summary
