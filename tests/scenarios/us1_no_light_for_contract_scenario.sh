#!/bin/bash
# US1-AS7 / FR-028 / SC-010: a public API contract change is classified as not small, and the spec
# is a keel spec (Base line). All clarification answers are given up front.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_repo); scn_constitution "$r"
mkdir -p "$r/src/main/java/shop"
cat > "$r/src/main/java/shop/PriceResource.java" <<'EOF'
package shop;

/** GET /prices/{id}: public partner API. Returns {"id": ..., "amountMinor": ...}. */
public final class PriceResource {
    public String get(long id) {
        return "{\"id\":" + id + ",\"amountMinor\":100}";
    }
}
EOF
printf '# Shop\n\n- Build and test: `mvn -q verify`\n- Commits: Conventional Commits; never add an AI co-author trailer.\n' > "$r/CLAUDE.md"
git -C "$r" add -A; git -C "$r" commit -q -m init
prompt='/keel:run Add a `currency` field (ISO 4217 code) to the JSON body returned by the public REST endpoint GET /prices/{id}, which external partners consume.

Clarification answers, so you do not need to ask anything:
- Intent and why: partners price in several currencies and currently guess the currency.
- Goals: every GET /prices/{id} response carries the currency of the stored price.
- Non-goals: currency conversion; changing other endpoints.
- Anti-goals: breaking existing partner clients that ignore unknown fields.
- Missing requirements: the default currency for existing prices is EUR.'
out=$(scn_claude "$r" 60 "$prompt")
spec=$(ls "$r"/specs/001-*/spec.md 2>/dev/null | head -1)
assert_eq yes "$([ -n "$spec" ] && echo yes)" "a spec is written under specs/001-* (out: $out)"
assert_contains "$(cat "$spec" 2>/dev/null)" "**Base**: " "the spec carries keel's Base line"
assert_eq yes "$(grep -qiE '\*\*Qualifies as small\*\*: *no' "$spec" 2>/dev/null && echo yes)" "a contract change does not qualify as small"
assert_not_contains "$(tr 'A-Z' 'a-z' < "$out")" "light path (one gate" "the light path is not offered at Gate 1"
t_summary
