#!/bin/bash
# T080 trial (non-behavior): the full path, end to end, in a fresh sample repo. A plain-language
# description goes through Gate 1, Gate 2, plan review, tasks, analyze, implement, mutate, review and
# finish, using real `claude -p --plugin-dir plugin` sessions with --continue for the gates.
# superpowers and feature-dev are disabled (SC-007). Afterwards, Spec Kit's own prerequisite script and
# /speckit-analyze read the result from a copy with keel's own Spec Kit install (SC-006); host
# repositories don't keep Spec Kit's scaffolding.
# Usage: tests/trials/full_path_trial.sh <out-dir> [<speckit-host-repo, default: this keel checkout>]
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/scenarios/lib.sh"
out=${1:?out dir}; skhost=${2:-$KEEL_REPO_ROOT}; mkdir -p "$out"
r=$(scn_sample); start=$(date +%s)
[ -z "$(ls -d "$r"/.claude/skills/speckit-* 2>/dev/null)" ] || { echo "speckit skills present in the trial repo" >&2; exit 1; }
prompt='/keel:run Prices can be discounted by a whole-number percentage from 0 to 100.

Clarification answers, so you do not need to ask anything:
- Intent and why: marketing runs percentage promotions and enters final prices by hand today.
- Goals: Price.discounted(percent) returns the discounted Price, rounding half up to the cent.
- Non-goals: stacking discounts; currencies.
- Anti-goals: a discount that ever produces a negative price, or a percentage outside 0..100 that is silently accepted.
- Missing requirements: none.'
s1=$(scn_claude "$r" 80 "$prompt" --output-format stream-json --verbose)
s2=$(scn_continue "$r" 120 "I approve the spec. Use the full path." --output-format stream-json --verbose)
s3=$(scn_continue "$r" 400 "Go with the pragmatic balance design." --output-format stream-json --verbose)
f=$(basename "$(dirname "$(ls "$r"/specs/001-*/spec.md | head -1)")")
resumes=0
for extra in 1 2; do
  [ "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" = done ] && break
  resumes=$((resumes + 1)); s4=$(scn_claude "$r" 400 "/keel:run" --output-format stream-json --verbose)
  cp "$s4" "$out/session-resume-$extra.jsonl"
done
for i in 1 2 3; do eval "cp \"\$s$i\" \"$out/session$i.jsonl\""; done
end=$(date +%s)
state=$(scn_state "$r" --feature "$f"); step=$(printf '%s\n' "$state" | sed -n 's/^STEP=//p'); base=$(printf '%s\n' "$state" | sed -n 's/^BASE=//p')
g=$(git -C "$r" rev-parse --absolute-git-dir)
# sessions in run order (a glob would sort session-resume-* first)
all=$(ls "$out"/session[0-9].jsonl; ls "$out"/session-resume-*.jsonl 2>/dev/null)
last=$(printf '%s\n' "$all" | tail -1)
denied=$(cat $all | grep -c 'Permission to use' || true)
speckit=$(scn_speckit_used $all); reachable=$(scn_speckit_reachable $all)
dispatches() { local n=0 s; for s in $all; do n=$((n + $(scn_dispatches "$s" "$1"))); done; echo "$n"; }
writers=$(scn_put_writers $all | awk -F'\t' '$2 ~ /^(reports|reviews|plan-review|review\/(findings|scoped))/')
by_session=$(printf '%s\n' "$writers" | grep -c '^main' || true); by_agents=$(printf '%s\n' "$writers" | grep -c '^agent' || true)
fjc=$(git -C "$r" log --format=%h "$base..HEAD" -- .specify/feature.json | tr '\n' ' '); fjc=${fjc% }
finish=$(scn_bash_output 'keel-verify run .*--label finish' $all | grep -E '^(RESULT|FAILING|NEW|TESTS|MISSING)=' | tr '\n' ' ')
q1=$(scn_result "$s1" | tail -c 400); q2=$(scn_result "$s2" | tail -c 400)
cp -R "$r" "$out/repo"   # keep the result for inspection

# SC-006: Spec Kit reads keel's artifacts
sk=$(t_tmp)/speckit-copy; cp -R "$r" "$sk"
mkdir -p "$sk/.claude/skills"; cp -R "$skhost/.specify/scripts" "$skhost/.specify/templates" "$sk/.specify/" 2>/dev/null
cp -R "$skhost/.claude/skills/speckit-analyze" "$sk/.claude/skills/" 2>/dev/null
prereq=$(cd "$sk" && bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks 2>&1 | tail -1)
an=$(cd "$sk" && claude -p --model "$KEEL_SCN_MODEL" --settings "$KEEL_SCN_SETTINGS" --allowedTools "Bash,Read,Glob,Grep,Skill" --max-turns 40 "/speckit-analyze" 2>&1 </dev/null)
printf '%s\n' "$an" > "$out/speckit-analyze.txt"

{
  printf '## Full-path trial (T080), %s\n\n' "$(date +%Y-%m-%d)"
  printf -- '- **Repo**: sample-maven; feature `%s`; model `%s`; wall time %d min; resumes needed: %d.\n' "$f" "$KEEL_SCN_MODEL" $(( (end - start) / 60 )) "$resumes"
  printf -- '- **keel-state next**: `STEP=%s`.\n' "$step"
  printf -- '- **Gates**: session 1 ended with: …%s\n' "$(printf '%s' "$q1" | tr '\n' ' ' | tail -c 200)"
  printf -- '  session 2 ended with: …%s\n' "$(printf '%s' "$q2" | tr '\n' ' ' | tail -c 200)"
  printf -- '- **Agents**: explorers %s, architects %s, plan reviewers %s, implementers %s, task reviewers %s, code reviewers %s.\n' \
    "$(dispatches explorer)" "$(dispatches architect)" "$(dispatches plan-reviewer)" \
    "$(dispatches implementer)" "$(dispatches task-reviewer)" "$(dispatches code-reviewer)"
  printf -- '  (distinct top-level Agent dispatches across all sessions)\n'
  printf -- '- **Commits** (`%s..HEAD`):\n\n```text\n%s\n```\n\n' "${base:0:7}" "$(git -C "$r" log --format='%h %s' "$base..HEAD")"
  printf -- '- **Evidence per behavior task**:\n'
  for t in $(grep -oE '^- \[X\] T[0-9]{3}' "$r/specs/$f/tasks.md" | grep -oE 'T[0-9]{3}'); do
    kind=$(scn_keel "$r" keel-diff "$f" --kind "$t" | sed -n 's/^KIND=//p')
    chk=$(scn_keel "$r" keel-evidence check "$f" "$t" >/dev/null 2>&1 && echo pass || echo "fail")
    printf '  - `%s` (%s): evidence check %s; verify log %s\n' "$t" "$kind" "$chk" "$([ -f "$g/keel/$f/verify/$t.log" ] && echo present || echo missing)"
  done
  printf -- '- **Test quality**: %s; %s\n' "$(grep -m1 '^\*\*Result\*\*' "$r/specs/$f/test-quality.md" 2>/dev/null)" "$(grep -m1 '^\*\*Summary\*\*' "$r/specs/$f/test-quality.md" 2>/dev/null)"
  printf -- '- **Spec status**: %s\n' "$(grep -m1 '^\*\*Status\*\*' "$r/specs/$f/spec.md")"
  printf -- '- **Finish verify** (keel-verify stdout): %s(log %s)\n' "${finish:-no finish run found }" "$([ -f "$g/keel/$f/verify/finish.log" ] && echo present || echo missing)"
  printf -- '- **Agent outputs stored by the session itself** (must be 0): %s; **by the agents**: %s (background agents'\'' calls are not in the stream).\n' "$by_session" "$by_agents"
  printf -- '- **Commits touching `.specify/feature.json`**: %s\n' "${fjc:-none}"
  printf -- '- **Build files unchanged**: %s\n' "$([ -z "$(git -C "$r" diff --name-only "$base" HEAD -- pom.xml mvnw .mvn)" ] && echo yes || echo NO)"
  printf -- '- **Co-author trailers**: %s; **tree**: %s; **remote refs**: none (no remote configured; the guard blocks pushes regardless).\n' \
    "$(git -C "$r" log --format=%B "$base..HEAD" | grep -ci 'co-authored-by' | sed 's/^0$/none/')" \
    "$( [ -z "$(git -C "$r" status --porcelain | grep -v '\.specify/feature\.json$')" ] && echo clean || echo dirty)"
  printf -- '- **Permission denials in the sessions (SC-001)**: %s; **Spec Kit CLI or speckit-* skill used (SC-007)**: %s; **speckit skills or commands reachable**: %s.\n' "$denied" "$speckit" "$reachable"
  printf -- '- **SC-006, Spec Kit reads the artifacts**: check-prerequisites: `%s`\n' "$(printf '%s' "$prereq" | cut -c1-200)"
  printf -- '  `/speckit-analyze`: %s\n' "$(printf '%s\n' "$an" | grep -m3 -iE 'critical issues|coverage %|total requirements' | tr '\n' ';' | cut -c1-300)"
  printf -- '- **Final message**:\n\n```text\n%s\n```\n' "$(scn_result "$last" | head -40)"
} | tee "$out/section.md"
