#!/bin/bash
# Tests for the git shim (push guard layer A, rules A1-A3 and A8; contracts/push-guard.md).
# Runs with a throwaway HOME and no system config, so a regression can never write user config.
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
SHIM="$KEEL_PLUGIN_ROOT/shims/git"
CASES="$KEEL_TESTS_ROOT/guard/shims/cases"
home=$(t_tmp)
export HOME="$home" XDG_CONFIG_HOME="$home/.config" GIT_CONFIG_NOSYSTEM=1 KEEL_TEST_ALIAS=push
unset KEEL_SHIM_DEPTH KEEL_REAL_GIT

remote=$(mk_bare_remote)
r=$(mk_repo)
git -C "$r" remote add origin "$remote"
git -C "$r" commit -q --allow-empty -m one
git -C "$r" commit -q --allow-empty -m two
git -C "$r" config alias.pp push
git -C "$r" config alias.p2 pp
git -C "$r" config alias.co checkout
refs() { git --git-dir="$remote" for-each-ref | wc -l | tr -d ' '; }

# --- deny corpus -------------------------------------------------------------
while IFS="$(printf '\t')" read -r rule args; do
  case "$rule" in ''|'#'*) continue ;; esac
  eval "set -- $args"
  out=$(cd "$r" && "$SHIM" "$@" 2>&1); rc=$?
  assert_eq 2 "$rc" "deny [$args] exits 2"
  assert_contains "$out" "keel: blocked publish ($rule)" "deny [$args] reports $rule"
done < "$CASES/git-deny.tsv"

# alias defined through GIT_CONFIG_COUNT env config
out=$(cd "$r" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ee GIT_CONFIG_VALUE_0=push "$SHIM" ee 2>&1); rc=$?
assert_eq 2 "$rc" "alias from GIT_CONFIG_COUNT is resolved and denied"
assert_eq 0 "$(refs)" "nothing reached the remote after the deny corpus"
assert_eq "" "$(git config --global --list 2>/dev/null)" "no global config was written"

# --- allow corpus ------------------------------------------------------------
echo change > "$r/file.txt"; git -C "$r" add file.txt; git -C "$r" commit -q -m file
echo dirty >> "$r/file.txt"
while IFS="$(printf '\t')" read -r note args; do
  case "$note" in ''|'#'*) continue ;; esac
  eval "set -- $args"
  out=$(cd "$r" && "$SHIM" "$@" 2>&1); rc=$?
  assert_not_contains "$out" "keel: blocked" "allow [$note] is not blocked"
  assert_eq 0 "$rc" "allow [$note] succeeds (out: $out)"
done < "$CASES/git-allow.tsv"

# exec passes argv and exit status through unchanged
assert_exit 129 "real git's exit status passes through" -- "$SHIM" --definitely-not-an-option

# --- shell aliases and functions (zsh, as in Claude Code's shell snapshot) ----
if command -v zsh >/dev/null 2>&1; then
  shims=$(dirname "$SHIM")
  for cmd in gp gpsup ggpush ggp; do
    out=$(cd "$r" && PATH="$shims:$PATH" zsh -f -c "source '$KEEL_TESTS_ROOT/fixtures/snapshot/aliases.zsh'; eval $cmd" 2>&1); rc=$?
    assert_contains "$out" "keel: blocked publish (A1)" "zsh $cmd is blocked"
  done
  assert_eq 0 "$(refs)" "nothing reached the remote through zsh aliases"
fi

t_summary
