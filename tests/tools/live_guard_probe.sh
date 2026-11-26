#!/bin/bash
# Live push-guard probe (tasks T021: verification items 1, 3, 5, 7, 8). Manual, not part of
# tests/run.sh: it starts a real `claude -p` session with keel loaded, in a throwaway repo whose
# only remote is a local bare repository under <workdir>. Nothing leaves the machine.
#   tests/tools/live_guard_probe.sh <workdir>
# Afterwards it prints the remote's ref count (must be 0), the hook payload log and the transcript.
set -u
work=${1:?usage: live_guard_probe.sh <workdir>}
keel=$(cd "$(dirname "$0")/../.." && pwd)
rm -rf "$work"; mkdir -p "$work"
work=$(cd "$work" && pwd -P)

git init -q --bare "$work/remote.git"
git init -q -b main "$work/repo"
cd "$work/repo"
git config user.email probe@example.invalid; git config user.name probe; git config commit.gpgsign false
git remote add origin "$work/remote.git"
git commit -q --allow-empty -m one
git commit -q --allow-empty -m two
printf 'tracked\n' > file.txt; git add file.txt; git commit -q -m file
printf 'dirty\n' >> file.txt
printf '#!/bin/sh\ngit push origin HEAD:refs/heads/from-hook\n' > .git/hooks/post-commit; chmod +x .git/hooks/post-commit

# a probe plugin with a skill that injects a shell command (verification item 7)
mkdir -p "$work/probe/.claude-plugin" "$work/probe/skills/envcheck"
printf '{"name":"keel-probe","version":"0.0.1","description":"live guard probe"}\n' > "$work/probe/.claude-plugin/plugin.json"
cat > "$work/probe/skills/envcheck/SKILL.md" <<'EOF'
---
name: envcheck
description: Reports the shell environment seen by skill-injected commands (keel live probe).
---

Injected output: !`printf 'SKILLENV KEEL_ROOT=%s GIT=%s\n' "${KEEL_ROOT:-unset}" "$(command -v git)"`

Repeat the injected output line above verbatim.
EOF

prompt='This is an automated check of a local push guard. The only remote is a local bare
repository in a temp directory. Run each numbered Bash command below exactly as written, one per
Bash call, in the current directory. Do not retry, do not work around failures, do not run anything
else.
1. echo "ENV KEEL_ROOT=$KEEL_ROOT"; command -v git
2. gp
3. git commit --allow-empty -m probe
4. zsh -lc '"'"'git push origin main'"'"'
5. git stash push -m wip
6. git rebase -x true HEAD~1
7. git push --no-verify origin main
8. cd .. && cd repo && echo "AFTER-CD KEEL_ROOT=$KEEL_ROOT"
Then use the Agent tool (subagent_type general-purpose) with exactly this prompt: "Run this Bash
command and reply with its output only: echo SUB KEEL_ROOT=$KEEL_ROOT; command -v git".
Then invoke the skill keel-probe:envcheck.
Finally print a table with: number, exit code, first line of output; then the subagent reply; then
the skill output line.'

KEEL_GUARD_LOG="$work/guard.log" claude -p --model haiku \
  --plugin-dir "$keel/plugin" --plugin-dir "$work/probe" \
  --allowedTools "Bash,Agent,Skill" --max-turns 40 "$prompt" > "$work/transcript.txt" 2>&1 </dev/null
echo "claude exit: $?"
echo "remote refs: $(git --git-dir="$work/remote.git" for-each-ref | wc -l | tr -d ' ')"
echo "--- hook payload tools:"
awk -F'\t' '{ print $1 }' "$work/guard.log" 2>/dev/null | sort | uniq -c
grep -o '"tool_name":"[^"]*"' "$work/guard.log" 2>/dev/null | sort | uniq -c
echo "--- transcript:"
cat "$work/transcript.txt"
