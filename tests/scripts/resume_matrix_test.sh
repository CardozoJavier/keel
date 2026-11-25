#!/bin/bash
# Resume matrix (US4, SC-005; data-model.md §2 and §5): a feature built up to every interruption point,
# then what keel-state next / recover and keel-branch ensure report on resume. Exercises the existing
# scripts only: no step is redone, no gate is asked twice (next never goes back past evidence), and
# anything not attributable halts.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
S="$KEEL_PLUGIN_ROOT/bin/keel-state"; L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"; B="$KEEL_PLUGIN_ROOT/bin/keel-branch"
ENVSH="$KEEL_PLUGIN_ROOT/hooks/keel-env.sh"
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"
f=001-x
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
ks() { (cd "$r" && /bin/sh -c ". '$ENVSH'; exec '$S' \"\$@\"" keel-state "$@" 2>&1); }
kb() { (cd "$r" && /bin/sh -c ". '$ENVSH'; exec '$B' \"\$@\"" keel-branch "$@" 2>&1); }
led() { (cd "$r" && "$L" "$@" >/dev/null); }
step() { kv "$(ks next --feature "${1:-$f}")" STEP; }
commit() { git -C "$r" add -A -- . ':(exclude).specify/feature.json'; git -C "$r" commit -q -m "$1"; }
clean() { git -C "$r" status --porcelain --untracked-files=all | grep -v 'feature\.json$'; }

STAGES="empty constitution spec approved design plancomplete go analyzed t001 t002 tq reviewdone done"
build() { # build <stage>: a fresh repo with feature 001-x walked up to <stage>
  local want=$1 s
  r=$(mk_repo); mkdir -p "$r/src/main/java" "$r/src/test/java"
  echo 'class A {}' > "$r/src/main/java/A.java"; echo 'class B {}' > "$r/src/main/java/B.java"
  git -C "$r" add -A; git -C "$r" commit -q -m init; base=$(git -C "$r" rev-parse HEAD)
  for s in $STAGES; do
    case $s in
      empty) ;;
      constitution) mkdir -p "$r/.specify/memory"; echo '# Shop Constitution' > "$r/.specify/memory/constitution.md"; commit "docs: constitution"; base=$(git -C "$r" rev-parse HEAD) ;;
      spec) git -C "$r" switch -q -c $f; mkdir -p "$r/specs/$f"
            printf '# Feature Specification: X\n**Status**: Draft\n**Base**: %s (main)\n' "$base" > "$r/specs/$f/spec.md"
            led append $f files done - "specs/$f" ;;
      approved) printf '# Feature Specification: X\n**Status**: Approved (Gate 1, 2026-11-26)\n**Path**: full\n**Base**: %s (main)\n' "$base" > "$r/specs/$f/spec.md" ;;
      design) printf '# Plan\n**Plan status**: draft\n## Design Decision\n**Chosen**: pragmatic (Gate 2, 2026-11-26)\n' > "$r/specs/$f/plan.md" ;;
      plancomplete) sed -i '' 's/^\*\*Plan status\*\*: draft$/**Plan status**: complete/' "$r/specs/$f/plan.md" ;;
      go) printf '## Plan Review\n### Round 1 (2026-11-26)\n**Verdict**: GO\n' >> "$r/specs/$f/plan.md"
          printf '# Tasks\n- [ ] T001 [US1] a in src/main/java/A.java (test: src/test/java/ATest.java)\n- [ ] T002 [US1] b in src/main/java/B.java (test: src/test/java/BTest.java)\n' > "$r/specs/$f/tasks.md" ;;
      analyzed) { echo '# Tasks'; echo '**Analyzed**: 2026-11-26 (baseline 0 failing; build maven; tests present; setup none)'; tail -n +2 "$r/specs/$f/tasks.md"; } > "$r/t.tmp" && mv "$r/t.tmp" "$r/specs/$f/tasks.md"
                led append $f branch ok "$base" $f; commit "docs($f): spec, plan and tasks" ;;
      t001) led append $f implement started "$(git -C "$r" rev-parse HEAD)" T001 n/a src/main/java/A.java
            echo 'class A { int a; }' > "$r/src/main/java/A.java"; sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"; commit "feat(x): T001 a"
            led append $f implement ok "$(git -C "$r" rev-parse HEAD)" T001 ;;
      t002) led append $f implement started "$(git -C "$r" rev-parse HEAD)" T002 n/a src/main/java/B.java
            echo 'class B { int b; }' > "$r/src/main/java/B.java"; sed -i '' 's/^- \[ \] T002 /- [X] T002 /' "$r/specs/$f/tasks.md"; commit "feat(x): T002 b"
            led append $f implement ok "$(git -C "$r" rev-parse HEAD)" T002 ;;
      tq) printf '# Test Quality: x\n**Result**: resolved\n' > "$r/specs/$f/test-quality.md"; commit "test($f): test-quality" ;;
      reviewdone) led append $f review done "$(git -C "$r" rev-parse HEAD)" ;;
      done) sed -i '' 's/^\*\*Status\*\*: Approved (Gate 1, 2026-11-26)$/**Status**: Implemented (2026-11-27)/' "$r/specs/$f/spec.md"; commit "feat($f): finish" ;;
    esac
    [ "$s" = "$want" ] && return 0
  done
}
start() { led append $f "$1" started "$(git -C "$r" rev-parse HEAD)" "$2" "$3" "$4"; }
last_row() { (cd "$r" && "$L" last $f "$1" "$2"); }

# --- every §2 row --------------------------------------------------------------------------------------
expect="empty:constitution constitution:specify spec:clarify approved:plan design:plan plancomplete:plan-review go:analyze analyzed:implement t001:implement t002:mutate tq:review reviewdone:finish done:done"
for pair in $expect; do
  st=${pair%%:*}; want=${pair#*:}
  build "$st"
  got=$( [ "$st" = empty ] || [ "$st" = constitution ] && kv "$(ks next)" STEP || step)
  assert_eq "$want" "$got" "row: interrupted after '$st' resumes at $want"
done

# --- between Gate 2 and Plan status: complete: plan again, never Gate 1 -----------------------------------
build design
assert_eq plan "$(step)" "a recorded design with an incomplete plan resumes at plan (the skill skips Gate 2)"
assert_contains "$(ks facts --feature $f)" "clarify done" "Gate 1 is not asked again"

# --- mid-task: partial work is recovered to a patch and the unit restarts ----------------------------------
build analyzed; start implement T001 n/a src/main/java/A.java,src/test/java
echo 'class A { int partial; }' > "$r/src/main/java/A.java"; echo 'class ATest {}' > "$r/src/test/java/ATest.java"
out=$(ks recover --feature $f)
assert_eq T001 "$(kv "$out" RECOVERED)" "mid-task: the open unit is recovered"
assert_contains "$(cat "$(kv "$out" PATCH)")" "int partial" "the partial work is saved"
assert_eq "" "$(clean)" "and the tree is clean for the restart"
assert_eq implement "$(step)" "resume at implement, T001 still open"

# --- between [X] and the task commit ------------------------------------------------------------------------
build analyzed; start implement T001 n/a src/main/java/A.java
echo 'class A { int a; }' > "$r/src/main/java/A.java"; sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"
assert_eq T001 "$(kv "$(ks recover --feature $f)" RECOVERED)" "an uncommitted [X] is the unit's own: recovered"
assert_eq yes "$(grep -q '^- \[ \] T001 ' "$r/specs/$f/tasks.md" && echo yes)" "the [X] is undone with it"
assert_eq implement "$(step)" "resume at implement"

# --- between a task commit and its ledger ok ----------------------------------------------------------------
build analyzed; start implement T001 n/a src/main/java/A.java
echo 'class A { int a; }' > "$r/src/main/java/A.java"; sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"; commit "feat(x): T001 a"
assert_eq closed:T001 "$(kv "$(ks recover --feature $f)" RECOVERED)" "the committed unit is closed, not redone"
assert_eq ok "$(last_row implement T001 | cut -f3)" "with an ok row"
assert_eq implement "$(step)" "resume at implement for T002 only"

# --- in MUT-2 after MUT-1 was committed; and between them ----------------------------------------------------
build t002; start mutate MUT-1 gap src/test/java
echo 'class ATest { void t() {} }' > "$r/src/test/java/ATest.java"; commit "test(x): MUT-1 close gaps"
led append $f mutate ok "$(git -C "$r" rev-parse HEAD)" MUT-1
assert_eq none "$(kv "$(ks recover --feature $f)" RECOVERED)" "between MUT-1's commit and MUT-2: nothing to recover"
assert_eq mutate "$(step)" "resume at mutate"
start mutate MUT-2 gap src/test/java; echo 'class BTest {}' > "$r/src/test/java/BTest.java"
assert_eq MUT-2 "$(kv "$(ks recover --feature $f)" RECOVERED)" "in MUT-2: MUT-2 restarts, MUT-1 stays committed"
assert_contains "$(git -C "$r" log --format=%s)" "MUT-1" "MUT-1 is kept"

# --- after the REV-1 commit; a mixed-intent REV round ----------------------------------------------------------
build tq; start review REV-1 fix src/main/java/A.java,src/test/java
echo 'class A { int fixed; }' > "$r/src/main/java/A.java"; commit "fix(x): REV-1 findings"
led append $f review ok "$(git -C "$r" rev-parse HEAD)" REV-1
assert_eq review "$(step)" "after REV-1 without 'review done': review resumes (scoped re-review, no redo)"
start review REV-2 fix src/main/java/B.java,src/test/java
echo 'class B { int fix2; }' > "$r/src/main/java/B.java"; echo 'class BTest {}' > "$r/src/test/java/BTest.java"
assert_eq REV-2 "$(kv "$(ks recover --feature $f)" RECOVERED)" "a mixed-intent round (fix and refactor findings) is recovered"
assert_contains "$((cd "$r" && "$L" rows $f) | grep 'started' | grep 'REV-2')" "REV-2 fix" "and keeps intent=fix for the restart"

# --- in FIN-1; between the FINISH edit and its commit; between the commit and ok --------------------------------
build reviewdone; start finish FIN-1 fix src/main/java/A.java,src/test/java
echo 'class A { int fin; }' > "$r/src/main/java/A.java"
assert_eq FIN-1 "$(kv "$(ks recover --feature $f)" RECOVERED)" "in FIN-1: recovered"
assert_eq finish "$(step)" "resume at finish"
build reviewdone; start finish FINISH n/a "specs/$f/spec.md,specs/$f/test-quality.md"
sed -i '' 's/^\*\*Status\*\*: Approved (Gate 1, 2026-11-26)$/**Status**: Implemented (2026-11-27)/' "$r/specs/$f/spec.md"
assert_eq FINISH "$(kv "$(ks recover --feature $f)" RECOVERED)" "between the FINISH edit and its commit: the edit is redone"
assert_contains "$(cat "$r/specs/$f/spec.md")" "**Status**: Approved (Gate 1" "the uncommitted Status edit is restored"
assert_eq finish "$(step)" "resume at finish"
sed -i '' 's/^\*\*Status\*\*: Approved (Gate 1, 2026-11-26)$/**Status**: Implemented (2026-11-27)/' "$r/specs/$f/spec.md"; start finish FINISH n/a "specs/$f/spec.md"; commit "feat($f): finish"
assert_eq closed:FINISH "$(kv "$(ks recover --feature $f)" RECOVERED)" "between the finish commit and ok: closed"
assert_eq done "$(step)" "done"

# --- done after finish ---------------------------------------------------------------------------------------
build done
assert_eq none "$(kv "$(ks recover --feature $f)" RECOVERED)" "done: nothing to recover"
assert_eq done "$(step)" "and next is done (the run repeats only its report)"

# --- interleaved features with a stale feature.json ---------------------------------------------------------------
build approved
mkdir -p "$r/specs/002-y"; printf '# Feature Specification: Y\n**Status**: Draft\n**Base**: %s (main)\n' "$base" > "$r/specs/002-y/spec.md"
printf '{"feature_directory": "specs/002-y"}\n' > "$r/.specify/feature.json"
assert_eq plan "$(step $f)" "--feature 001-x wins over a stale feature.json"
assert_eq '{"feature_directory": "specs/001-x"}' "$(cat "$r/.specify/feature.json")" "and rewrites it"
assert_eq "$f" "$(kv "$(ks next)" FEATURE)" "a later resume without --feature stays on 001-x"

# --- resuming 001 from 002 with a started unit and a dirty tree: halt ----------------------------------------------
build analyzed; start implement T001 n/a src/main/java/A.java
git -C "$r" switch -q -c 002-y; echo 'class A { int other; }' > "$r/src/main/java/A.java"
assert_eq deferred "$(kv "$(ks recover --feature $f)" RECOVERED)" "on another branch, recovery is deferred"
out=$(kb ensure $f); rc=$?
assert_eq 3 "$rc" "switching back with a dirty tree halts"
assert_contains "$out" "MISSING=clean-tree" "naming the dirty tree"
assert_contains "$(cat "$r/src/main/java/A.java")" "int other" "and the developer's change is untouched"

# --- lost .git/keel before and after the docs commit -----------------------------------------------------------------
build go; rm -rf "$r/.git/keel"
assert_eq analyze "$(step)" "lost scratch before the docs commit: resume at analyze"
out=$(kb ensure $f); rc=$?
assert_eq 0 "$rc" "on the feature's own branch the uncommitted spec directory is still exempt (out: $out)"
build analyzed; rm -rf "$r/.git/keel"
assert_eq implement "$(step)" "lost scratch after the docs commit: resume at implement"
assert_eq "$base" "$(kv "$(ks next --feature $f)" BASE)" "BASE comes back from the spec's Base line"
t_summary
