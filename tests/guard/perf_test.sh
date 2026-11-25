#!/bin/bash
# Push guard performance (contracts/push-guard.md §Performance): layer B p95 < 50 ms over the allow
# corpus; layer A adds < 15 ms per git call when KEEL_REAL_GIT is resolved (as session-env.sh does).
# Thresholds can be raised on a loaded machine: KEEL_PERF_HOOK_MS, KEEL_PERF_SHIM_MS.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
HOOK="$KEEL_PLUGIN_ROOT/hooks/guard-push.sh"
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"
jdk=$(t_tmp); mkdir -p "$jdk/bin"; export JAVA_HOME="$jdk"
hook_max=${KEEL_PERF_HOOK_MS:-50}
shim_max=${KEEL_PERF_SHIM_MS:-15}
TIMEFORMAT=%3R

json_str() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; printf '"%s"' "$s"; }
ms() { awk -v s="$1" 'BEGIN { printf "%d", s * 1000 + 0.5 }'; }

# collect allow-corpus commands
cmds=() hdr= body=
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    '### '*) [ -n "$hdr" ] && cmds+=("${body%$'\n'}"); hdr=$line; body= ;;
    *) body="$body$line"$'\n' ;;
  esac
done < "$KEEL_TESTS_ROOT/guard/hook/cases/allow.txt"
[ -n "$hdr" ] && cmds+=("${body%$'\n'}")

times=()
for round in 1 2 3; do
  for c in "${cmds[@]}"; do
    p=$(printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":"%s"}' "$(json_str "$c")" "$KEEL_REPO_ROOT")
    t=$( { time printf '%s' "$p" | /bin/bash "$HOOK" >/dev/null 2>&1; } 2>&1 )
    times+=("$(ms "$t")")
  done
done
p95=$(printf '%s\n' "${times[@]}" | sort -n | awk '{ a[NR] = $1 } END { i = int(NR * 0.95 + 0.999); if (i > NR) i = NR; print a[i] }')
printf 'layer B: %d runs, p95 %d ms (limit %d)\n' "${#times[@]}" "$p95" "$hook_max"
assert_eq yes "$([ "$p95" -lt "$hook_max" ] && echo yes)" "layer B p95 ${p95} ms < ${hook_max} ms"

# layer A overhead per git call
real=$(command -v git)
if [ "$real" = /usr/bin/git ] && command -v xcrun >/dev/null 2>&1; then real=$(xcrun --find git); fi
export KEEL_REAL_GIT=$real
unset KEEL_SHIM_DEPTH
cd "$KEEL_REPO_ROOT"
t_shim=$( { time for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do "$KEEL_PLUGIN_ROOT/shims/git" rev-parse HEAD >/dev/null; done; } 2>&1 )
t_real=$( { time for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do "$real" rev-parse HEAD >/dev/null; done; } 2>&1 )
over=$(( ( $(ms "$t_shim") - $(ms "$t_real") ) / 20 ))
printf 'layer A: shim overhead %d ms per git call (limit %d)\n' "$over" "$shim_max"
assert_eq yes "$([ "$over" -lt "$shim_max" ] && echo yes)" "shim overhead ${over} ms < ${shim_max} ms"
t_summary
