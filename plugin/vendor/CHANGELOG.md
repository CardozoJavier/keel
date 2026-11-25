# Vendor change log

Every in-place edit to a vendored file is recorded here (constitution, Development Workflow).
Files not listed are verbatim copies of the upstream version named in `PROVENANCE.md`.

| Date | File | Change | Reason |
|---|---|---|---|
| 2026-11-25 | speckit/templates/spec-template.md | Added `**Path**` and `**Base**` header lines and a `## Change Classification` section | keel light path (FR-028) and feature identity/base derivation (data-model §1, §3) |
| 2026-11-25 | speckit/templates/plan-template.md | Added `**Plan status**` header line, `## Design Decision` and `## Plan Review` sections | Gate 2 record (FR-009), plan review rounds (FR-010), state derivation (data-model §2) |
| 2026-11-25 | speckit/templates/tasks-template.md | Tests changed from OPTIONAL to REQUIRED with the behavior-task-carries-its-test rule; `**Analyzed**` line note | Constitution Principle V; analyze evidence (data-model §2) |

## Derived files (outside `vendor/`)

Each file below carries an `Adapted from <upstream> <version> <path>` header naming its vendored
source; feature-dev derivatives also carry an Apache-2.0 §4(b) change notice.

| Date | File | Source | Main changes |
|---|---|---|---|
| 2026-11-25 | skills/constitution, specify, clarify, plan, tasks, analyze, implement | speckit commands/* | keel-state preconditions instead of scripts; no extension hooks; keel gates, markers and work units |
| 2026-11-25 | agents/explorer.md, agents/architect.md | feature-dev agents/code-explorer.md, code-architect.md | read-only tools; one focus or lens per dispatch; fixed report formats |
| 2026-11-25 | agents/code-reviewer.md | feature-dev agents/code-reviewer.md + superpowers requesting-code-review severity calibration | one lens per dispatch; scope tag in-design/changes-design; templates/finding.md |
| 2026-11-25 | skills/tdd | superpowers test-driven-development (+ writing-good-tests.md) | runs through keel-evidence; Java/JUnit examples; compile-failure RED rule; report statuses instead of human escalation |
| 2026-11-25 | skills/debug | superpowers systematic-debugging | handoffs and human-partner wording removed; 3-failed-fixes stop is a reported halt |
| 2026-11-25 | skills/verify | superpowers verification-before-completion | keel-verify detect/run; no PR or push wording |
| 2026-11-25 | skills/respond-review | superpowers receiving-code-review | GitHub reply section removed; every comment ends applied, declined or needs-input |
| 2026-11-25 | agents/implementer.md, agents/task-reviewer.md | superpowers subagent-driven-development implementer-prompt.md, task-reviewer-prompt.md | keel briefs and evidence; no commits; PASS/FIX verdict with RED validity and behavior-unchanged |
