#!/bin/bash
# plugin/hooks/hooks.json registers the push guard (contracts/push-guard.md): SessionStart writes
# the session environment; anchored PreToolUse matchers route shell tools, GitHub MCP tools and
# Codex to guard-push.sh; every guard entry fails closed with a 10 s timeout.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
. "$KEEL_PLUGIN_ROOT/lib/json.sh"
H="$KEEL_PLUGIN_ROOT/hooks/hooks.json"
j() { keel_json_get "$1" < "$H" 2>/dev/null; }
jr() { keel_json_get -r "$1" < "$H" 2>/dev/null; }

assert_eq yes "$([ -f "$H" ] && echo yes)" "hooks.json exists"
assert_eq '"${CLAUDE_PLUGIN_ROOT}/hooks/session-env.sh"' "$(j 'hooks.SessionStart[0].hooks[0].command')" "SessionStart runs session-env.sh"
assert_eq '^(Bash|Monitor|PowerShell)$' "$(j 'hooks.PreToolUse[0].matcher')" "shell tools matcher is anchored"
assert_eq '"${CLAUDE_PLUGIN_ROOT}/hooks/guard-push.sh"' "$(j 'hooks.PreToolUse[0].hooks[0].command')" "shell tools run guard-push.sh"
assert_eq '^mcp__.*github.*__.*$' "$(j 'hooks.PreToolUse[1].matcher')" "GitHub MCP matcher is anchored"
assert_eq '"${CLAUDE_PLUGIN_ROOT}/hooks/guard-push.sh" --github-mcp' "$(j 'hooks.PreToolUse[1].hooks[0].command')" "GitHub MCP mode"
assert_eq '^mcp__codex__codex$' "$(j 'hooks.PreToolUse[2].matcher')" "Codex matcher is anchored (codex-reply is not matched)"
assert_eq '"${CLAUDE_PLUGIN_ROOT}/hooks/guard-push.sh" --codex' "$(j 'hooks.PreToolUse[2].hooks[0].command')" "Codex mode"
for i in 0 1 2; do
  assert_eq "block" "$(j "hooks.PreToolUse[$i].hooks[0].onFailure")" "PreToolUse[$i] fails closed"
  assert_eq "10" "$(jr "hooks.PreToolUse[$i].hooks[0].timeout")" "PreToolUse[$i] has a 10 s timeout"
done
for f in session-env.sh guard-push.sh deny-push; do
  assert_eq yes "$([ -x "$KEEL_PLUGIN_ROOT/hooks/$f" ] && echo yes)" "hooks/$f is executable"
done
for f in git gh jj sl gt glab hub git-remote-keel-blocked-push; do
  assert_eq yes "$([ -x "$KEEL_PLUGIN_ROOT/shims/$f" ] && echo yes)" "shims/$f is executable"
done
if command -v claude >/dev/null 2>&1; then
  out=$(claude plugin validate --strict "$KEEL_PLUGIN_ROOT" 2>&1); rc=$?
  assert_eq 0 "$rc" "claude plugin validate --strict accepts the plugin (out: $(printf '%s' "$out" | tail -3))"
fi
t_summary
