#!/bin/bash
# Tests for plugin/lib/common.sh: root discovery, repo/scratch paths, portable helpers,
# unit-ID matching and the seeded temp-index tree builder (contracts/run-state.md).
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
LIB="$KEEL_PLUGIN_ROOT/lib/common.sh"

# --- root discovery ---------------------------------------------------------
d=$(t_tmp); mkdir -p "$d/elsewhere"
ln -s "$KEEL_PLUGIN_ROOT/lib/common.sh" "$d/elsewhere/link.sh"
out=$(env -u KEEL_ROOT /bin/bash -c ". '$d/elsewhere/link.sh'; keel_root")
assert_eq "$(cd "$KEEL_PLUGIN_ROOT" && pwd -P)" "$out" "keel_root resolves through a symlink when KEEL_ROOT is unset"
out=$(KEEL_ROOT="$d" /bin/bash -c ". '$LIB'; keel_root")
assert_eq "$d" "$out" "keel_root prefers \$KEEL_ROOT"

# --- repo root and scratch, from the root and from a module subdir ----------
r=$(mk_repo); rp=$(cd "$r" && pwd -P)
mkdir -p "$r/svc/src/main/java"
echo a > "$r/a.txt"; git -C "$r" add a.txt; git -C "$r" commit -q -m init
for wd in "$r" "$r/svc/src/main/java"; do
  out=$(in_subdir "$wd" /bin/bash -c ". '$LIB'; keel_repo_root")
  assert_eq "$rp" "$out" "keel_repo_root from $wd"
  out=$(in_subdir "$wd" /bin/bash -c ". '$LIB'; keel_scratch 001-x")
  assert_eq "$rp/.git/keel/001-x" "$out" "keel_scratch from $wd"
done
assert_eq "yes" "$([ -d "$r/.git/keel/001-x" ] && echo yes)" "keel_scratch creates the directory"
nr=$(t_tmp)
assert_exit 5 "keel_repo_root outside a repo exits 5" -- in_subdir "$nr" /bin/bash -c ". '$LIB'; keel_repo_root"

# --- emit / die -------------------------------------------------------------
assert_eq "STEP=done" "$(/bin/bash -c ". '$LIB'; keel_emit STEP done")" "keel_emit prints KEY=value"
out=$(/bin/bash -c ". '$LIB'; keel_die 3 'MISSING=x'" 2>&1); rc=$?
assert_eq 3 "$rc" "keel_die exits with the given code"
assert_contains "$out" "MISSING=x" "keel_die prints its message"

# --- portable reverse --------------------------------------------------------
assert_eq "3 2 1" "$(printf '1\n2\n3\n' | /bin/bash -c ". '$LIB'; keel_tac" | tr '\n' ' ' | sed 's/ $//')" "keel_tac reverses lines"

# --- unit-ID boundary matching ----------------------------------------------
m() { /bin/bash -c ". '$LIB'; keel_match_id '$1' '$2'" && echo y || echo n; }
assert_eq y "$(m T003 'feat(pay): T003 add refund limit')" "T003 matches in a subject"
assert_eq y "$(m T003 'T003: add')" "T003 matches at the start"
assert_eq n "$(m T003 'T0031 add')" "T003 does not match T0031"
assert_eq n "$(m T003 'xT003 add')" "T003 does not match xT003"
assert_eq y "$(m REV-1 'fix(core): REV-1 rename')" "REV-1 matches"
assert_eq n "$(m REV-1 'REV-12 rename')" "REV-1 does not match REV-12"
assert_eq n "$(m REV-1 'REV-1-b rename')" "REV-1 does not match REV-1-b"

# --- seeded temp-index tree ---------------------------------------------------
fixture_tracked_ignored "$r"
mkdir -p "$r/.specify"; echo '{"feature_directory": "specs/001-x"}' > "$r/.specify/feature.json"
echo new > "$r/svc/New.java"
echo changed > "$r/a.txt"
for wd in "$r" "$r/svc/src/main/java"; do
  t=$(in_subdir "$wd" /bin/bash -c ". '$LIB'; keel_worktree_tree HEAD '$r/.git/keel/001-x'")
  st=$(git -C "$r" diff-tree -r --name-status HEAD "$t")
  assert_contains "$st" "svc/New.java" "untracked new file is in the tree (cwd $wd)"
  assert_contains "$st" "a.txt" "modified tracked file is in the tree (cwd $wd)"
  assert_not_contains "$st" "feature.json" "feature.json is excluded (cwd $wd)"
  assert_not_contains "$st" "maven-wrapper.jar" "tracked-but-ignored file is not shown as deleted (cwd $wd)"
done
assert_eq "" "$(ls "$r/.git/keel/001-x" | grep '^idx' || true)" "temp index files are cleaned up"
assert_eq "M	a.txt" "$(git -C "$r" status --porcelain=v1 a.txt | sed 's/^ M /M	/')" "real index untouched"

# unborn repository: seed from the empty tree
u=$(mk_repo); echo x > "$u/x.txt"
t=$(in_subdir "$u" /bin/bash -c ". '$LIB'; keel_worktree_tree EMPTY '$u/.git/keel/001-y'")
assert_contains "$(git -C "$u" ls-tree --name-only "$t")" "x.txt" "unborn repo tree includes untracked files"
assert_eq "4b825dc642cb6eb9a060e54bf8d69288fbee4904" "$(in_subdir "$u" /bin/bash -c ". '$LIB'; keel_empty_tree")" "keel_empty_tree"

t_summary
