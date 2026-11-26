#!/bin/bash
# Layer B (plugin/hooks/guard-push.sh, shell mode). It catches:
# - invocations that bypass PATH;
# - attempts to weaken A0 or A;
# - literal publish commands;
# - recursive literal payloads;
# - forge HTTP writes;
# - inline interpreter payloads.
# See contracts/push-guard.md. Cases are in tests/guard/hook/cases/{deny,allow}.txt.
# The hook only parses these commands; nothing in the corpus is ever executed.
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
HOOK="$KEEL_PLUGIN_ROOT/hooks/guard-push.sh"
CASES="$KEEL_TESTS_ROOT/guard/hook/cases"
jdk=$(t_tmp); mkdir -p "$jdk/bin"; export JAVA_HOME="$jdk"   # a JDK dir without git/gh
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"

json_str() { # JSON-encode a string
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
  printf '"%s"' "$s"
}
payload() { printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":%s,"description":"x"},"cwd":"%s"}' "${2:-Bash}" "$(json_str "$1")" "$PWD"; }
run_hook() { payload "$1" "${2:-Bash}" | /bin/bash "$HOOK" 2>&1; }

run_cases() { # <file> <mode>
  local file=$1 mode=$2 hdr= body= line
  flush() {
    [ -n "$hdr" ] || return 0
    body=${body%$'\n'}
    out=$(run_hook "$body"); rc=$?
    if [ "$mode" = deny ]; then
      rule=${hdr%% *}
      assert_eq 2 "$rc" "deny [$hdr] exits 2"
      assert_contains "$out" "keel: blocked publish ($rule" "deny [$hdr] reports $rule"
    else
      assert_eq 0 "$rc" "allow [$hdr] exits 0 (out: $out)"
    fi
  }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '### '*) flush; hdr=${line#\#\#\# }; body= ;;
      *) body="$body$line"$'\n' ;;
    esac
  done < "$file"
  flush
}
run_cases "$CASES/deny.txt" deny
run_cases "$CASES/allow.txt" allow

# PowerShell and Monitor use the same shell rules; Monitor without a command (ws mode) passes
out=$(run_hook "git push" PowerShell); assert_eq 2 "$?" "PowerShell publish is denied"
out=$(run_hook "git push" Monitor); assert_eq 2 "$?" "Monitor publish is denied"
out=$(printf '{"tool_name":"Monitor","tool_input":{"url":"ws://x"},"cwd":"/"}' | /bin/bash "$HOOK" 2>&1)
assert_eq 0 "$?" "Monitor in ws mode (no command) passes"

# fail closed (F1/F2)
out=$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"' | /bin/bash "$HOOK" 2>&1); rc=$?
assert_eq 2 "$rc" "malformed JSON is denied"; assert_contains "$out" "(F1)" "malformed JSON reports F1"
out=$(printf '' | /bin/bash "$HOOK" 2>&1); assert_eq 2 "$?" "empty stdin is denied"
out=$(printf '{"tool_name":"Bash","tool_input":{}}' | /bin/bash "$HOOK" 2>&1); assert_eq 2 "$?" "Bash without a command is denied"
nested="echo deep"; for i in 1 2 3 4 5 6 7; do nested="bash -c $(printf '%q' "$nested")"; done
out=$(run_hook "$nested"); assert_eq 2 "$?" "payload nesting beyond the limit fails closed"

# opt-in payload log for empirical checks
lg="$jdk/guard.log"
out=$(payload "git status" | KEEL_GUARD_LOG="$lg" /bin/bash "$HOOK" 2>&1)
assert_contains "$(cat "$lg" 2>/dev/null)" '"tool_name":"Bash"' "KEEL_GUARD_LOG records the payload"

t_summary
