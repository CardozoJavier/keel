#!/bin/bash
# Skill frontmatter and preconditions (plan §Run control, T056, research R7.4):
# - every skill has a name matching its directory and a description;
# - every user-facing skill declares allowed-tools (they apply when the run invokes it with the
#   Skill tool; a preload grants nothing, so the internal tdd skill declares none);
# - every step skill's first keel-state call is `keel-state require <its step>`;
#   run and the standalone skills start with `keel-state guard`;
# - skills that commit carry the never-publish rule.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
S="$KEEL_PLUGIN_ROOT/skills"
STEP_SKILLS="constitution specify clarify plan tasks analyze implement review finish"
GUARD_SKILLS="run debug verify respond-review"
COMMIT_SKILLS="analyze implement review finish"

fm() { awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { exit } f' "$1"; }

for d in "$S"/*/; do
  n=$(basename "$d"); f="$d/SKILL.md"
  assert_eq yes "$([ -f "$f" ] && echo yes)" "$n has SKILL.md"
  front=$(fm "$f")
  assert_contains "$front" "name: $n" "$n: frontmatter name matches the directory"
  assert_contains "$front" "description: " "$n: has a description"
  case "$n" in
    tdd)
      assert_contains "$front" "user-invocable: false" "tdd is internal (preloaded into the implementer)" ;;
    *)
      assert_contains "$front" "allowed-tools: " "$n declares allowed-tools" ;;
  esac
done

for n in $STEP_SKILLS; do
  first=$(grep -oE 'keel-state (require [a-z-]+|guard|next)' "$S/$n/SKILL.md" 2>/dev/null | grep -v '^keel-state next' | head -1)
  assert_eq "keel-state require $n" "$first" "$n starts with keel-state require $n"
  assert_contains "$(fm "$S/$n/SKILL.md")" "Bash(keel-state:*)" "$n allows keel-state"
done
for n in $GUARD_SKILLS; do
  first=$(grep -oE 'keel-state (require [a-z-]+|guard)' "$S/$n/SKILL.md" 2>/dev/null | head -1)
  assert_eq "keel-state guard" "$first" "$n starts with keel-state guard"
done
for n in $COMMIT_SKILLS; do
  body=$(cat "$S/$n/SKILL.md" 2>/dev/null)
  assert_contains "$body" "Never push" "$n: never push"
  assert_contains "$body" "AI co-author trailer" "$n: host commit style, no AI co-author trailer where forbidden"
  assert_contains "$(fm "$S/$n/SKILL.md")" "Bash(git commit:*)" "$n allows git commit"
done
assert_contains "$(fm "$S/run/SKILL.md")" "Skill" "run allows the Skill tool"
for n in plan implement review; do
  assert_contains "$(fm "$S/$n/SKILL.md")" "Agent" "$n allows dispatching agents"
done
# tdd-preload (T043): the implementer carries the TDD and debugging discipline as preloaded skills
# (a skills: preload delivers content into plugin agents, research R7.4); behavior is checked by
# tests/scenarios/us2_implement_red_green (RED before GREEN from a fresh implementer)
assert_contains "$(fm "$KEEL_PLUGIN_ROOT/agents/implementer.md")" "skills: [tdd, debug]" "the implementer preloads tdd and debug"
t_summary
