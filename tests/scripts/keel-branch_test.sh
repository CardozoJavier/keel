#!/bin/bash
# keel-branch (contracts/run-state.md): local-only feature branching with the ensure-scope
# exemptions, unborn HEAD, stacking, numbering and default-branch detection. Never touches the network.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
B="$KEEL_PLUGIN_ROOT/bin/keel-branch"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# --- numbering -----------------------------------------------------------------------------
r=$(mk_repo); git -C "$r" commit -q --allow-empty -m init
assert_eq "NNN=001" "$(cd "$r" && "$B" next-number)" "first feature is 001"
mkdir -p "$r/specs/001-a"; git -C "$r" branch 002-b
assert_eq "NNN=003" "$(cd "$r" && "$B" next-number)" "next number covers spec dirs and local branches"
rm -rf "$r/specs"; git -C "$r" branch -D 002-b -q

# --- ensure on a clean default branch -------------------------------------------------------
head=$(git -C "$r" rev-parse HEAD)
out=$(cd "$r" && "$B" ensure 001-x); rc=$?
assert_eq 0 "$rc" "ensure on a clean tree succeeds"
assert_eq "001-x" "$(kv "$out" BRANCH)" "BRANCH"
assert_eq "$head" "$(kv "$out" BASE)" "BASE is HEAD of the default branch"
assert_eq yes "$(kv "$out" CREATED)" "CREATED=yes"
assert_eq no "$(kv "$out" STACKED)" "not stacked"
assert_eq "001-x" "$(git -C "$r" symbolic-ref --short HEAD)" "switched to the feature branch"
assert_contains "$(cd "$r" && "$L" last 001-x branch)" "$head" "ledger records the base"
out=$(cd "$r" && "$B" ensure 001-x)
assert_eq no "$(kv "$out" CREATED)" "ensure again is a no-op"
assert_eq "$head" "$(kv "$out" BASE)" "base is kept from the ledger"

# --- dirty tree and exemptions ----------------------------------------------------------------
echo t > "$r/tracked.txt"; git -C "$r" add tracked.txt; git -C "$r" commit -q -m t
echo dirty >> "$r/tracked.txt"
out=$(cd "$r" && "$B" ensure 001-x 2>&1); rc=$?
assert_eq 3 "$rc" "a modified tracked file halts"; assert_contains "$out" "MISSING=clean-tree" "reports clean-tree"
git -C "$r" checkout -q -- tracked.txt
echo u > "$r/untracked.txt"
assert_exit 3 "an untracked file halts" -- sh -c "cd '$r' && '$B' ensure 001-x"
rm "$r/untracked.txt"
mkdir -p "$r/.specify/memory" "$r/specs/001-x"
echo '{"feature_directory": "specs/001-x"}' > "$r/.specify/feature.json"
echo spec > "$r/specs/001-x/spec.md"
echo c > "$r/.specify/memory/constitution.md"
assert_exit 0 "on the feature branch: feature.json, specs/<f>/ and an untracked constitution are exempt" -- sh -c "cd '$r' && '$B' ensure 001-x"
mkdir -p "$r/specs/002-y"; echo s > "$r/specs/002-y/spec.md"
assert_exit 3 "another feature's uncommitted documents halt" -- sh -c "cd '$r' && '$B' ensure 001-x"
rm -rf "$r/specs/002-y"

# ledger exemption: on the default branch, files keel wrote for the feature
git -C "$r" switch -q main 2>/dev/null || true
r2=$(mk_repo); git -C "$r2" commit -q --allow-empty -m init
mkdir -p "$r2/specs/003-z"; echo s > "$r2/specs/003-z/spec.md"
assert_exit 3 "on the default branch, unledgered feature files halt" -- sh -c "cd '$r2' && '$B' ensure 003-z"
(cd "$r2" && "$L" append 003-z files done - specs/003-z/spec.md)
assert_exit 0 "files recorded in the ledger are exempt" -- sh -c "cd '$r2' && '$B' ensure 003-z"

# --- unborn HEAD ---------------------------------------------------------------------------------
u=$(mk_repo)
out=$(cd "$u" && "$B" ensure 001-new); rc=$?
assert_eq 0 "$rc" "ensure in an unborn repository"
assert_eq "refs/heads/001-new" "$(git -C "$u" symbolic-ref HEAD)" "unborn HEAD points at the feature branch"
assert_eq "4b825dc642cb6eb9a060e54bf8d69288fbee4904" "$(kv "$out" BASE)" "base is the empty tree"

# --- stacking and switching -----------------------------------------------------------------------
s=$(mk_repo); git -C "$s" commit -q --allow-empty -m init
(cd "$s" && "$B" ensure 001-a >/dev/null); git -C "$s" commit -q --allow-empty -m a
ahead=$(git -C "$s" rev-parse HEAD)
out=$(cd "$s" && "$B" ensure 002-b)
assert_eq "001-a" "$(kv "$out" STACKED)" "a feature started from another feature branch is stacked"
assert_eq "$ahead" "$(kv "$out" BASE)" "stacked base is the other feature's HEAD"
(cd "$s" && "$B" ensure 001-a >/dev/null)
assert_eq "001-a" "$(git -C "$s" symbolic-ref --short HEAD)" "ensure switches to an existing feature branch"

# --- default branch detection ---------------------------------------------------------------------
d=$(mk_repo); git -C "$d" commit -q --allow-empty -m init
assert_eq "DEFAULT=main" "$(cd "$d" && "$B" default)" "falls back to main"
git -C "$d" config init.defaultBranch trunk
assert_eq "DEFAULT=trunk" "$(cd "$d" && "$B" default)" "init.defaultBranch"
git -C "$d" update-ref refs/remotes/origin/develop HEAD
git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
assert_eq "DEFAULT=develop" "$(cd "$d" && "$B" default)" "local origin/HEAD wins"

# --- no network ---------------------------------------------------------------------------------
n=$(mk_repo); git -C "$n" commit -q --allow-empty -m init
git -C "$n" remote add origin ssh://git@example.invalid/x.git
trace=$(t_tmp)/trace
(cd "$n" && GIT_TRACE="$trace" GIT_SSH_COMMAND=false "$B" ensure 001-net >/dev/null)
assert_eq 0 "$?" "ensure with an unreachable remote succeeds"
assert_not_contains "$(cat "$trace")" "fetch" "no fetch"
assert_not_contains "$(cat "$trace")" "ls-remote" "no ls-remote"
assert_not_contains "$(cat "$trace")" "remote update" "no remote update"
t_summary
