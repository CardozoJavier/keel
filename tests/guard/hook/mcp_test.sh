#!/bin/bash
# Layer B non-shell modes (contracts/push-guard.md): GitHub MCP tools default-deny except reads
# and named non-publishing writes; Codex agent runs denied when they could reach the network.
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
HOOK="$KEEL_PLUGIN_ROOT/hooks/guard-push.sh"
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"
cx=$(t_tmp); export CODEX_HOME="$cx"

gh_mcp() { printf '{"tool_name":"%s","tool_input":{"owner":"o","repo":"r"},"cwd":"/"}' "$1" | /bin/bash "$HOOK" --github-mcp 2>&1; }
for t in get_pull_request list_pull_requests search_code get_file_contents add_issue_comment create_issue update_issue \
         add_comment_to_pending_review create_pending_pull_request_review submit_pending_pull_request_review request_copilot_review; do
  out=$(gh_mcp "mcp__plugin_github_github__$t"); assert_eq 0 "$?" "GitHub MCP $t is allowed (out: $out)"
done
for t in create_pull_request merge_pull_request push_files create_or_update_file update_pull_request_branch create_branch delete_file create_repository fork_repository; do
  out=$(gh_mcp "mcp__plugin_github_github__$t"); rc=$?
  assert_eq 2 "$rc" "GitHub MCP $t is denied"; assert_contains "$out" "keel: blocked publish (T1)" "GitHub MCP $t reports T1"
done
out=$(gh_mcp "mcp__github__create_pull_request"); assert_eq 2 "$?" "other GitHub MCP server names are covered"

codex() { printf '{"tool_name":"mcp__codex__codex","tool_input":%s,"cwd":"/"}' "$1" | /bin/bash "$HOOK" --codex 2>&1; }
out=$(codex '{"prompt":"x","sandbox":"read-only"}'); assert_eq 0 "$?" "codex read-only is allowed"
out=$(codex '{"prompt":"x","sandbox":"workspace-write"}'); assert_eq 0 "$?" "codex workspace-write is allowed"
out=$(codex '{"prompt":"x","sandbox":"danger-full-access"}'); rc=$?
assert_eq 2 "$rc" "codex danger-full-access is denied"; assert_contains "$out" "(T2)" "codex reports T2"
out=$(codex '{"prompt":"x","sandbox":"workspace-write","config":{"sandbox_mode":"danger-full-access"}}'); assert_eq 2 "$?" "config sandbox_mode override is denied"
out=$(codex '{"prompt":"x","sandbox":"workspace-write","config":{"sandbox_workspace_write":{"network_access":true}}}'); assert_eq 2 "$?" "config enabling network is denied"
out=$(codex '{"prompt":"x"}'); assert_eq 0 "$?" "no sandbox and no config.toml: codex defaults apply"
printf 'sandbox_mode = "danger-full-access"\n' > "$cx/config.toml"
out=$(codex '{"prompt":"x"}'); assert_eq 2 "$?" "no sandbox, config.toml danger-full-access is denied"
printf 'sandbox_mode = "workspace-write"\n[sandbox_workspace_write]\nnetwork_access = true\n' > "$cx/config.toml"
out=$(codex '{"prompt":"x"}'); assert_eq 2 "$?" "no sandbox, config.toml network_access is denied"
printf 'sandbox_mode = "read-only"\n' > "$cx/config.toml"
out=$(codex '{"prompt":"x"}'); assert_eq 0 "$?" "no sandbox, config.toml read-only is allowed"
chmod 000 "$cx/config.toml"
out=$(codex '{"prompt":"x"}'); assert_eq 2 "$?" "unreadable config.toml is denied"
chmod 600 "$cx/config.toml"
out=$(printf '{"tool_name":"mcp__codex__codex","tool_input":' | /bin/bash "$HOOK" --codex 2>&1); assert_eq 2 "$?" "malformed codex payload is denied"

t_summary
