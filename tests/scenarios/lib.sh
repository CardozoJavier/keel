# shellcheck shell=bash
# Scenario checks for keel's skills and agents (constitution V): real `claude -p --plugin-dir`
# sessions against scaffolded repositories, with deterministic assertions on files, branches and
# output. `claude plugin eval` can't be used for these: its OS sandbox refuses to execute files
# from the plugin directory, which includes keel's scripts and its git shim (research R7.3).
# Run with `tests/run.sh --scenarios` (each scenario costs a model session).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

KEEL_SCN_MODEL=${KEEL_SCN_MODEL:-sonnet}
# Other workflow plugins and engram are off unless a scenario turns them on (SC-007, SC-008).
# jdtls-lsp is off too: in a nested session it compiles with ECJ but without the Maven classpath,
# and leaves stub classes in target/ plus .project/.classpath/.settings (research R7.5).
KEEL_SCN_SETTINGS=${KEEL_SCN_SETTINGS:-'{"enabledPlugins":{"superpowers@claude-plugins-official":false,"feature-dev@claude-plugins-official":false,"pr-review-toolkit@claude-plugins-official":false,"engram@engram":false,"jdtls-lsp@claude-plugins-official":false,"github@claude-plugins-official":false}}'}

# scn_repo: a fresh git repo on main at <tmp>/repo (prints its path); session output goes in <tmp>
scn_repo() {
  local d
  d="$(t_tmp)/repo"
  mkdir "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email keel-test@example.invalid
  git -C "$d" config user.name keel-test
  git -C "$d" config commit.gpgsign false
  printf 'target/\n' > "$d/.gitignore"
  printf '%s\n' "$d"
}

# scn_claude <dir> <max-turns> <prompt> [extra claude args...]: run one session in <dir>.
# Writes the session output to <dir>/../scenario-<ts>.XXXXXX.out and prints that path.
# KEEL_SCN_EXTRA_TOOLS adds allowed tools (e.g. mcp__engram for the memory scenarios).
# KEEL_SCN_PLUGIN overrides the plugin under test, e.g. a copy without one skill, to watch a
# scenario fail before that skill exists.
scn_claude() {
  local dir=$1 turns=$2 prompt=$3 out
  shift 3
  out=$(mktemp "$(dirname "$dir")/scenario-$(date +%s).XXXXXX")
  (cd "$dir" && claude -p --model "$KEEL_SCN_MODEL" --plugin-dir "${KEEL_SCN_PLUGIN:-$KEEL_PLUGIN_ROOT}" \
     --settings "$KEEL_SCN_SETTINGS" \
     --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Skill,Agent${KEEL_SCN_EXTRA_TOOLS:+,$KEEL_SCN_EXTRA_TOOLS}" \
     --max-turns "$turns" "$@" "$prompt" > "$out" 2>&1 </dev/null)
  printf '%s\n' "$out"
}

# scn_continue <dir> <max-turns> <prompt> [extra claude args...]: continue the last session in
# <dir> (multi-turn gates).
scn_continue() {
  local dir=$1 turns=$2 prompt=$3
  shift 3
  scn_claude "$dir" "$turns" "$prompt" --continue "$@"
}

# scn_constitution <dir>: a minimal constitution so runs skip that step.
scn_constitution() {
  mkdir -p "$1/.specify/memory"
  printf '# Shop Constitution\n\n## Principles\n\n### I. Tests first\nEvery behavior change starts with a failing test.\n\n**Version**: 1.0.0 | **Ratified**: %s\n' "$(date +%Y-%m-%d)" > "$1/.specify/memory/constitution.md"
}

# scn_keel <dir> <keel-script> [args...]: run a keel script in <dir> with the guard environment
scn_keel() {
  local dir=$1 bin=$2
  shift 2
  (cd "$dir" && KEEL_ROOT="$KEEL_PLUGIN_ROOT" /bin/sh -c \
    "export KEEL_ROOT; . '$KEEL_PLUGIN_ROOT/hooks/keel-env.sh'; exec '$KEEL_PLUGIN_ROOT/bin/$bin' \"\$@\"" \
    "$bin" "$@" 2>&1)
}

# scn_state <dir> [keel-state next args...]: keel-state next in <dir> with the guard environment
scn_state() {
  local dir=$1
  shift
  scn_keel "$dir" keel-state next "$@"
}

# scn_sample: the Maven sample fixture (tests/fixtures/sample-maven) as a fresh repo at
# <tmp>/repo with a committed constitution (prints its path)
scn_sample() {
  local d
  d="$(t_tmp)/repo"
  /bin/bash "$KEEL_REPO_ROOT/tests/fixtures/mk-sample.sh" "$d" >/dev/null
  scn_constitution "$d"
  git -C "$d" add -A
  git -C "$d" commit -q -m "docs: constitution"
  printf '%s\n' "$d"
}

# scn_light_feature <dir> <feature> <title> <FR-001 text>: bind a light-path feature whose spec is
# approved and whose single-design plan is complete (keel-state next = tasks). Markers follow
# data-model.md §3, as in tests/scripts/keel-state_test.sh.
scn_light_feature() {
  local dir=$1 f=$2 title=$3 fr=$4 base
  base=$(git -C "$dir" rev-parse HEAD)
  git -C "$dir" switch -q -c "$f"
  mkdir -p "$dir/specs/$f" "$dir/.specify"
  printf '{"feature_directory": "specs/%s"}\n' "$f" > "$dir/.specify/feature.json"
  {
    printf '# Feature Specification: %s\n\n' "$title"
    printf '**Feature Branch**: `%s`\n' "$f"
    printf '**Status**: Approved (Gate 1, %s)\n' "$(date +%Y-%m-%d)"
    printf '**Path**: light (accepted at Gate 1)\n'
    printf '**Base**: %s (main)\n\n' "$base"
    printf '## User Scenarios & Testing *(mandatory)*\n\n'
    printf '### User Story 1 - %s (Priority: P1)\n\n' "$title"
    printf '**Acceptance Scenarios**:\n\n'
    printf '1. **Given** the behavior in FR-001, **When** it is exercised, **Then** it holds.\n\n'
    printf '## Requirements *(mandatory)*\n\n- **FR-001**: %s\n\n' "$fr"
    printf '## Change Classification\n\n| Criterion | Answer |\n|---|---|\n'
    printf '| External contract | no |\n| Persisted data | no |\n| Easy to reverse | yes |\n\n'
    printf '**Qualifies as small**: yes\n'
  } > "$dir/specs/$f/spec.md"
  {
    printf '# Implementation Plan: %s\n\n' "$title"
    printf '**Branch**: `%s` | **Spec**: [spec.md](./spec.md)\n' "$f"
    printf '**Plan status**: complete\n\n'
    printf '## Design Decision\n\n**Chosen**: single design (light path)\n\n'
    printf 'Implement FR-001 directly in the existing type, test-first.\n\n'
    printf '## Technical Context\n\nJava 21, Maven, JUnit 5. Build and test: `mvn -q verify`.\n'
  } > "$dir/specs/$f/plan.md"
  scn_keel "$dir" keel-ledger append "$f" branch ok "$base" "$f" >/dev/null
}

# scn_analyzed <dir> <feature> <tasks-body>: write tasks.md with an **Analyzed** line (baseline 0
# failing) and the keel:baseline comment, then make the docs commit (keel-state next = implement).
scn_analyzed() {
  local dir=$1 f=$2 body=$3
  {
    printf '# Tasks: %s\n\n' "$f"
    printf '**Analyzed**: %s (baseline 0 failing; build maven; tests present; setup none)\n' "$(date +%Y-%m-%d)"
    printf '<!-- keel:baseline\ncmd: mvn %%2Dq verify\n%s\n' '-->'
    printf '\n## Phase 1: User Story 1\n\n%s\n' "$body"
  } > "$dir/specs/$f/tasks.md"
  git -C "$dir" add -A -- specs .specify/memory
  git -C "$dir" commit -q -m "docs($f): spec, plan and tasks"
}

# scn_dispatches <stream-json file> <agent>: how many keel:<agent> subagents the main session
# dispatched. It counts unique top-level Agent tool_use ids; stream-json repeats each call's input
# in later events, so a plain grep overcounts.
scn_dispatches() {
  python3 -I -c '
import json, sys
seen = set()
for line in open(sys.argv[1], errors="replace"):
    try:
        o = json.loads(line)
    except ValueError:
        continue
    if o.get("type") != "assistant" or o.get("parent_tool_use_id"):
        continue
    for b in (o.get("message") or {}).get("content") or []:
        if (b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task")
                and (b.get("input") or {}).get("subagent_type") == "keel:" + sys.argv[2]):
            seen.add(b.get("id"))
print(len(seen))
' "$1" "$2"
}

# scn_result <stream-json file>: the session's final result text
scn_result() {
  python3 -I -c '
import json, sys
r = ""
for line in open(sys.argv[1], errors="replace"):
    try:
        o = json.loads(line)
    except ValueError:
        continue
    if o.get("type") == "result":
        r = str(o.get("result"))
print(r)
' "$1"
}

# scn_bash_ran <stream-json file> <ERE>: yes if any Bash call in the session (main or subagent)
# ran a command matching <ERE>
scn_bash_ran() {
  python3 -I -c '
import json, re, sys
pat = re.compile(sys.argv[2])
for line in open(sys.argv[1], errors="replace"):
    try:
        o = json.loads(line)
    except ValueError:
        continue
    m = o.get("message")
    content = m.get("content") if isinstance(m, dict) else None
    for b in content if isinstance(content, list) else []:
        if b.get("type") == "tool_use" and b.get("name") == "Bash" and pat.search((b.get("input") or {}).get("command", "")):
            print("yes"); sys.exit(0)
print("no")
' "$1" "$2"
}

# scn_speckit_used <session.jsonl...>: Spec Kit invocations (SC-007), by any agent in the sessions:
# Skill calls of a speckit-* skill, and Bash calls that run the `specify` CLI as a command (also
# through uvx, pipx or uv tool run). A keel step named "specify", tool output and prose don't count.
scn_speckit_used() {
  python3 -I -c '
import json, re, sys
skill = re.compile(r"(^|:)speckit-")
cli = re.compile(r"(^|[;&|(\n]|\$\()\s*([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(\S*/)?specify(\s|$)"
         r"|\b(uvx|pipx\s+run|uv\s+tool\s+run)\b[^;&|\n]*\sspecify(\s|$)")
n = 0
for fn in sys.argv[1:]:
    for line in open(fn, errors="replace"):
        try:
            o = json.loads(line)
        except ValueError:
            continue
        m = o.get("message")
        content = m.get("content") if isinstance(m, dict) else None
        for b in content if isinstance(content, list) else []:
            if not isinstance(b, dict) or b.get("type") != "tool_use":
                continue
            i = b.get("input") or {}
            if b.get("name") == "Skill" and skill.search(str(i.get("skill", ""))):
                n += 1
            elif b.get("name") == "Bash" and cli.search(str(i.get("command", ""))):
                n += 1
print(n)
' "$@"
}

# scn_speckit_reachable <session.jsonl...>: distinct speckit skills or slash commands the sessions'
# init messages offered (SC-007: none should be reachable).
scn_speckit_reachable() {
  python3 -I -c '
import json, sys
names = set()
for fn in sys.argv[1:]:
    for line in open(fn, errors="replace"):
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if o.get("type") == "system" and o.get("subtype") == "init":
            for k in ("skills", "slash_commands", "agents"):
                for x in o.get(k) or []:
                    if isinstance(x, str) and "speckit" in x:
                        names.add(x)
print(len(names))
' "$@"
}

# scn_bash_output <regex> <session.jsonl...>: the output of the last Bash call (across the sessions,
# in order) whose command matches <regex>; empty when none does.
scn_bash_output() {
  python3 -I -c '
import json, re, sys
pat = re.compile(sys.argv[1])
ids, last = set(), ""
for fn in sys.argv[2:]:
    for line in open(fn, errors="replace"):
        try:
            o = json.loads(line)
        except ValueError:
            continue
        m = o.get("message")
        content = m.get("content") if isinstance(m, dict) else None
        for b in content if isinstance(content, list) else []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use" and b.get("name") == "Bash" and pat.search(str((b.get("input") or {}).get("command", ""))):
                ids.add(b.get("id"))
            elif b.get("type") == "tool_result" and b.get("tool_use_id") in ids:
                r = b.get("content")
                if isinstance(r, list):
                    r = "".join(x.get("text", "") for x in r if isinstance(x, dict))
                last = str(r)
print(last)
' "$@"
}
