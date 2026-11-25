#!/bin/bash
# Handoff templates (contracts/agent-handoffs.md): the implementer report and the code-review
# finding carry every field the orchestrator and the evidence rules read; the agents that return
# them point at the templates.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
T="$KEEL_PLUGIN_ROOT/templates"

report=$(cat "$T/report.md" 2>/dev/null)
for field in '# Report: {{UNIT}}' '**Status**:' 'DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT' \
             '**Files changed**:' '**Evidence**:' 'RED seq' 'GREEN seq' 'index.tsv' \
             '**Triage proposals**:' '**What was done**:' '**Concerns / blockers / questions**:'; do
  assert_contains "$report" "$field" "report.md has $field"
done

finding=$(cat "$T/finding.md" 2>/dev/null)
for field in '[Critical|Important|Minor]' 'confidence' 'scope' 'in-design|changes-design' '<file:line>' '—'; do
  assert_contains "$finding" "$field" "finding.md has $field"
done
assert_contains "$finding" "80" "finding.md states the confidence floor"
assert_contains "$finding" "No findings" "finding.md says how to report an empty review"

assert_contains "$(cat "$KEEL_PLUGIN_ROOT/agents/implementer.md" 2>/dev/null)" "templates/report.md" "the implementer returns templates/report.md"
assert_contains "$(cat "$KEEL_PLUGIN_ROOT/agents/code-reviewer.md" 2>/dev/null)" "templates/finding.md" "the code-reviewer returns templates/finding.md"
for field in '**Verdict**: PASS | FIX' '**Spec compliance**:' '**RED validity**:' '**Behavior unchanged**:' '**Test quality**:' '**Issues**:'; do
  assert_contains "$(cat "$KEEL_PLUGIN_ROOT/agents/task-reviewer.md" 2>/dev/null)" "$field" "task-reviewer returns $field"
done
t_summary
