#!/bin/bash
# keel-ledger: append-only TSV run ledger under .git/keel/<feature>/ (contracts/run-state.md).
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
r=$(mk_repo); git -C "$r" commit -q --allow-empty -m init
f=001-x
in_r() { (cd "$r" && "$@"); }

assert_exit 0 "append a unit start" -- in_r "$L" append $f implement started abc123 T001 n/a src/A.java,src/ATest.java
assert_exit 0 "close the unit" -- in_r "$L" append $f implement ok def456 T001
assert_exit 0 "append a step completion" -- in_r "$L" append $f review done 789abc
led="$r/.git/keel/$f/ledger.tsv"
assert_eq 3 "$(wc -l < "$led" | tr -d ' ')" "three rows"
row=$(sed -n 1p "$led")
assert_contains "$row" "$(printf 'implement\tstarted\tabc123\tT001 n/a src/A.java,src/ATest.java')" "row fields are tab-separated"
case "$row" in 20[0-9][0-9]-[01][0-9]-[0-3][0-9]T*Z$'\t'*) _t_pass ;; *) _t_fail "row starts with a UTC ISO-8601 timestamp: $row" ;; esac

assert_contains "$(in_r "$L" last $f implement)" "$(printf 'ok\tdef456\tT001')" "last row for a step"
assert_contains "$(in_r "$L" last $f implement T001)" "ok" "last row for a step and unit"
assert_exit 3 "no row for an unknown step" -- in_r "$L" last $f mutate
assert_exit 3 "no row for an unknown unit" -- in_r "$L" last $f implement T002
assert_exit 1 "unknown status is rejected" -- in_r "$L" append $f implement finished x T001
assert_exit 1 "tabs in fields are rejected" -- in_r "$L" append $f implement ok "a$(printf '\t')b"
assert_exit 1 "missing arguments" -- in_r "$L" append $f
assert_eq 3 "$(wc -l < "$led" | tr -d ' ')" "rejected appends add nothing"
mkdir -p "$r/mod"; assert_exit 0 "works from a subdirectory" -- in_subdir "$r/mod" "$L" append $f analyze done x
assert_eq "$(cat "$led" | wc -l | tr -d ' ')" "4" "subdirectory append lands in the same ledger"
t_summary
