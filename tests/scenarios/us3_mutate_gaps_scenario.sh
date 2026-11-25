#!/bin/bash
# US3 / FR-030..FR-034 / SC-013 / SC-014: mutate measures the feature's changed lines on the seeded weak
# fixture, closes the gaps in MUT-n units (tests only, or committed triage), commits test-quality.md with
# a computed Result, and never touches the build files. An independent keel-mutate + keel-classify run
# afterwards must agree that nothing blocks.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
d="$(t_tmp)/repo"
/bin/bash "$KEEL_REPO_ROOT/tests/fixtures/mk-sample.sh" "$d" maven-weak >/dev/null
r=$d; full=$(git -C "$r" rev-parse HEAD)
scn_constitution "$r"; git -C "$r" add -A; git -C "$r" commit -q -m "docs: constitution"
git -C "$r" rm -q -r src; git -C "$r" commit -q -m "chore: start without the calculator"
f=001-fee-calculator
scn_light_feature "$r" "$f" "Fee calculator" "FeeCalculator.feeMinor(amountMinor) MUST charge 2% of the amount with a floor of 30, and 1% for amounts above 10,000,000."
scn_analyzed "$r" "$f" "- [ ] T001 [US1] Add FeeCalculator.feeMinor in src/main/java/weak/FeeCalculator.java (test: src/test/java/weak/FeeCalculatorTest.java)"
git -C "$r" checkout -q "$full" -- src
sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"
git -C "$r" add -A -- src specs; git -C "$r" commit -q -m "feat(fee): T001 add FeeCalculator"
assert_eq mutate "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged at mutate"
base=$(scn_state "$r" --feature "$f" | sed -n 's/^BASE=//p')
pom=$(git -C "$r" hash-object pom.xml)

out=$(scn_claude "$r" 150 "/keel:mutate --feature $f" --output-format stream-json --verbose)
assert_eq yes "$(scn_bash_ran "$out" 'keel-mutate .*--base')" "keel-mutate ran on the feature (out: $out)"
assert_eq yes "$(git -C "$r" log --format=%s "$base..HEAD" | grep -qE '(^|[^A-Za-z0-9])MUT-1([^A-Za-z0-9-]|$)' && echo yes)" "gaps are closed in a MUT-1 unit commit"
mutc=$(git -C "$r" log --format=%H --grep='MUT-1' -1)
assert_eq "" "$(git -C "$r" show --name-only --format= "$mutc" | grep -vE '^(src/test/|specs/'"$f"'/test-quality\.triage\.tsv$)')" "the MUT unit changed only tests and the triage file"
tq=$(git -C "$r" show "HEAD:specs/$f/test-quality.md" 2>/dev/null)
assert_contains "$tq" "**Result**: resolved" "test-quality.md is committed as resolved"
assert_contains "$tq" "**Summary**: " "with the computed summary"
assert_contains "$(git -C "$r" log --format=%s -1 --diff-filter=A -- "specs/$f/test-quality.md")" "test-quality" "the commit that adds it says test-quality"
assert_eq "$pom" "$(git -C "$r" hash-object pom.xml)" "pom.xml is byte-identical (SC-014)"
assert_eq "" "$(git -C "$r" status --porcelain | grep -v '\.specify/feature\.json$')" "the tree is clean"
assert_eq review "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "keel-state moves on to review"
g=$(git -C "$r" rev-parse --absolute-git-dir)
check=$(scn_keel "$r" keel-mutate --out "$g/keel/check" --base "$base" --feature "$f")
tri=; [ -f "$r/specs/$f/test-quality.triage.tsv" ] && tri="--triage $r/specs/$f/test-quality.triage.tsv"
"$KEEL_PLUGIN_ROOT/bin/keel-classify" "$g/keel/check/mutants.tsv" $tri >/dev/null; rc=$?
assert_eq 0 "$rc" "an independent re-run agrees: no blocking gap remains (check: $check)"
t_summary
