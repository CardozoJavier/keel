#!/bin/bash
# keel-classify (contracts/mutation-runner.md §keel-classify): deterministic classification of
# mutants.tsv into blocking gaps and non-blocking test-suite findings; exit 0/1/2.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
C="$KEEL_PLUGIN_ROOT/bin/keel-classify"
d=$(t_tmp)
H=$(printf 'key\tclass\tmethod\tline\tmutator\tstatus\tin_scope\tkilling\tsucceeding')
S=weak.FeeCalculatorTest#should_charge_minimum_fee_when_amount_is_small
T=weak.FeeCalculatorTest#should_charge_minimum_fee_when_amount_is_tiny
L=weak.FeeCalculatorTest#should_compute_fee_when_amount_is_large
m() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }

# --- the seeded weak fixture, as keel-mutate writes it ----------------------------------------------
{
  printf '%s\n' "$H"
  m k1 weak.FeeCalculator feeMinor 7 ConditionalsBoundaryMutator SURVIVED yes "" "$S|$T|$L"
  m k2 weak.FeeCalculator feeMinor 8 MathMutator NO_COVERAGE yes "" ""
  m k3 weak.FeeCalculator feeMinor 10 MathMutator SURVIVED yes "" "$S|$T|$L"
  m k4 weak.FeeCalculator feeMinor 10 MathMutator KILLED yes "$S|$T" "$L"
  m k5 weak.FeeCalculator feeMinor 7 NegateConditionalsMutator KILLED yes "$S|$T" "$L"
  m k6 weak.FeeCalculator feeMinor 8 PrimitiveReturnsMutator NO_COVERAGE yes "" ""
  m k7 weak.FeeCalculator feeMinor 11 PrimitiveReturnsMutator KILLED yes "$S|$T" "$L"
} > "$d/weak.tsv"
out=$("$C" "$d/weak.tsv"); rc=$?
assert_eq 1 "$rc" "in-scope gaps block: exit 1"
assert_eq 2 "$(printf '%s\n' "$out" | grep -c '^coverage-gap	')" "two coverage gaps (the untested branch)"
assert_contains "$out" "coverage-gap	k2	weak.FeeCalculator:8 feeMinor MathMutator NO_COVERAGE" "gap rows carry class:line, method, mutator, status"
assert_eq 2 "$(printf '%s\n' "$out" | grep -c '^assertion-gap	')" "two assertion gaps"
assert_contains "$out" "assertion-gap	k3	weak.FeeCalculator:10" "the unchecked 2% computation"
assert_contains "$out" "kills-nothing	$L	" "the missing-assertion test kills nothing"
assert_contains "$out" "overlap	$S,$T	3 identical kills" "the duplicate tests overlap"
assert_eq 0 "$(printf '%s\n' "$out" | grep -c '^redundant	')" "overlap members are not also reported as redundant"
while IFS="$(printf '\t')" read -r kind must _; do
  [ "$kind" = kind ] && continue
  assert_eq yes "$(printf '%s\n' "$out" | grep "^$kind	" | grep -qF "$must" && echo yes)" "expected.tsv: $kind contains $must"
done < "$KEEL_REPO_ROOT/tests/fixtures/maven-weak/expected.tsv"
assert_eq "$out" "$("$C" "$d/weak.tsv")" "deterministic output"

# --- triage, scope, exclusions, NO_TEST, redundancy -------------------------------------------------
printf 'k1\tequivalent: the boundary at 10,000,000 has no observable effect\nk2\tnot worth a test: covered by T9\nk3\tx\nk6\ty\n' > "$d/triage.tsv"
out=$("$C" "$d/weak.tsv" --triage "$d/triage.tsv"); rc=$?
assert_eq 0 "$rc" "every in-scope gap triaged: exit 0"
assert_contains "$out" "triaged	k1	equivalent: the boundary at 10,000,000 has no observable effect" "triaged rows carry the reason"
assert_eq 0 "$(printf '%s\n' "$out" | grep -cE '^(coverage|assertion)-gap	')" "no blocking rows remain"
{
  printf '%s\n' "$H"
  m o1 a.A f 3 MathMutator SURVIVED no "" "a.ATest#x"
  m o2 a.A f 4 MathMutator NO_COVERAGE no "" ""
  m n1 a.B - 12 - NO_TEST yes "" ""
  m e1 a.A f 5 MathMutator NON_VIABLE yes "" ""
  m e2 a.A f 6 MathMutator TIMED_OUT yes "" ""
  m e3 a.A f 7 MathMutator RUN_ERROR yes "" ""
  m e4 a.A f 8 MathMutator MEMORY_ERROR yes "" ""
  m r1 a.A g 9 MathMutator KILLED yes "a.ATest#wide|a.ATest#narrow" ""
  m r2 a.A g 10 MathMutator KILLED yes "a.ATest#wide" "a.ATest#narrow"
} > "$d/mixed.tsv"
out=$("$C" "$d/mixed.tsv"); rc=$?
assert_eq 1 "$rc" "an in-scope NO_TEST row blocks"
assert_contains "$out" "coverage-gap	n1	a.B:12 - - NO_TEST" "NO_TEST is a coverage gap"
assert_eq 2 "$(printf '%s\n' "$out" | grep -c '^out-of-scope	')" "out-of-scope gaps are listed, not blocking"
assert_eq 4 "$(printf '%s\n' "$out" | grep -c '^excluded	')" "NON_VIABLE, TIMED_OUT, RUN_ERROR, MEMORY_ERROR are excluded"
assert_contains "$out" "redundant	a.ATest#narrow	kills 1, all also killed by a.ATest#wide" "a strict subset is redundant"
assert_eq 0 "$(printf '%s\n' "$out" | grep -c '^redundant	a.ATest#wide')" "the wider test is not redundant"
assert_eq 0 "$(printf '%s\n' "$out" | grep -c '^kills-nothing	a.ATest#narrow')" "a test that kills something is not kills-nothing"

# --- --summary: the test-quality.md Summary line, computed --------------------------------------------
sum=$("$C" "$d/weak.tsv" --summary); rc=$?
assert_eq 1 "$rc" "--summary keeps the blocking exit code"
assert_eq "SUMMARY=7 mutants (7 in scope); killed 3; coverage gaps 2; assertion gaps 2; triaged 0; excluded 0" "$sum" "summary counts for the weak fixture"
sum=$("$C" "$d/mixed.tsv" --triage "$d/triage.tsv" --summary)
assert_eq "SUMMARY=8 mutants (6 in scope); killed 2; coverage gaps 1 (1 with no test); assertion gaps 0; triaged 0; excluded 4" "$sum" "NO_TEST rows are gaps but not generated mutants; out-of-scope rows are not gaps"
sum=$("$C" "$d/weak.tsv" --triage "$d/triage.tsv" --summary); rc=$?
assert_eq 0 "$rc" "all triaged: exit 0"
assert_eq "SUMMARY=7 mutants (7 in scope); killed 3; coverage gaps 0; assertion gaps 0; triaged 4; excluded 0" "$sum" "triaged gaps are counted as triaged"

# --- --out: rows go to a file (callers never redirect into .git); the exit code is kept ----------------
"$C" "$d/weak.tsv" --out "$d/cls.tsv" > "$d/stdout.txt"; rc=$?
assert_eq 1 "$rc" "--out keeps the blocking exit code"
assert_eq "$("$C" "$d/weak.tsv")" "$(cat "$d/cls.tsv")" "--out writes the same rows"
assert_eq "" "$(cat "$d/stdout.txt")" "and nothing to stdout"

# --- malformed input: exit 2 ---------------------------------------------------------------------
printf 'key\tclass\n' > "$d/badhdr.tsv"
"$C" "$d/badhdr.tsv" >/dev/null 2>&1; assert_eq 2 "$?" "a wrong header is exit 2"
{ printf '%s\n' "$H"; printf 'k\tc\tm\n'; } > "$d/short.tsv"
"$C" "$d/short.tsv" >/dev/null 2>&1; assert_eq 2 "$?" "a short row is exit 2"
{ printf '%s\n' "$H"; m k c m 1 X WEIRD yes "" ""; } > "$d/status.tsv"
"$C" "$d/status.tsv" >/dev/null 2>&1; assert_eq 2 "$?" "an unknown status is exit 2"
printf 'no-tab-here\n' > "$d/badtriage.tsv"
"$C" "$d/weak.tsv" --triage "$d/badtriage.tsv" >/dev/null 2>&1; assert_eq 2 "$?" "a triage row without a reason is exit 2"
"$C" "$d/nothere.tsv" >/dev/null 2>&1; assert_eq 2 "$?" "a missing input is exit 2"
{ printf '%s\n' "$H"; m k1 a.A f 1 MathMutator KILLED yes "a.ATest#x" ""; } > "$d/clean.tsv"
"$C" "$d/clean.tsv" >/dev/null; assert_eq 0 "$?" "no gaps: exit 0"
t_summary
