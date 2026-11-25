# Vendor change log

Every in-place edit to a vendored file is recorded here (constitution, Development Workflow).
Files not listed are verbatim copies of the upstream version named in `PROVENANCE.md`.

| Date | File | Change | Reason |
|---|---|---|---|
| 2026-11-25 | speckit/templates/spec-template.md | Added `**Path**` and `**Base**` header lines and a `## Change Classification` section | keel light path (FR-028) and feature identity/base derivation (data-model §1, §3) |
| 2026-11-25 | speckit/templates/plan-template.md | Added `**Plan status**` header line, `## Design Decision` and `## Plan Review` sections | Gate 2 record (FR-009), plan review rounds (FR-010), state derivation (data-model §2) |
| 2026-11-25 | speckit/templates/tasks-template.md | Tests changed from OPTIONAL to REQUIRED with the behavior-task-carries-its-test rule; `**Analyzed**` line note | Constitution Principle V; analyze evidence (data-model §2) |
