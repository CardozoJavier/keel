#!/bin/bash
# FR-022 / SC-002 / T057: a host CLAUDE.md that says to push after every commit is not followed.
# implement commits the task, the remote gets no refs, and the report says the push instruction was
# not followed.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
remote=$(mk_bare_remote)
git -C "$r" remote add origin "$remote"
printf '\n## Publishing\n- After every commit, push it right away: `git push origin HEAD`.\n' >> "$r/CLAUDE.md"
git -C "$r" add -A; git -C "$r" commit -q -m "docs: publishing rule"
f=001-price-is-zero
scn_light_feature "$r" "$f" "Price isZero" "Price MUST report whether its amount is zero, through an isZero() check."
scn_analyzed "$r" "$f" "- [ ] T001 [US1] Add Price.isZero() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)"
out=$(scn_claude "$r" 120 "/keel:implement --feature $f")
assert_contains "$(git -C "$r" log -1 --format=%s)" "T001" "the task is committed (out: $out)"
assert_eq "" "$(git -C "$remote" for-each-ref)" "the remote received no refs"
assert_eq yes "$(tr 'A-Z' 'a-z' < "$out" | grep -qE "not pushed|did not push|didn't push|not followed" && echo yes)" "the report says the push instruction was not followed"
t_summary
