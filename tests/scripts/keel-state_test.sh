#!/bin/bash
# keel-state (data-model.md §2, contracts/run-state.md): latest-first state derivation with gate
# prerequisites, drift detection, feature binding, base resolution, require, facts, guard check.
# A fixture feature is walked through every row, from no constitution to done.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
S="$KEEL_PLUGIN_ROOT/bin/keel-state"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
ENVSH="$KEEL_PLUGIN_ROOT/hooks/keel-env.sh"
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"
f=001-x
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
ks() { (cd "$r" && /bin/sh -c ". '$ENVSH'; exec '$S' \"\$@\"" keel-state "$@" 2>&1); }
step() { kv "$(ks next "$@")" STEP; }
commit() { git -C "$r" add -A; git -C "$r" commit -q -m "$1"; }

r=$(mk_repo); git -C "$r" commit -q --allow-empty -m init
base=$(git -C "$r" rev-parse HEAD)

# --- guard self-check --------------------------------------------------------------------------
out=$(cd "$r" && env -u GIT_CONFIG_COUNT "$S" next 2>&1); rc=$?
assert_eq 5 "$rc" "without the guard environment keel-state exits 5"
assert_contains "$out" "MISSING=push-guard:" "and reports the missing guard"
assert_exit 0 "guard subcommand passes with the environment" -- sh -c "cd '$r' && . '$ENVSH' && '$S' guard"

# --- constitution, specify -------------------------------------------------------------------------
assert_eq constitution "$(step)" "no constitution"
mkdir -p "$r/.specify/memory"; echo "# [PROJECT_NAME] Constitution" > "$r/.specify/memory/constitution.md"
assert_eq constitution "$(step)" "a constitution with placeholders"
echo "# Shop Constitution" > "$r/.specify/memory/constitution.md"
assert_eq specify "$(step)" "constitution done, no feature: specify"
assert_eq "" "$(kv "$(ks next)" FEATURE)" "no feature bound"

# --- spec, binding, not-a-keel-feature ------------------------------------------------------------
mkdir -p "$r/specs/$f"
printf '# Feature Specification: X\n**Status**: Draft\n**Base**: %s (main)\n' "$base" > "$r/specs/$f/spec.md"
assert_eq clarify "$(step --feature $f)" "draft spec: clarify"
assert_eq '{"feature_directory": "specs/001-x"}' "$(cat "$r/.specify/feature.json")" "next --feature writes feature.json"
assert_eq clarify "$(step)" "feature resolved from feature.json"
assert_eq "$base" "$(kv "$(ks next)" BASE)" "base from the spec's Base line"
mkdir -p "$r/specs/002-plain"; printf '# Feature Specification: Plain\n**Status**: Draft\n' > "$r/specs/002-plain/spec.md"
out=$(ks next --feature 002-plain); rc=$?
assert_eq 4 "$rc" "a spec without a Base line exits 4"
assert_contains "$out" "WHY=not-a-keel-feature" "not-a-keel-feature"
rm -rf "$r/specs/002-plain"; (cd "$r" && "$S" next --feature $f >/dev/null 2>&1 || true)
ks next --feature $f >/dev/null

# --- Gate 1 -------------------------------------------------------------------------------------
sed -i '' 's/^\*\*Status\*\*: Draft$/**Status**: Approved (Gate 1, 2026-11-26)/' "$r/specs/$f/spec.md"
out=$(ks next); rc=$?
assert_eq 4 "$rc" "Approved without a Path line is drift"
assert_contains "$out" "drift" "reports drift"
printf '**Path**: full\n' >> "$r/specs/$f/spec.md"
assert_eq plan "$(step)" "approved: plan"
assert_eq full "$(kv "$(ks next)" PATH)" "path full"

# --- plan, plan review ---------------------------------------------------------------------------
printf '# Plan\n**Plan status**: draft\n## Design Decision\n**Chosen**: pragmatic (Gate 2, 2026-11-26)\n' > "$r/specs/$f/plan.md"
assert_eq plan "$(step)" "design chosen but plan incomplete: plan"
sed -i '' 's/^\*\*Plan status\*\*: draft$/**Plan status**: complete/' "$r/specs/$f/plan.md"
assert_eq plan-review "$(step)" "plan complete: plan-review"
printf '## Plan Review\n### Round 1 (2026-11-26)\n**Verdict**: NO_GO\n' >> "$r/specs/$f/plan.md"
assert_eq plan-review "$(step)" "NO_GO: plan-review"
printf '# Tasks\n- [ ] T001 [US1] a in src/main/java/A.java\n- [ ] T002 [US1] b in src/main/java/B.java\n' > "$r/specs/$f/tasks.md"
assert_eq plan-review "$(step)" "gate prerequisite: tasks.md without plan-review GO still goes to plan-review"
printf '### Round 2 (2026-11-26)\n**Verdict**: GO (developer decision)\n' >> "$r/specs/$f/plan.md"
assert_eq analyze "$(step)" "GO (developer decision) and tasks.md: analyze"

# --- analyze (docs commit) -------------------------------------------------------------------------
{ printf '# Tasks\n**Analyzed**: 2026-11-26 (baseline 0 failing; build maven; tests present; setup none)\n'; tail -n +2 "$r/specs/$f/tasks.md"; } > "$r/tasks.tmp" && mv "$r/tasks.tmp" "$r/specs/$f/tasks.md"
assert_eq analyze "$(step)" "Analyzed line not yet committed: analyze"
(cd "$r" && "$L" append $f branch ok "$base" $f)
commit "docs($f): spec, plan and tasks"
assert_eq implement "$(step)" "docs commit: implement"
assert_eq "$base" "$(kv "$(ks next)" BASE)" "base from the ledger"

# --- implement, drift --------------------------------------------------------------------------------
sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"; mkdir -p "$r/src/main/java"; echo a > "$r/src/main/java/A.java"
commit "feat(pay): T001 add a"
assert_eq implement "$(step)" "one of two tasks done: implement"
sed -i '' 's/^- \[ \] T002 /- [X] T002 /' "$r/specs/$f/tasks.md"; commit "chore: tick without the ID"
out=$(ks next); rc=$?
assert_eq 4 "$rc" "a [X] task without a matching commit is drift"
assert_contains "$out" "T002" "drift names the task"
echo b > "$r/src/main/java/B.java"; commit "feat(pay): T002 add b"
assert_eq mutate "$(step)" "all tasks committed: mutate"

# --- mutate, review, finish ------------------------------------------------------------------------------
printf '# Test Quality: x\n**Result**: resolved\n' > "$r/specs/$f/test-quality.md"
assert_eq mutate "$(step)" "test-quality.md not committed yet: mutate"
commit "test($f): test-quality"
assert_eq review "$(step)" "test-quality committed: review"
(cd "$r" && "$L" append $f review ok "$(git -C "$r" rev-parse HEAD)" REV-1)
assert_eq review "$(step)" "a unit closure is not review evidence"
(cd "$r" && "$L" append $f review done "$(git -C "$r" rev-parse HEAD)")
assert_eq finish "$(step)" "review done at HEAD: finish"
echo c > "$r/src/main/java/A.java"; commit "fix(pay): FIN-1 make verify pass"
assert_eq finish "$(step)" "FIN commits after review done: still finish"
echo d > "$r/src/main/java/A.java"; commit "fix: something without an ID"
assert_eq review "$(step)" "a commit without a FIN ID after review done: review re-runs"
(cd "$r" && "$L" append $f review done "$(git -C "$r" rev-parse HEAD)")
sed -i '' 's/^\*\*Status\*\*: Approved (Gate 1, 2026-11-26)$/**Status**: Implemented (2026-11-27)/' "$r/specs/$f/spec.md"
assert_eq finish "$(step)" "Implemented not committed yet: finish"
commit "feat($f): finish"
assert_eq done "$(step)" "Implemented in HEAD: done"

# --- require, facts -------------------------------------------------------------------------------------
assert_exit 0 "require finish when done" -- sh -c "cd '$r' && . '$ENVSH' && '$S' require finish"
r2=$(mk_repo); git -C "$r2" commit -q --allow-empty -m init; mkdir -p "$r2/.specify/memory" "$r2/specs/$f"
echo "# C" > "$r2/.specify/memory/constitution.md"
printf '**Status**: Draft\n**Base**: %s (main)\n' "$(git -C "$r2" rev-parse HEAD)" > "$r2/specs/$f/spec.md"
r_save=$r; r=$r2
assert_exit 0 "require clarify on an unapproved spec" -- sh -c "cd '$r' && . '$ENVSH' && '$S' require clarify --feature $f"
out=$(ks require plan --feature $f); rc=$?
assert_eq 3 "$rc" "require plan before Gate 1 exits 3"
assert_contains "$out" "MISSING=" "and names what is missing"
out=$(ks facts --feature $f)
assert_contains "$out" "constitution done" "facts: constitution done"
assert_contains "$out" "clarify todo" "facts: clarify todo"
# light path skips plan-review
sed -i '' 's/^\*\*Status\*\*: Draft$/**Status**: Approved (Gate 1, 2026-11-26)/' "$r/specs/$f/spec.md"; printf '**Path**: light (accepted at Gate 1)\n' >> "$r/specs/$f/spec.md"
printf '**Plan status**: complete\n## Design Decision\n**Chosen**: single design (light path)\n' > "$r/specs/$f/plan.md"
assert_eq tasks "$(step --feature $f)" "light path: plan complete goes straight to tasks"
assert_contains "$(ks facts --feature $f)" "plan-review skipped" "facts: plan-review skipped on the light path"
# drift: a design decision without Gate 1
sed -i '' 's/^\*\*Status\*\*: Approved (Gate 1, 2026-11-26)$/**Status**: Draft/' "$r/specs/$f/spec.md"
out=$(ks next --feature $f); rc=$?
assert_eq 4 "$rc" "a design decision without Gate 1 is drift"
r=$r_save
t_summary
