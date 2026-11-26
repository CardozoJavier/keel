#!/bin/bash
# keel-diff (contracts/run-state.md): unit diffs tree-to-tree from a seeded temp index (no real
# index changes, feature.json excluded, tracked-but-ignored files intact), the whole-feature review
# diff, and behavior/non-behavior classification of a unit.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
D="$KEEL_PLUGIN_ROOT/bin/keel-diff"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
f=001-x
r=$(mk_repo); echo readme > "$r/README.md"; git -C "$r" add README.md; git -C "$r" commit -q -m init
fixture_tracked_ignored "$r"
base=$(git -C "$r" rev-parse HEAD)
(cd "$r" && "$L" append $f implement started "$base" T001 n/a src/main/java/A.java)

mkdir -p "$r/svc/src/main/java" "$r/.specify"
echo 'class A {}' > "$r/svc/src/main/java/A.java"
echo more >> "$r/README.md"
echo '{"feature_directory": "specs/001-x"}' > "$r/.specify/feature.json"
idx_before=$(git -C "$r" ls-files --stage | git hash-object --stdin)
for wd in "$r" "$r/svc"; do
  out=$(cd "$wd" && "$D" $f --unit T001); rc=$?
  assert_eq 0 "$rc" "unit diff from $wd"
  patch=$(kv "$out" PATCH)
  assert_contains "$(cat "$patch")" "svc/src/main/java/A.java" "untracked new file is in the unit diff ($wd)"
  assert_contains "$(cat "$patch")" "README.md" "modified file is in the unit diff ($wd)"
  assert_not_contains "$(cat "$patch")" "feature.json" "feature.json is excluded ($wd)"
  assert_not_contains "$(cat "$patch")" "maven-wrapper.jar" "tracked-but-ignored file is not deleted ($wd)"
done
assert_eq "$idx_before" "$(git -C "$r" ls-files --stage | git hash-object --stdin)" "the real index is untouched"
assert_eq "KIND=behavior" "$(cd "$r" && "$D" $f --kind T001)" "src/main change is behavior"

# a tests-and-docs-only unit is non-behavior; resources count as production
git -C "$r" add -A -- svc README.md; git -C "$r" commit -q -m T001
(cd "$r" && "$L" append $f implement ok "$(git -C "$r" rev-parse HEAD)" T001)
b2=$(git -C "$r" rev-parse HEAD)
(cd "$r" && "$L" append $f implement started "$b2" T002 n/a svc/src/test/java/ATest.java)
mkdir -p "$r/svc/src/test/java" "$r/docs"; echo t > "$r/svc/src/test/java/ATest.java"; echo d > "$r/docs/x.md"
assert_eq "KIND=non-behavior" "$(cd "$r" && "$D" $f --kind T002)" "test and docs changes are non-behavior"
mkdir -p "$r/svc/src/main/resources/db/migration"; echo 'create table t();' > "$r/svc/src/main/resources/db/migration/V1__t.sql"
assert_eq "KIND=behavior" "$(cd "$r" && "$D" $f --kind T002)" "src/main/resources (migrations) are production"

# a committed unit diffs BASE..its commit
out=$(cd "$r" && "$D" $f --unit T001)
assert_contains "$(cat "$(kv "$out" PATCH)")" "A.java" "committed unit diff shows its commit"
assert_not_contains "$(cat "$(kv "$out" PATCH)")" "ATest.java" "committed unit diff excludes later work"

# whole-feature review diff (base..HEAD) and the files list
(cd "$r" && "$L" append $f branch ok "$base" $f)
out=$(cd "$r" && "$D" $f --base); rc=$?
assert_eq 0 "$rc" "review diff"
assert_contains "$(cat "$(kv "$out" PATCH)")" "A.java" "review diff includes committed feature work"
assert_contains "$(cat "$(kv "$out" FILES)")" "svc/src/main/java/A.java" "files list"
assert_exit 3 "unknown unit exits 3" -- sh -c "cd '$r' && '$D' $f --unit T009"

# unborn-base feature: review diff against the empty tree
u=$(mk_repo); (cd "$u" && "$L" append 001-u branch ok 4b825dc642cb6eb9a060e54bf8d69288fbee4904 001-u)
echo x > "$u/x.txt"; git -C "$u" add x.txt; git -C "$u" commit -q -m x
out=$(cd "$u" && "$D" 001-u --base)
assert_contains "$(cat "$(kv "$out" PATCH)")" "x.txt" "review diff against the empty tree"
t_summary
