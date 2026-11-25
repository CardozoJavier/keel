#!/bin/bash
# T068 trial (non-behavior): /keel:test-audit <module> on an existing repository, read-only. It prints
# a RESULTS.md section: the report path, its summary line, the module arguments keel chose, and
# whether the tree changed.
# Usage: tests/trials/test_audit_trial.sh <repo> <module>
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/scenarios/lib.sh"
repo=${1:?repo}; module=${2:?module}
before_head=$(git -C "$repo" rev-parse HEAD); before_status=$(git -C "$repo" status --porcelain)
g=$(git -C "$repo" rev-parse --absolute-git-dir)
existing=$(ls -d "$g"/keel/audit/*/ 2>/dev/null)
out=$(scn_claude "$repo" 40 "/keel:test-audit $module" --output-format stream-json --verbose)
rep=$(for d in "$g"/keel/audit/*/; do printf '%s\n' "$existing" | grep -qxF "$d" || { [ -f "$d/report.md" ] && echo "${d%/}/report.md"; }; done | tail -1)
{
  printf '## test-audit trial (T068): `%s` in `%s`, %s\n\n' "$module" "$(basename "$repo")" "$(date +%Y-%m-%d)"
  printf -- '- **Report**: `%s`\n' "${rep#$g/}"
  printf -- '- **Summary**: %s\n' "$(grep -m1 -oE '[0-9]+ mutants \([0-9]+ in scope\)[^|]*' "${rep:-/dev/null}" | head -1)"
  printf -- '- **Module args**: `%s`\n' "$(cat "$(dirname "${rep:-/x}")"/*/module-args 2>/dev/null | head -1)"
  printf -- '- **Commits**: %s; **tree**: %s.\n' \
    "$([ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ] && echo none || echo CHANGED)" \
    "$([ "$(git -C "$repo" status --porcelain)" = "$before_status" ] && echo unchanged || echo CHANGED)"
  printf -- '- **Final message**:\n\n```text\n%s\n```\n' "$(scn_result "$out" | head -40)"
}
