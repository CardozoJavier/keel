# Test Quality: 001-spec-to-commit-flow
**Result**: resolved
**Base**: 8db2ef7..HEAD (feature branch `001-spec-to-commit-flow`) | **Tool**: `tests/mutation-self-check.sh` (sed mutants; PIT doesn't apply to bash)
**Command**: `tests/mutation-self-check.sh` | **Module args**: n/a (bash scripts; each mutant runs against a copy of the repository)
**Scope**: the scripts whose failure would publish code or misreport the run's state: `plugin/shims/git`, `plugin/shims/gh`, `plugin/hooks/guard-push.sh`, `plugin/bin/keel-classify`, `plugin/bin/keel-state`, `plugin/bin/keel-evidence`; tests: their suites under `tests/guard/` and `tests/scripts/` plus `tests/scripts/resume_matrix_test.sh`; not analyzed: skills and agents (prompt text, covered by `tests/scenarios/`)
**Summary**: 16 mutants (16 in scope); killed 16; coverage gaps 0; assertion gaps 0; triaged 0; excluded 0

PIT measures JVM bytecode and doesn't apply to keel's bash. The equivalent is hand-written mutants,
each removing one decision the specification depends on. Each one is applied to a copy of the
repository, and the suite that owns the behavior must fail. Skills and agents are prompt text; their
behavior is checked by scenario sessions (`tests/scenarios/`, research R7.3). Each was confirmed
RED before its skill existed or against a plugin copy without the skill; the US1 checks were
confirmed RED in their earlier `claude plugin eval` form.

## Gaps (in scope)

| Key | Location | Mutator | Status | Resolution |
|---|---|---|---|---|
| M07 | guard-push.sh `path_check` | drop "PATH replaced without keel's shims" (B2) | SURVIVED in round 1 | test: deny case `PATH=/keel-no-such-dir git push` in `tests/guard/hook/cases/deny.txt` (push-guard B2). The existing case was also denied by the tool-location rule, so the PATH-replacement rule had no test of its own |
| M15 | keel-evidence `check` | a red run that passed counts as RED | SURVIVED in round 1 | test: `T009` in `tests/scripts/keel-evidence_test.sh`, where a passing red run plus GREEN must report `MISSING=red-before-green` (run-state contract, check rule 1) |

## Mutants (all killed after round 2)

| ID | Script | What the mutant breaks | Killed by |
|---|---|---|---|
| M01 | shims/git | `git push` no longer denied (A1) | guard/shims/git_test |
| M02 | shims/git | `git svn set-tree` allowed (A2) | guard/shims/git_test |
| M03 | shims/git | `git -c` with a protected key allowed (A8) | guard/shims/git_test |
| M04 | shims/gh | `gh pr create` allowed (A4) | guard/shims/gh_test |
| M05 | shims/gh | `gh api` with `state=open` allowed (A5) | guard/shims/gh_test |
| M06 | hooks/guard-push.sh | layer B allows what it means to deny | guard/hook/shell_test, mcp_test |
| M07 | hooks/guard-push.sh | PATH replaced without the shims allowed (B2) | guard/hook/shell_test (new case) |
| M08 | bin/keel-classify | gaps no longer block | scripts/keel-classify_test |
| M09 | bin/keel-classify | scope inverted | scripts/keel-classify_test |
| M10 | bin/keel-classify | every killing test reported redundant | scripts/keel-classify_test |
| M11 | bin/keel-state | review is skipped | keel-state_test, resume_matrix_test |
| M12 | bin/keel-state | an uncommitted Analyzed line counts | keel-state_test, resume_matrix_test |
| M13 | bin/keel-state | an uncommitted Implemented counts as done | keel-state_test, resume_matrix_test |
| M14 | bin/keel-evidence | RED with a production change accepted | scripts/keel-evidence_test |
| M15 | bin/keel-evidence | a passing run counts as RED | scripts/keel-evidence_test (new case) |
| M16 | bin/keel-evidence | GREEN-only evidence accepted | scripts/keel-evidence_test |

## Redundancy and overlap (not blocking)

- Not measured for bash: the suites have no per-test kill matrix. The resume matrix and
  `keel-state_test` deliberately overlap on M11–M13. The matrix checks resume behavior, and
  `keel-state_test` checks derivation row by row. action: none.

## Rounds

1. 2026-11-25: 16 mutants; 2 survived (M07, M15); 8 hadn't applied at first because of a
   field-separator bug in the self-check, which was fixed.
2. 2026-11-25: 2 tests added; 16 of 16 killed; nothing triaged (`tests/mutation-self-check.triage`
   is empty).
