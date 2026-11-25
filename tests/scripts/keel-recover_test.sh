#!/bin/bash
# keel-state recover (data-model.md §5): close, abandon, defer or recover an interrupted work unit;
# restore only changes attributable to that unit, saving a patch first; otherwise halt untouched.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
S="$KEEL_PLUGIN_ROOT/bin/keel-state"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
E="$KEEL_PLUGIN_ROOT/bin/keel-evidence"
ENVSH="$KEEL_PLUGIN_ROOT/hooks/keel-env.sh"
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"
f=001-x
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
rec() { (cd "$r" && /bin/sh -c ". '$ENVSH'; exec '$S' recover --feature $f" 2>&1); }
setup() {
  r=$(mk_repo); mkdir -p "$r/specs/$f" "$r/src/main/java" "$r/src/test/java"
  printf -- '- [ ] T001 [US1] a in src/main/java/A.java\n- [ ] T002 [US1] b in src/main/java/B.java\n' > "$r/specs/$f/tasks.md"
  echo 'class A {}' > "$r/src/main/java/A.java"
  git -C "$r" add -A; git -C "$r" commit -q -m init
  git -C "$r" switch -q -c $f
  base=$(git -C "$r" rev-parse HEAD)
}
start() { (cd "$r" && "$L" append $f implement started "$base" "$1" n/a "$2"); }
last_status() { (cd "$r" && "$L" last $f implement "$1" | awk -F'\t' '{ print $3 }'); }

setup
assert_eq none "$(kv "$(rec)" RECOVERED)" "no open unit: nothing to do"

setup; start T001 src/main/java/A.java
assert_eq none "$(kv "$(rec)" RECOVERED)" "clean tree at BASE: none"
assert_eq abandoned "$(last_status T001)" "and the unit is marked abandoned"

setup; start T001 src/main/java/A.java
echo 'class A { int x; }' > "$r/src/main/java/A.java"; git -C "$r" commit -q -am "feat: T001 add x"
assert_eq "closed:T001" "$(kv "$(rec)" RECOVERED)" "clean tree past BASE with a matching commit: closed"
assert_eq ok "$(last_status T001)" "and closed with ok"

setup; start T001 src/main/java/A.java
git -C "$r" commit -q --allow-empty -m "unrelated"
assert_eq none "$(kv "$(rec)" RECOVERED)" "clean tree past BASE without a matching commit: none"
assert_eq abandoned "$(last_status T001)" "and abandoned"

# dirty tree at BASE, all changes attributable: named path, new file in a named dir, the unit's own [X]
setup; start T001 src/main/java/A.java,src/test/java
echo 'class A { int partial; }' > "$r/src/main/java/A.java"
echo 'class ATest {}' > "$r/src/test/java/ATest.java"; git -C "$r" add src/test/java/ATest.java   # staged new file
echo 'class Helper {}' > "$r/src/test/java/Helper.java"                                            # untracked new file
sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"
mkdir -p "$r/.specify"; echo '{"feature_directory": "specs/001-x"}' > "$r/.specify/feature.json"
out=$(rec); rc=$?
assert_eq 0 "$rc" "attributable changes are recovered"
assert_eq T001 "$(kv "$out" RECOVERED)" "RECOVERED=T001"
patch=$(kv "$out" PATCH)
assert_contains "$(cat "$patch")" "int partial" "the patch keeps the partial production change"
assert_contains "$(cat "$patch")" "Helper.java" "the patch keeps new files"
assert_eq "" "$(git -C "$r" status --porcelain --untracked-files=all | grep -v 'feature.json')" "the tree is clean afterwards (feature.json untouched)"
assert_eq "" "$(git -C "$r" ls-files src/test/java/ATest.java)" "a staged new file is removed from the index"
assert_eq yes "$([ -f "$r/.specify/feature.json" ] && echo yes)" "feature.json is kept"

# an unattributable change halts and touches nothing
setup; start T001 src/main/java/A.java
echo 'class A { int mine; }' > "$r/src/main/java/A.java"
echo 'developer notes' > "$r/NOTES.txt"
out=$(rec); rc=$?
assert_eq 3 "$rc" "an unattributable change halts"
assert_contains "$out" "HALT=unattributed-changes" "reports unattributed-changes"
assert_contains "$(cat "$r/src/main/java/A.java")" "int mine" "nothing is restored"
assert_eq yes "$([ -f "$r/NOTES.txt" ] && echo yes)" "nothing is deleted"

# a tasks.md change other than the unit's own [X] is unattributable
setup; start T001 src/main/java/A.java
sed -i '' 's/^- \[ \] T002 /- [X] T002 /' "$r/specs/$f/tasks.md"
out=$(rec); assert_eq 3 "$?" "another task's [X] is unattributable"

# paths recorded in the unit's evidence trees are attributable
setup; start T001 src/main/java/A.java
echo 'class Extra {}' > "$r/src/main/java/Extra.java"
(cd "$r" && /bin/sh -c ". '$ENVSH'; '$E' run $f T001 red -- false" >/dev/null 2>&1)
assert_eq T001 "$(kv "$(rec)" RECOVERED)" "a path in an evidence tree is attributable"

# halted units are never touched; off-branch defers; dirty past BASE halts
setup; start T001 src/main/java/A.java; (cd "$r" && "$L" append $f implement halted "$base" T001 "debug stop")
echo 'class A { int dev; }' > "$r/src/main/java/A.java"
assert_eq none "$(kv "$(rec)" RECOVERED)" "a halted unit is not recovered"
assert_contains "$(cat "$r/src/main/java/A.java")" "int dev" "and the developer's change stays"
setup; start T001 src/main/java/A.java; git -C "$r" switch -q main
assert_eq deferred "$(kv "$(rec)" RECOVERED)" "not on the feature branch: deferred"
setup; start T001 src/main/java/A.java; git -C "$r" commit -q --allow-empty -m other; echo x >> "$r/src/main/java/A.java"
out=$(rec); assert_eq 3 "$?" "dirty tree past BASE halts"
t_summary
