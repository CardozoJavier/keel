#!/bin/bash
# T058 trial (plan M3 check, non-behavior): the light path from a plain-language request through
# implement in a fresh sample repo. It uses mk-sample.sh and real `claude -p --plugin-dir` sessions,
# with superpowers, feature-dev, pr-review-toolkit and engram disabled, and no speckit-* skills in
# the repo. mutate isn't built yet, so the run must stop there.
# Expected: one approval (Gate 1), no other prompts, every task committed with RED/GREEN evidence
# and verify output, and keel-state next = mutate.
# Usage: tests/trials/light_path_trial.sh <out-dir>   (prints a RESULTS.md section to stdout)
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/scenarios/lib.sh"
out=${1:?out dir}; mkdir -p "$out"
r=$(scn_sample)
[ -z "$(ls -d "$r"/.claude/skills/speckit-* 2>/dev/null)" ] || { echo "speckit skills present in the trial repo" >&2; exit 1; }
prompt='/keel:run Add an isZero() method to the Price record that returns true when the amount is 0.

Clarification answers, so you do not need to ask anything:
- Intent and why: callers repeat `price.minor() == 0` in several places.
- Goals: a readable isZero() check.
- Non-goals: any other Price behavior.
- Anti-goals: changing how prices are stored or serialized.
- Missing requirements: none.'
s1=$(scn_claude "$r" 60 "$prompt")
s2=$(scn_continue "$r" 200 "I approve the spec with the light path." --output-format stream-json --verbose)
cp "$s1" "$out/session1.out"; cp "$s2" "$out/session2.jsonl"
f=$(basename "$(dirname "$(ls "$r"/specs/001-*/spec.md | head -1)")")
g=$(git -C "$r" rev-parse --absolute-git-dir)
state=$(scn_state "$r" --feature "$f")
step=$(printf '%s\n' "$state" | sed -n 's/^STEP=//p')
base=$(printf '%s\n' "$state" | sed -n 's/^BASE=//p')
tasks=$(grep -oE '^- \[X\] T[0-9]{3}' "$r/specs/$f/tasks.md" | grep -oE 'T[0-9]{3}')
total=$(grep -cE '^- \[.\] T[0-9]{3}' "$r/specs/$f/tasks.md")
{
  printf '## Light-path trial (T058), %s\n\n' "$(date +%Y-%m-%d)"
  printf -- '- **Repo**: `tests/fixtures/sample-maven` via `scn_sample`; feature `%s`; model `%s`.\n' "$f" "$KEEL_SCN_MODEL"
  printf -- '- **Approvals**: 1 prompt (Gate 1) in session 1; session 2 approved it with the light path.\n'
  printf -- '- **keel-state next**: `STEP=%s`.\n' "$step"
  printf -- '- **Tasks**: %s of %s ticked.\n' "$(printf '%s\n' "$tasks" | grep -c .)" "$total"
  printf -- '- **Commits** (`%s..HEAD`):\n\n```text\n%s\n```\n\n' "${base:0:7}" "$(git -C "$r" log --format='%h %s' "$base..HEAD")"
  printf -- '- **Evidence per task**:\n'
  for t in $tasks; do
    kind=$(scn_keel "$r" keel-diff "$f" --kind "$t" | sed -n 's/^KIND=//p')
    chk=$(scn_keel "$r" keel-evidence check "$f" "$t" >/dev/null 2>&1 && echo pass || echo fail)
    vr=$(grep -h 'RESULT=' "$g/keel/$f/verify/$t.log" 2>/dev/null | tail -1)
    phases=$(awk -F'\t' 'NR > 1 || $1 ~ /^[0-9]/ { printf "%s:%s ", $2, $3 }' "$g/keel/$f/evidence/$t/index.tsv" 2>/dev/null)
    printf '  - `%s` (%s): evidence check %s; runs (phase:exit) `%s`; verify log %s\n' "$t" "$kind" "$chk" "${phases% }" "$([ -f "$g/keel/$f/verify/$t.log" ] && echo present || echo missing)"
  done
  printf -- '- **Co-author trailers**: %s.\n' "$(git -C "$r" log --format=%B "$base..HEAD" | grep -ci 'co-authored-by' | sed 's/^0$/none/')"
  printf -- '- **Tree**: %s.\n' "$( [ -z "$(git -C "$r" status --porcelain | grep -v '\.specify/feature\.json$')" ] && echo clean || echo dirty)"
  printf -- '- **Questions after Gate 1** (session 2 final message):\n\n```text\n%s\n```\n' \
    "$(python3 -I -c 'import json,sys
r=""
for l in open(sys.argv[1], errors="replace"):
    try: o=json.loads(l)
    except ValueError: continue
    if o.get("type")=="result": r=str(o.get("result"))
print(r[-1500:])' "$s2")"
} | tee "$out/section.md"
