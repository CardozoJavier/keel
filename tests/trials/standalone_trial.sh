#!/bin/bash
# T074 trial (non-behavior): one standalone keel capability on an existing repository. Prints a
# RESULTS.md section with the final message, and whether the tree or HEAD changed.
# Usage: tests/trials/standalone_trial.sh <repo> "<prompt, e.g. /keel:verify>"
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/scenarios/lib.sh"
repo=${1:?repo}; prompt=${2:?prompt}
before_head=$(git -C "$repo" rev-parse HEAD); before_status=$(git -C "$repo" status --porcelain)
out=$(scn_claude "$repo" 40 "$prompt" --output-format stream-json --verbose)
{
  printf '## standalone trial (T074): `%s` in `%s`, %s\n\n' "$prompt" "$(basename "$repo")" "$(date +%Y-%m-%d)"
  printf -- '- **Guard self-check ran first**: %s\n' "$(scn_bash_ran "$out" 'keel-state (guard|require)')"
  printf -- '- **Commits**: %s; **tree**: %s.\n' \
    "$([ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ] && echo none || echo CHANGED)" \
    "$([ "$(git -C "$repo" status --porcelain)" = "$before_status" ] && echo unchanged || echo CHANGED)"
  printf -- '- **Final message**:\n\n```text\n%s\n```\n' "$(scn_result "$out" | head -40)"
}
