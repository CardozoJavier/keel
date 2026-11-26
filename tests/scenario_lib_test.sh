#!/bin/bash
# Tests for the stream-json readers in tests/scenarios/lib.sh that the trials count with:
# Spec Kit use and reachability (SC-007) and the stdout of a given Bash call.
set -u
. "$(cd "$(dirname "$0")" && pwd)/scenarios/lib.sh"
d=$(t_tmp)

# --- scn_speckit_used / scn_speckit_reachable --------------------------------------------------
# mentions that are not Spec Kit use: a keel step named "specify", tool output and prose
cat > "$d/clean.jsonl" <<'JSON'
{"type":"system","subtype":"init","skills":["keel:run","keel:verify"],"slash_commands":["keel:run","clear"]}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"keel-state require specify --feature 001-x; echo specify"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"STEP=specify\nrun specify init to start"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will not run \"specify init\" or the speckit-analyze skill."}]}}
not json
JSON
assert_eq 0 "$(scn_speckit_used "$d/clean.jsonl")" "a keel step named specify, tool output and prose are not Spec Kit use"
assert_eq 0 "$(scn_speckit_reachable "$d/clean.jsonl")" "no speckit skill or command in the session's init"

cat > "$d/used.jsonl" <<'JSON'
{"type":"system","subtype":"init","skills":["keel:run","speckit-analyze"],"slash_commands":["speckit-analyze","speckit-plan"]}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Skill","input":{"skill":"speckit-analyze"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Skill","input":{"skill":"spec-kit:speckit-plan"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u3","name":"Bash","input":{"command":"specify init --here --ai claude"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u4","name":"Bash","input":{"command":"cd repo && specify check"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u5","name":"Bash","input":{"command":"uvx --from git+https://github.com/github/spec-kit.git specify init x"}}]}}
{"type":"assistant","parent_tool_use_id":"a1","message":{"content":[{"type":"tool_use","id":"u6","name":"Bash","input":{"command":"/usr/local/bin/specify version"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u7","name":"Skill","input":{"skill":"keel:specify"}}]}}
JSON
assert_eq 6 "$(scn_speckit_used "$d/used.jsonl")" "Skill and Bash invocations of Spec Kit, including a subagent's, are counted"
assert_eq 6 "$(scn_speckit_used "$d/clean.jsonl" "$d/used.jsonl")" "counts add up across sessions"
assert_eq 2 "$(scn_speckit_reachable "$d/clean.jsonl" "$d/used.jsonl")" "distinct speckit skills and commands offered in init"

# --- scn_bash_output: stdout of the last Bash call whose command matches -------------------------
cat > "$d/s1.jsonl" <<'JSON'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"v1","name":"Bash","input":{"command":"keel-verify run 001-x --label finish -- mvn verify"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"v1","content":"RESULT=fail\nNEW=1"}]}}
JSON
cat > "$d/s2.jsonl" <<'JSON'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"v2","name":"Bash","input":{"command":"keel-state require finish; keel-verify run 001-x --label finish -- mvn -q verify 2>&1"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"v2","content":[{"type":"text","text":"exit=0\nRESULT=pass\nNEW=0"}]}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"v3","name":"Bash","input":{"command":"keel-verify run 001-x --label T001 -- mvn verify"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"v3","content":"RESULT=fail"}]}}
JSON
out=$(scn_bash_output 'keel-verify run .*--label finish' "$d/s1.jsonl" "$d/s2.jsonl")
assert_contains "$out" "RESULT=pass" "the last matching call's output, across sessions in order"
assert_not_contains "$out" "RESULT=fail" "earlier and non-matching calls are not included"
assert_eq "" "$(scn_bash_output 'no such command' "$d/s1.jsonl" "$d/s2.jsonl")" "no matching call: empty"

# --- scn_put_writers: who ran each keel-put (the session itself, or an agent) ----------------
cat > "$d/put.jsonl" <<'JSON'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"Bash","input":{"command":"keel-put 001-x reports/T001.md <<'KEEL_EOF'\n# Report: T001\nKEEL_EOF"}}]}}
{"type":"assistant","parent_tool_use_id":"a1","message":{"content":[{"type":"tool_use","id":"p2","name":"Bash","input":{"command":"keel-put 001-x reviews/T001-r1.md <<'KEEL_EOF'\n**Verdict**: PASS\nKEEL_EOF"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p3","name":"Bash","input":{"command":"keel-verify run 001-x --label T001 -- mvn verify"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p4","name":"Bash","input":{"command":"cd repo && keel-put 001-x plan-review/round-1.md <<'EOF'\nx\nEOF"}}]}}
JSON
assert_eq "$(printf 'main\treports/T001.md\nagent\treviews/T001-r1.md\nmain\tplan-review/round-1.md')" "$(scn_put_writers "$d/put.jsonl")" "each keel-put with its writer and relpath, in order"
t_summary
