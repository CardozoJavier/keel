#!/bin/bash
# keel-plan-round (FR-010): renders a plan-review round, which the reviewer stored itself with
# keel-put, into plan.md's ## Plan Review from templates/plan-review.md. The reviewer's output goes
# in byte for byte; the orchestrator never retypes it.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
P="$KEEL_PLUGIN_ROOT/bin/keel-plan-round"
f=001-x
r=$(mk_repo); git -C "$r" commit -q --allow-empty -m init
mkdir -p "$r/specs/$f"
printf '# Plan: x\n\n## Summary\n\nText.\n' > "$r/specs/$f/plan.md"
put() { (cd "$r" && "$KEEL_PLUGIN_ROOT/bin/keel-put" $f "plan-review/round-$1.md" >/dev/null); }
pl() { (cd "$r" && "$P" "$@" 2>&1); }
plan() { cat "$r/specs/$f/plan.md"; }

out=$(pl $f 1); rc=$?
assert_eq 3 "$rc" "no stored round: exit 3"
assert_contains "$out" "MISSING=round" "names the missing round"
assert_exit 1 "rejects an invalid feature name" -- sh -c "cd '$r' && '$P' ../x 1"
assert_exit 1 "rejects a round that is not a number" -- sh -c "cd '$r' && '$P' $f x"

round1='## 1. Critical flaws
None.

## 2. Missing assumptions
- `$HOME`, & and \1 and a back\\slash stay literal

## 3. Revised plan (deltas only)
- none

## 4. Verdict
GO: covered'
printf '%s\n' "$round1" | put 1
out=$(pl $f 1); rc=$?
assert_eq 0 "$rc" "round 1 renders"
assert_contains "$out" "VERDICT=GO" "prints the verdict"
assert_contains "$(plan)" "## Plan Review" "creates the Plan Review section"
assert_contains "$(plan)" "### Round 1 ($(date +%Y-%m-%d))" "round heading with today's date"
assert_contains "$(plan)" "**Verdict**: GO" "verdict line"
assert_contains "$(plan)" "$round1" "the reviewer's output, byte for byte"
assert_contains "$(plan)" "**Dispositions**:" "a Dispositions line for the orchestrator to fill"
assert_not_contains "$(plan)" "{{" "no template placeholders left"
assert_eq "# Plan: x" "$(head -1 "$r/specs/$f/plan.md")" "the rest of the plan is kept"

# a round already in plan.md is left as it is (its dispositions may have been filled in)
sed 's/^\*\*Dispositions\*\*:$/**Dispositions**: none/' "$r/specs/$f/plan.md" > "$r/tmp.md" && cat "$r/tmp.md" > "$r/specs/$f/plan.md"
cp "$r/specs/$f/plan.md" "$r/once.md"
out=$(pl $f 1)
assert_eq "" "$(diff "$r/once.md" "$r/specs/$f/plan.md")" "rendering a round twice changes nothing"
assert_contains "$out" "VERDICT=GO" "and still prints its verdict"

printf '## 1. Critical flaws\n- x\n\n## 4. Verdict\nNO_GO: blocker x\n' | put 2
out=$(pl $f 2)
assert_contains "$out" "VERDICT=NO_GO" "NO_GO verdict"
assert_eq "1 2" "$(grep -o '^### Round [0-9]*' "$r/specs/$f/plan.md" | awk '{ printf "%s%s", s, $3; s = " " }')" "round 2 follows round 1"
assert_contains "$(plan)" "$round1" "round 1's output is still intact"

printf '## 4. Verdict\nmaybe\n' | put 3
cp "$r/specs/$f/plan.md" "$r/before.md"
out=$(pl $f 3); rc=$?
assert_eq 3 "$rc" "no GO or NO_GO verdict: exit 3"
assert_contains "$out" "MISSING=verdict" "names the missing verdict"
assert_eq "" "$(diff "$r/before.md" "$r/specs/$f/plan.md")" "plan.md is unchanged"

# rounds stay inside ## Plan Review when another section follows it; the reviewer's own "## "
# headings don't end the section
r2=$(mk_repo); git -C "$r2" commit -q --allow-empty -m init; mkdir -p "$r2/specs/$f"
r=$r2
printf '# Plan: y\n\n## Plan Review\n\n## Complexity Tracking\n\nNone.\n' > "$r/specs/$f/plan.md"
printf '%s\n' "$round1" | put 1; pl $f 1 >/dev/null
printf '## 4. Verdict\nGO\n' | put 2; pl $f 2 >/dev/null
assert_eq "## Plan Review|### Round 1|### Round 2|## Complexity Tracking" \
  "$(grep -E '^(## Plan Review|### Round [0-9]+|## Complexity Tracking)' "$r/specs/$f/plan.md" | sed 's/ (.*//' | paste -sd'|' -)" \
  "both rounds sit inside Plan Review, before the next section"
assert_contains "$(plan)" "$round1" "round 1 intact when round 2 is inserted"

# the plan template's placeholder round is replaced, not mistaken for a recorded round
r3=$(mk_repo); git -C "$r3" commit -q --allow-empty -m init; mkdir -p "$r3/specs/$f"
r=$r3
printf '# Plan: z\n\n## Plan Review\n\n<!-- keel: one round per fresh plan-reviewer -->\n\n### Round 1 ([DATE])\n\n**Verdict**: [GO | NO_GO]\n\n[Reviewer output]\n\n**Dispositions**: [blocker]: resolved\n' > "$r/specs/$f/plan.md"
printf '%s\n' "$round1" | put 1; pl $f 1 >/dev/null
assert_eq 1 "$(grep -c '^### Round 1 ' "$r/specs/$f/plan.md")" "one Round 1"
assert_not_contains "$(plan)" "[DATE]" "the placeholder round is gone"
assert_contains "$(plan)" "$round1" "the stored round is in its place"
assert_contains "$(plan)" "<!-- keel: one round per fresh plan-reviewer -->" "the section comment is kept"
t_summary
