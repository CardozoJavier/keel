#!/bin/bash
# keel-evidence (contracts/run-state.md, data-model.md §7): records test runs with exit code and
# working-tree id, and checks the per-unit evidence rule (RED before GREEN, test before production
# change, final green), with the exceptions for non-behavior, refactor, gap and FIN fix units.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
E="$KEEL_PLUGIN_ROOT/bin/keel-evidence"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
f=001-x
new_repo() {
  r=$(mk_repo); mkdir -p "$r/src/main/java" "$r/src/test/java"
  echo 'class A {}' > "$r/src/main/java/A.java"; git -C "$r" add -A; git -C "$r" commit -q -m init
  base=$(git -C "$r" rev-parse HEAD)
}
ev() { (cd "$r" && "$E" "$@"); }
start() { (cd "$r" && "$L" append $f implement started "$base" "$1" "$2" src); }
miss() { (cd "$r" && "$E" check $f "$1" 2>&1 | sed -n 's/^MISSING=//p'); }

# --- a correct behavior task: test first (RED), then production change (GREEN) ---------------
new_repo; start T001 n/a
echo 'class ATest {}' > "$r/src/test/java/ATest.java"
out=$(ev run $f T001 red -- sh -c 'echo "1 failing"; exit 1'); rc=$?
assert_eq 1 "$rc" "run exits with the command's code"
assert_contains "$out" "1 failing" "run shows the command output"
echo 'class A { int x; }' > "$r/src/main/java/A.java"
ev run $f T001 green -- sh -c 'echo ok' >/dev/null
assert_exit 0 "check passes for test-first RED then GREEN" -- sh -c "cd '$r' && '$E' check $f T001"
idx="$r/.git/keel/$f/evidence/T001/index.tsv"
assert_eq 2 "$(wc -l < "$idx" | tr -d ' ')" "two evidence entries"
assert_contains "$(sed -n 1p "$idx")" "$(printf '01\tred\t1\t')" "index row: seq, phase, exit"
assert_eq yes "$([ -f "$r/.git/keel/$f/evidence/T001/01-red.log" ] && echo yes)" "log file per run"
ev run $f T001 refactor -- sh -c 'exit 0' >/dev/null
assert_exit 0 "a passing refactor run keeps the check green" -- sh -c "cd '$r' && '$E' check $f T001"

# --- failures -------------------------------------------------------------------------------------
new_repo; start T002 n/a
echo 'class A { int y; }' > "$r/src/main/java/A.java"
ev run $f T002 green -- true >/dev/null
assert_eq "red-before-green" "$(miss T002)" "GREEN without RED fails"

new_repo; start T003 n/a
echo 'class ATest {}' > "$r/src/test/java/ATest.java"
echo 'class A { int z; }' > "$r/src/main/java/A.java"
ev run $f T003 red -- false >/dev/null; ev run $f T003 green -- true >/dev/null
assert_eq "red-production-unchanged" "$(miss T003)" "RED after the production change fails"

new_repo; start T004 n/a
ev run $f T004 red -- false >/dev/null
echo 'class A { int w; }' > "$r/src/main/java/A.java"; ev run $f T004 green -- true >/dev/null
assert_eq "red-test-added" "$(miss T004)" "RED with no new or changed test fails"

new_repo; start T005 n/a
echo 'class ATest {}' > "$r/src/test/java/ATest.java"
ev run $f T005 red -- false >/dev/null; ev run $f T005 green -- true >/dev/null
echo 'class A { int v; }' > "$r/src/main/java/A.java"
assert_eq "green-production-change" "$(miss T005)" "GREEN before any production change fails"

new_repo; start T006 n/a
echo 'class ATest {}' > "$r/src/test/java/ATest.java"; ev run $f T006 red -- false >/dev/null
echo 'class A { int u; }' > "$r/src/main/java/A.java"; ev run $f T006 green -- true >/dev/null
ev run $f T006 refactor -- false >/dev/null
assert_eq "final-green" "$(miss T006)" "a failing last run fails"

# --- units with other rules -------------------------------------------------------------------------
new_repo; start T007 n/a
echo '# docs' > "$r/README.md"
assert_exit 0 "non-behavior task needs no RED" -- sh -c "cd '$r' && '$E' check $f T007"
new_repo; start REV-1 refactor
echo 'class A { /* renamed */ }' > "$r/src/main/java/A.java"; ev run $f REV-1 refactor -- true >/dev/null
assert_exit 0 "refactor unit needs no RED" -- sh -c "cd '$r' && '$E' check $f REV-1"
new_repo; start MUT-1 gap
echo 'class ATest { }' > "$r/src/test/java/ATest.java"; ev run $f MUT-1 green -- true >/dev/null
assert_exit 0 "mutation gap unit: evidence is the computed kill" -- sh -c "cd '$r' && '$E' check $f MUT-1"
new_repo; start FIN-1 fix
ev run $f FIN-1 red -- false >/dev/null   # an already-failing test, no test change
echo 'class A { int fixed; }' > "$r/src/main/java/A.java"; ev run $f FIN-1 green -- true >/dev/null
assert_exit 0 "FIN fix unit may use an already-failing test as RED" -- sh -c "cd '$r' && '$E' check $f FIN-1"
new_repo; start REV-2 fix
ev run $f REV-2 red -- false >/dev/null
echo 'class A { int r2; }' > "$r/src/main/java/A.java"; ev run $f REV-2 green -- true >/dev/null
assert_eq "red-test-added" "$(miss REV-2)" "REV fix unit still needs a new or changed test"

# --- guard environment for spawned commands; unknown unit --------------------------------------------
new_repo; start T008 n/a
out=$(cd "$r" && env -u GIT_CONFIG_COUNT KEEL_ROOT="$KEEL_PLUGIN_ROOT" "$E" run $f T008 green -- sh -c 'echo "count=$GIT_CONFIG_COUNT first=${PATH%%:*}"')
assert_contains "$out" "count=5" "spawned commands get the A0 entries"
assert_contains "$out" "first=$KEEL_PLUGIN_ROOT/shims" "spawned commands get the shims first on PATH"
assert_exit 3 "run for an unknown unit exits 3" -- sh -c "cd '$r' && '$E' run $f T099 red -- false"
t_summary
