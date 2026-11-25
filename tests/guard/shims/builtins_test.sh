#!/bin/bash
# The git shim's embedded builtin list must match the installed git (git --list-cmds=main).
# Drift matters: a word listed as builtin but unknown to this git could be a user alias that the
# shim would then skip resolving. Regenerate with tests/tools/gen-git-builtins.sh.
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
LIST="$KEEL_PLUGIN_ROOT/lib/git-builtins.sh"

assert_eq yes "$([ -f "$LIST" ] && echo yes)" "git-builtins.sh exists"
want=$(git --list-cmds=main | LC_ALL=C sort -u)
have=$( . "$LIST" 2>/dev/null; printf '%s\n' $KEEL_GIT_BUILTINS | LC_ALL=C sort -u)
assert_eq "$want" "$have" "embedded list matches git $(git --version | awk '{print $3}') (regenerate: tests/tools/gen-git-builtins.sh)"
assert_contains "$have" "push" "push is a builtin (so it is never alias-resolved)"
assert_contains "$(head -1 "$LIST" 2>/dev/null)" "# generated from git" "header names the git version"
t_summary
