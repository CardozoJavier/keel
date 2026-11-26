#!/bin/bash
# T042: verification items 2, 6 and 11 (plan §Verification items), probed with real sessions.
#   2   `skills:` preload works in plugin agents
#   6   quickstart allow rules and skill `allowed-tools` apply inside plugin subagents, and
#       `Bash(keel-put:*)` matches a here-document whose body contains `;`, `&&` and `$(`
#   11  plugin agent `tools` accept Bash permission patterns such as `Bash(echo:*)`
# Usage: tests/tools/t042_probe.sh <probe-plugin-dir> <out-dir>
# The probe plugin (agents preloaded, pattern, bashy, bashy-preload, bashy-skill; skills
# preload-token, putter) is described in research.md R7.4. User settings are excluded
# (--setting-sources project) and the permission mode is pinned to default, so only the rules
# named per probe can allow a call. Non-interactive sessions deny anything else.
set -u
probe=${1:?probe plugin dir}; out=${2:?out dir}
keel="$(cd "$(dirname "$0")/../.." && pwd)/plugin"
mkdir -p "$out"
heredoc="keel-put 001-probe notes/p6.md <<'EOF'
a; b && c \$(d)
EOF"

run() { # run <name> <allowedTools> <prompt>
  local name=$1 allow=$2 prompt=$3 r="$out/$1"
  rm -rf "$r"; mkdir -p "$r/repo"
  git -C "$r/repo" init -q -b main
  git -C "$r/repo" -c user.email=p@example.invalid -c user.name=p commit -q --allow-empty -m init
  (cd "$r/repo" && claude -p --model haiku --plugin-dir "$keel" --plugin-dir "$probe" \
     --setting-sources project --permission-mode default --allowedTools "$allow" \
     --max-turns 12 --output-format stream-json --verbose "$prompt" > "$r/stream.jsonl" 2>&1 </dev/null)
}

dispatch() { # dispatch <agent> <agent prompt>
  printf 'Use the Agent tool exactly once, with subagent_type "kprobe:%s" and exactly this prompt:\n\n%s\n\nThen reply with the agent'"'"'s report verbatim. Do not run any tool yourself other than Agent.' "$1" "$2"
}

run p2 "Agent" "$(dispatch preloaded "What is the preload token? Reply with just the token, or NONE if you do not know it.")" &
run p11 "Agent,Bash" "$(dispatch pattern "Run these two commands, one at a time: \`echo PATTERN-OK\` and then \`ls /\`.")" &
run p6-neg "Agent" "$(dispatch bashy "$heredoc")" &
run p6-allow "Agent,Bash(keel-put:*)" "$(dispatch bashy "$heredoc")" &
run p6-preload "Agent" "$(dispatch bashy-preload "$heredoc")" &
run p6-skill "Agent,Skill" "$(dispatch bashy-skill "$heredoc")" &
wait

for p in p2 p11 p6-neg p6-allow p6-preload p6-skill; do
  printf '== %s\n' "$p"
  case $p in p6-*) [ -f "$out/$p/repo/.git/keel/001-probe/notes/p6.md" ] && echo "RAN: note stored" || echo "NOT RUN: no note" ;; esac
  python3 -I - "$out/$p/stream.jsonl" <<'PY'
import json, sys
for line in open(sys.argv[1], errors="replace"):
    try:
        o = json.loads(line)
    except ValueError:
        continue
    sub = o.get("parent_tool_use_id")
    m = o.get("message")
    content = m.get("content") if isinstance(m, dict) else None
    for b in content if isinstance(content, list) else []:
        t = b.get("type")
        if sub and t == "tool_use":
            print("  sub tool_use:", b.get("name"), json.dumps(b.get("input"))[:160])
        elif sub and t == "tool_result":
            c = b.get("content"); c = c if isinstance(c, str) else json.dumps(c)
            print("  sub result:", c[:240].replace("\n", " | "))
    if o.get("type") == "result":
        print("  final:", str(o.get("result"))[:300].replace("\n", " | "))
PY
done
