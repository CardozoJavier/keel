#!/bin/bash
# Tests for the thin shims jj, sl, gt, glab, hub (push guard layer A, rule A7).
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
S="$KEEL_PLUGIN_ROOT/shims"
w=$(t_tmp); mkdir -p "$w/real"
for t in jj sl gt glab hub; do
  printf '#!/bin/sh\necho "REAL%s $*"\n' "$t" > "$w/real/$t"; chmod +x "$w/real/$t"
done
unset KEEL_SHIM_DEPTH KEEL_REAL_JJ KEEL_REAL_SL KEEL_REAL_GT KEEL_REAL_GLAB KEEL_REAL_HUB
run() { local t=$1; shift; PATH="$S:$w/real:/usr/bin:/bin" "$S/$t" "$@" 2>&1; }

deny() { local t=$1; shift; out=$(run "$t" "$@"); rc=$?
  assert_eq 2 "$rc" "deny [$t $*]"; assert_contains "$out" "keel: blocked publish (A7)" "deny [$t $*] reports A7"
  assert_not_contains "$out" "REAL$t" "deny [$t $*] never reaches the real $t"; }
allow() { local t=$1; shift; out=$(run "$t" "$@"); rc=$?
  assert_eq 0 "$rc" "allow [$t $*]"; assert_eq "REAL$t $*" "$out" "allow [$t $*] passes argv unchanged"; }

deny jj git push
deny jj git push --all
deny jj --repository . git push
allow jj git fetch
allow jj log
deny sl push
deny sl pr submit
allow sl pull
allow sl log
deny gt submit
deny gt ss
deny gt sync
allow gt log
allow gt create -m x
deny glab mr create --fill
deny glab mr merge 3
allow glab mr list
allow glab mr view 3
deny hub push
deny hub pull-request -m x
allow hub status
allow hub browse

t_summary
