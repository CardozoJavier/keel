#!/bin/bash
# lib/pit-xml.sh (contracts/mutation-runner.md §Output): PIT mutations.xml (one <mutation> per line)
# to TSV rows: class method desc mutator indexes line status killing succeeding covering sourceFile.
# Entities are decoded and JUnit unique IDs normalized to C#m; a malformed mutation line is exit 12.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
. "$KEEL_PLUGIN_ROOT/lib/pit-xml.sh"
FX="$KEEL_REPO_ROOT/tests/fixtures/pit"
col() { awk -F'\t' -v n="$1" -v c="$2" 'NR == n { print $c }'; }

# --- the seeded weak fixture's real PIT output ---------------------------------------------------
out=$(keel_pit_rows "$FX/weak-mutations.xml"); rc=$?
assert_eq 0 "$rc" "a real mutations.xml parses"
assert_eq 7 "$(printf '%s\n' "$out" | grep -c .)" "one row per mutation"
row=$(printf '%s\n' "$out" | awk -F'\t' '$6 == 8 && $4 ~ /MathMutator$/')
assert_eq "weak.FeeCalculator" "$(printf '%s' "$row" | cut -f1)" "class"
assert_eq "feeMinor" "$(printf '%s' "$row" | cut -f2)" "method"
assert_eq "(J)J" "$(printf '%s' "$row" | cut -f3)" "method description"
assert_eq "11" "$(printf '%s' "$row" | cut -f5)" "indexes"
assert_eq "NO_COVERAGE" "$(printf '%s' "$row" | cut -f7)" "status"
assert_eq "FeeCalculator.java" "$(printf '%s' "$row" | cut -f11)" "source file"
killed=$(printf '%s\n' "$out" | awk -F'\t' '$6 == 11')
assert_eq "weak.FeeCalculatorTest#should_charge_minimum_fee_when_amount_is_small|weak.FeeCalculatorTest#should_charge_minimum_fee_when_amount_is_tiny" \
  "$(printf '%s' "$killed" | cut -f8)" "killing tests are normalized to C#m and |-separated"
assert_contains "$(printf '%s' "$killed" | cut -f9)" "weak.FeeCalculatorTest#should_compute_fee_when_amount_is_large" "succeeding tests are normalized"
assert_eq 3 "$(printf '%s' "$killed" | cut -f10 | tr '|' '\n' | grep -c .)" "covering tests are kept for the fail-closed check"

# --- edge cases ----------------------------------------------------------------------------------
out=$(keel_pit_rows "$FX/edge-mutations.xml"); rc=$?
assert_eq 0 "$rc" "edge cases parse"
assert_eq 'pay.Ledger$Entry' "$(printf '%s\n' "$out" | col 1 1)" "a nested mutated class keeps its \$"
assert_eq '<init>' "$(printf '%s\n' "$out" | col 1 2)" "entities in the method name are decoded"
assert_eq '(Ljava/util/List<Ljava/lang/String;>;)V' "$(printf '%s\n' "$out" | col 1 3)" "entities in the description are decoded"
assert_eq '3,7' "$(printf '%s\n' "$out" | col 1 5)" "several indexes join with commas"
assert_eq 'pay.LedgerTest$Entries#should_reject_empty_entries' "$(printf '%s\n' "$out" | col 1 8)" "a nested test class becomes C\$N#m"
assert_eq 'pay.LedgerTest#balances|pay.LedgerTest#should_sum' "$(printf '%s\n' "$out" | col 2 8)" "test-factory and test-template IDs become C#m"
assert_eq 'weird-runner:opaque-id-42' "$(printf '%s\n' "$out" | col 2 9)" "an unknown ID form is kept raw"
assert_eq '' "$(printf '%s\n' "$out" | col 3 8)" "self-closing empty lists are empty"
assert_eq 'NO_COVERAGE' "$(printf '%s\n' "$out" | col 3 7)" "status of the third row"

# --- malformed -----------------------------------------------------------------------------------
bad=$(t_tmp)/bad.xml
{ head -2 "$FX/weak-mutations.xml"; printf "<mutation detected='false' numberOfTestsRun='0'><sourceFile>X.java</sourceFile><lineNumber>3</lineNumber></mutation>\n"; printf '</mutations>\n'; } > "$bad"
keel_pit_rows "$bad" >/dev/null 2>&1; rc=$?
assert_eq 12 "$rc" "a mutation line without mutatedClass and status is a tool failure (exit 12)"
keel_pit_rows "$(t_tmp)/missing.xml" >/dev/null 2>&1; rc=$?
assert_eq 12 "$rc" "a missing file is a tool failure (exit 12)"
t_summary
