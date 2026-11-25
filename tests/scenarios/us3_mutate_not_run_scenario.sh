#!/bin/bash
# FR-035: a feature mutation analysis can't measure (no Java production change) is recorded as
# `**Result**: not-run (<reason>)` in a committed test-quality.md, after a verify, and the run moves on.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
f=001-readme-note
scn_light_feature "$r" "$f" "Readme note" "The README MUST say how to run the tests."
scn_analyzed "$r" "$f" "- [ ] T001 [US1] Document the test command in README.md"
printf '# Shop\n\nRun the tests with `mvn -q verify`.\n' > "$r/README.md"
sed -i '' 's/^- \[ \] T001 /- [X] T001 /' "$r/specs/$f/tasks.md"
git -C "$r" add -A -- README.md specs; git -C "$r" commit -q -m "docs(readme): T001 document the test command"
assert_eq mutate "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "staged at mutate"
out=$(scn_claude "$r" 40 "/keel:mutate --feature $f" --output-format stream-json --verbose)
assert_eq yes "$(scn_bash_ran "$out" 'keel-mutate ')" "keel-mutate ran (out: $out)"
tq=$(git -C "$r" show "HEAD:specs/$f/test-quality.md" 2>/dev/null)
assert_eq yes "$(printf '%s\n' "$tq" | grep -qE '^\*\*Result\*\*: not-run \(.*nothing to analyze' && echo yes)" "Result is not-run with keel-mutate's reason"
g=$(git -C "$r" rev-parse --absolute-git-dir)
assert_eq yes "$([ -f "$g/keel/$f/verify/test-quality.log" ] && echo yes)" "keel-verify ran before the commit"
assert_contains "$(git -C "$r" log --format=%s -1)" "test-quality" "the commit says test-quality"
assert_eq review "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "keel-state moves on to review"
t_summary
