#!/bin/bash
# SC-006: plain Spec Kit's vendored check-prerequisites.sh accepts a keel-produced feature dir
# (keel's Base/Path/Plan status/Analyzed lines and keel:baseline comment) exactly like a plain one.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
VENDOR="$KEEL_PLUGIN_ROOT/vendor/speckit"

run_check() { # <fixture-dir-name> → prints normalized JSON
  local r f
  r=$(mk_repo)
  mkdir -p "$r/.specify/scripts/bash" "$r/specs/001-refund-limit"
  cp "$VENDOR/scripts/bash/common.sh" "$VENDOR/scripts/bash/check-prerequisites.sh" "$r/.specify/scripts/bash/"
  cp "$KEEL_TESTS_ROOT/fixtures/repos/$1/"*.md "$r/specs/001-refund-limit/"
  printf '{"feature_directory": "specs/001-refund-limit"}\n' > "$r/.specify/feature.json"
  git -C "$r" add -A >/dev/null && git -C "$r" commit -q -m fixture
  git -C "$r" switch -q -c 001-refund-limit
  (cd "$r" && /bin/bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks) | sed "s#$(cd "$r" && pwd -P)#ROOT#g; s#$r#ROOT#g"
}

keel=$(run_check keel-feature); rc_k=$?
plain=$(run_check plain-feature); rc_p=$?
assert_eq 0 "$rc_k" "check-prerequisites accepts the keel feature dir"
assert_eq 0 "$rc_p" "check-prerequisites accepts the plain feature dir"
assert_contains "$keel" '"FEATURE_DIR":"ROOT/specs/001-refund-limit"' "FEATURE_DIR resolves"
assert_contains "$keel" 'tasks.md' "tasks.md is listed"
assert_eq "$plain" "$keel" "keel markers change nothing Spec Kit reports"

# keel's template edits keep Spec Kit's mandatory headings
for h in '## User Scenarios & Testing' '## Requirements' '## Success Criteria'; do
  assert_contains "$(cat "$VENDOR/templates/spec-template.md")" "$h" "spec template keeps '$h'"
done
assert_contains "$(cat "$VENDOR/templates/spec-template.md")" '**Base**:' "spec template has the keel Base line"
assert_contains "$(cat "$VENDOR/templates/spec-template.md")" '## Change Classification' "spec template has Change Classification"
assert_contains "$(cat "$VENDOR/templates/plan-template.md")" '**Plan status**:' "plan template has Plan status"
assert_contains "$(cat "$VENDOR/templates/plan-template.md")" '## Design Decision' "plan template has Design Decision"
assert_contains "$(cat "$VENDOR/templates/plan-template.md")" '## Plan Review' "plan template has Plan Review"
assert_contains "$(cat "$VENDOR/templates/tasks-template.md")" 'names both the test path and the production path' "tasks template has the behavior-task rule"
assert_contains "$(cat "$VENDOR/templates/tasks-template.md")" '**Analyzed**' "tasks template notes the Analyzed line"
assert_eq "yes" "$([ -f "$VENDOR/LICENSE" ] && grep -q 'Copyright GitHub, Inc.' "$VENDOR/LICENSE" && echo yes)" "Spec Kit MIT license vendored"

t_summary
