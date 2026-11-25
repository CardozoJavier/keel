#!/bin/bash
# keel-put: store agent output from stdin under the run scratch (contracts/run-state.md).
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
P="$KEEL_PLUGIN_ROOT/bin/keel-put"
r=$(mk_repo); git -C "$r" commit -q --allow-empty -m init
rp=$(cd "$r" && pwd -P)
out=$(cd "$r" && "$P" 001-x reports/T001.md <<'DOC'
# Report: T001; status && done $(not run) `nor this`
line two
DOC
)
assert_eq "PATH=$rp/.git/keel/001-x/reports/T001.md" "$out" "prints the stored path"
assert_eq "$(printf '# Report: T001; status && done $(not run) `nor this`\nline two')" "$(cat "$rp/.git/keel/001-x/reports/T001.md")" "content stored verbatim, metacharacters untouched"
assert_exit 1 "rejects .." -- sh -c "cd '$r' && echo x | '$P' 001-x ../escape.md"
assert_exit 1 "rejects absolute paths" -- sh -c "cd '$r' && echo x | '$P' 001-x /tmp/escape.md"
assert_exit 1 "rejects an empty path" -- sh -c "cd '$r' && echo x | '$P' 001-x ''"
assert_exit 1 "rejects a bad feature name" -- sh -c "cd '$r' && echo x | '$P' '../x' a.md"
assert_eq "no" "$([ -e "$rp/.git/escape.md" ] && echo yes || echo no)" "nothing written outside scratch"
printf 'v2\n' | (cd "$r" && "$P" 001-x reports/T001.md >/dev/null)
assert_eq "v2" "$(cat "$rp/.git/keel/001-x/reports/T001.md")" "overwrites an existing file"
t_summary
