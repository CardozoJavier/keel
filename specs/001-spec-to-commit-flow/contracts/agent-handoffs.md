# Contract: Agent Handoffs

How handoffs move between the orchestrating session and agents:
- **Inputs reach agents as file paths**: briefs and diffs, written by keel's scripts. Content isn't
  pasted.
- **Agents never write under `.git`**, which is a protected path and always prompts. Each agent
  returns its report as its **final message**, in the format below.
- **The orchestrator stores it** with `keel-put <feature> <relpath> <<'EOF' … EOF`.
- **Only the implementer edits files**, and only project files.

This scheme is adapted from superpowers' SDD.

## Agents

| Agent | Tools | Preloaded skills | Model | Source |
|---|---|---|---|---|
| explorer | Read, Grep, Glob | none | sonnet | feature-dev code-explorer (Apache-2.0, modified) |
| architect | Read, Grep, Glob | none | inherit | feature-dev code-architect (Apache-2.0, modified: one lens per call, no single commitment) |
| plan-reviewer | Read, Grep, Glob | none | inherit | keel (the maintainer's Plan Review Protocol) |
| implementer | Read, Edit, Write, Bash, Grep, Glob | tdd, debug | inherit | superpowers SDD implementer prompt (MIT, adapted) |
| task-reviewer | Read, Grep, Glob | none | inherit | superpowers SDD task reviewer (MIT, adapted) |
| code-reviewer | Read, Grep, Glob | none | inherit | feature-dev code-reviewer (Apache-2.0, modified) + superpowers severity calibration (MIT) |

- **Reading scratch**: reviewers and explorers read files under `.git/keel/` (reads don't prompt)
  but don't run Bash.
- **Implementer Bash**: covered by both push-guard layers. Layer A covers it if the session env
  applies to subagents (verification item 5).
- **Permissions**: the implementer's Bash allow rules come from the quickstart's permission block
  (verification item 6 checks they apply inside plugin subagents).

## Brief (`briefs/<unit>.md`, from `templates/brief.md`, written by `keel-brief`)

```markdown
# Brief: <unit> <description>
**Feature**: <NNN-name> | **Unit**: T### | MUT-n | REV-n | FIN-n | **Story**: US# | **BASE**: <sha> | **Kind**: behavior | non-behavior | **Intent**: n/a | fix | refactor
## Task or finding
<tasks.md line verbatim (T###); classification rows (MUT-n, FIN gap units); verified findings (REV-n, FIN fix units); verify-log excerpt (FIN-n on a failing verify)>
## Allowed paths
<per the unit's row in data-model.md §7; anything else is out of scope>
## Requirements in scope
<FR-### and acceptance scenarios, verbatim from spec.md>
## Design context
<plan/data-model/contracts excerpts>
## Rules
- Behavior task: write the test first and run it with `keel-evidence run <feature> <unit> red -- <test cmd>`; it must fail for the right reason. Then make the smallest change and run `… green -- <test cmd>`, then refactor and run `… refactor -- <test cmd>`.
- Non-behavior task: make the change; run the relevant check with `keel-evidence run … green -- <cmd>` if one exists.
- Mutation-gap unit (MUT-n, FIN gap): add or strengthen tests only (no production code), run them with `… green -- <test cmd>`, and propose triage rows for gaps a test can't catch.
- Refactor unit (`intent=refactor`): change no behavior and write no RED; run the tests with `… refactor -- <test cmd>`.
- Allowed paths are advisory for `T###`: ripple edits are fine and get reported. Build files are the exception, and so are the hard limits of MUT and FIN gap units.
- Do not commit. Do not edit build files unless this task says so. Do not write under .git. Never push.
- Do not run git commands that change the tree, index or refs (stash, reset, checkout, switch, restore, clean, rebase). Read-only git (status, diff, log, show) is fine.
- Run every test and build through `keel-evidence run` or `keel-verify`, never directly.
- Host conventions: <paths to host CLAUDE.md files>
## Report
Return your report as your final message, in the format of templates/report.md.
```

## Implementer report (the agent's final message, stored as `reports/<unit>.md`)

```markdown
# Report: <unit>
**Status**: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
**Files changed**: <path>, …
**Evidence**: RED seq <n>, GREEN seq <m> (evidence/<unit>/index.tsv); for MUT and refactor units: GREEN or REFACTOR seq <m>
**Triage proposals**: <key> <reason>   (MUT and FIN gap units only; one per line)
**What was done**: <3–6 lines>
**Concerns / blockers / questions**: <only if status ≠ DONE>
```

## Task review (final message, stored as `reviews/<unit>-r<round>.md`)

**Input**: the paths of the brief, `diffs/<unit>.patch`, `evidence/<unit>/` and the report.

```markdown
**Verdict**: PASS | FIX
**Spec compliance**: <each in-scope FR/AS: met | not met (why)>
**RED validity**: <the failing run failed for the right reason: yes | no (why)> (units that need `check`)
**Behavior unchanged**: <yes | no (why)> (`intent=refactor` units only; `no` re-opens the unit as `intent=fix`)
**Test quality**: <tests check behavior traceable to the spec, not implementation details: yes | no (why)>
**Issues**: - [Critical|Important|Minor] <file:line> <issue> — <required fix>
```

- **FIX**: triggered by any Critical or Important issue, by `RED validity: no`, or by
  `Test quality: no`.

## Code review finding (final message, stored as `review/findings-<lens>.md`)

**Input**: the paths of `review/diff.patch`, `review/files.txt`, the spec, the plan, the host
CLAUDE.md files and `test-quality.md`.

```markdown
- **[Critical|Important|Minor]** (confidence <80–100>, scope <in-design|changes-design>) `<file:line>`
  <issue in one or two lines> — <suggested fix>
```

- **Severity**:
  - Critical: wrong behavior, data loss, security, or a broken spec requirement.
  - Important: a likely defect or clear maintainability cost.
  - Minor: style or nit.
- **Confidence**: findings below 80 are not returned.
- **Lenses**:
  - `simplicity`: DRY, needless abstraction, dead code.
  - `correctness`: bugs, edge cases, error handling. It also checks the triage reasons in
    `test-quality.md`.
  - `conventions`: host CLAUDE.md rules and existing patterns.

## Plan review (final message, stored as `plan-review/round-<n>.md` and appended to `plan.md`)

- **Input**: the paths of the spec, the plan, Phase 1 artifacts and the constitution. Rounds after
  the first also get the prior rounds' verbatim output plus a disposition log.
- **Output**: four sections:
  1. Critical flaws.
  2. Missing assumptions.
  3. Revised plan (deltas only).
  4. Verdict: `GO` | `NO_GO`.

## Status handling (orchestrator)

| Status | Action |
|---|---|
| DONE | the per-unit rule (data-model.md §7): `keel-evidence check` where required, then task review |
| DONE_WITH_CONCERNS | same, with the concerns passed to the reviewer |
| NEEDS_CONTEXT | answer from the artifacts and re-dispatch once; still NEEDS_CONTEXT → halt |
| BLOCKED | halt and report |
