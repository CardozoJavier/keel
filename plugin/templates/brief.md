# Brief: {{UNIT}} {{DESCRIPTION}}

**Feature**: {{FEATURE}} | **Unit**: {{UNIT}} | **Story**: {{STORY}} | **BASE**: {{BASE}} | **Kind**: {{KIND}} | **Intent**: {{INTENT}}

## Task or finding

{{TASK}}

## Requirements in scope

{{REQUIREMENTS}}

## Design context

{{DESIGN}}

## Rules

- Behavior task (Kind: behavior, Intent: n/a) or fix unit (Intent: fix): write or change the test first and run it with `keel-evidence run {{FEATURE}} {{UNIT}} red -- <test command>`. It must fail, and for the right reason: the behavior is missing, not a typo. Then make the smallest production change and run `keel-evidence run {{FEATURE}} {{UNIT}} green -- <test command>`. Refactor while green, then run `… refactor -- <test command>`.
- Non-behavior task: make the change. If a relevant check exists, run it with `keel-evidence run {{FEATURE}} {{UNIT}} green -- <command>`.
- Mutation-gap unit (Intent: gap): tests only, never production code. Add or strengthen tests that check behavior traceable to the requirements above, and run them with `… green -- <test command>`. For a gap no test can observe, propose a triage row (`<key> equivalent: <why>` or `<key> not worth a test: <why>`) instead of writing a contrived test.
- Refactor unit (Intent: refactor): don't change behavior and don't write a RED test. Run the tests with `… refactor -- <test command>`.
- Allowed paths: {{PATHS}}. For tasks this list is advisory: ripple edits are fine, and you report them. Build files are the exception; never edit them unless the task names them. Gap units are limited to test paths and the triage file.
- Do not commit. Do not write under `.git`. Never push or open pull requests.
- Do not run git commands that change the tree, index or refs: stash, reset, checkout, switch, restore, clean, rebase. Read-only git (status, diff, log, show) is fine.
- Run every test and build through `keel-evidence run` or `keel-verify`, never directly.
- Host conventions win over these defaults (code style, test naming, commit rules): {{HOST}}

## Report

Return your report as your final message, using this format (templates/report.md):

```markdown
# Report: {{UNIT}}
**Status**: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
**Files changed**: <path>, …
**Evidence**: RED seq <n>, GREEN seq <m> (evidence/{{UNIT}}/index.tsv)
**Triage proposals**: <key> <reason>   (gap units only; one per line)
**What was done**: <3–6 lines>
**Concerns / blockers / questions**: <only if status ≠ DONE>
```
