# keel trial results

Trials are non-behavior checks run with real `claude -p --plugin-dir plugin` sessions
(`tests/trials/*.sh`). Each section is the script's own output, appended verbatim.

## Light-path trial (T058), 2026-11-25

- **Repo**: `tests/fixtures/sample-maven` via `scn_sample`; feature `001-price-is-zero`; model `sonnet`.
- **Approvals**: 1 prompt (Gate 1) in session 1; session 2 approved it with the light path.
- **keel-state next**: `STEP=mutate`.
- **Tasks**: 1 of 1 ticked.
- **Commits** (`644842e..HEAD`):

```text
d8bb179 feat(price): T001 add Price.isZero()
06fb651 docs(001-price-is-zero): spec, plan and tasks
```

- **Evidence per task**:
  - `T001` (behavior): evidence check pass; runs (phase:exit) `red:1 green:0 green:0`; verify log present
- **Co-author trailers**: none.
- **Tree**: clean.
- **Questions after Gate 1** (session 2 final message):

```text
The run stopped at `mutate`. The `keel:mutate` skill doesn't exist in this session. It isn't in the skill list, and the Skill tool returned `Unknown skill: keel:mutate`. I didn't skip the step or do it by hand.

**Done so far** (branch `001-price-is-zero`):
- **Gate 1:** approved on the light path.
- **Docs commit:** `06fb651 docs(001-price-is-zero): spec, plan and tasks`. The baseline passed with 0 failing tests.
- **T001:** `d8bb179 feat(price): T001 add Price.isZero()`. It went RED to GREEN, verify passed, and the task review was PASS. It added three tests: 0, 1 and `Long.MAX_VALUE`.
- **Left untracked:** `.specify/feature.json`.
- **Not pushed.** You can run `git push` yourself if you want to.

**To resume:**
- Check that the keel plugin install includes `skills/mutate`. The orchestrator's table lists `keel:mutate`, but the skill list doesn't.
- Once it's available, start a new Claude Code session and run `/keel:run`. It resumes at `mutate`, and `review` and `finish` follow.
```

## test-audit trial (T068): `payment-service` in `payconductor`, 2026-11-25

- **Report**: `keel/audit/20261125T205855/report.md`
- **Summary**: 0 mutants (0 in scope); killed 0; coverage gaps 22; assertion gaps 0; triaged 0; excluded 0`
- **Module args**: `-f payment-service/pom.xml`
- **Commits**: none; **tree**: unchanged.
- **Final message**:

```text
- **Report:** `.git/keel/audit/20261125T205855/report.md`
- **Summary:** `0 mutants (0 in scope); killed 0; coverage gaps 22; assertion gaps 0; triaged 0; excluded 0`
- **Why it reads 0:** `payment-service/src/test` has no files, so PIT never mutated any bytecode. The 22 `NO_TEST` rows in `classification.tsv` are one per class. The "0 mutants" figure contradicts those rows, so use the table, not the summary line.
- **`command.txt`:** it came out empty, so the report doesn't show the exact Maven command.

**Top findings**
- `Payment`, `PaymentStatus` and `Money` have no tests. These are the state transitions and money arithmetic, so they come first.
- `PaymentCommandHandler` has no tests. Cover idempotent command handling, save-then-publish ordering and error paths with in-memory port fakes.
- The five event records have no payload tests.
- `PostgresPaymentRepository` and `KafkaPaymentEventPublisher` need Testcontainers integration tests. Cover optimistic-lock conflicts and the outbox.
- `PaymentController` and the DTOs have no validation or mapping tests. `KafkaConfig` and `PaymentServiceApplication` need only a smoke test.

**Next step:** run `/keel:run` to add domain unit tests for `Money`, `Payment` and `PaymentStatus` first. Then re-run `/keel:test-audit payment-service` to get real mutation results.
```

Follow-up from this trial: the summary line now reads `coverage gaps 22 (22 with no test)` when
classes have no test, and `command.txt` records why PIT was not run (research R7.6).

## standalone trial (T074): `/keel:verify` in `payconductor`, 2026-11-25

- **Guard self-check ran first**: yes
- **Commits**: none; **tree**: unchanged.
- **Final message**:

```text
**The build fails.** `mvn verify` stops at POM resolution, before any module compiles or any test runs.

```
[ERROR] The project io.payconductor:projection-service:1.0.0-SNAPSHOT
        (projection-service/pom.xml) has 1 error
[ERROR] 'dependencies.dependency.version' for
        io.quarkus:quarkus-smallrye-reactive-messaging-kafka:jar is missing.
        @ line 42, column 21
```

- **Exit code:** The `exit=` line printed empty because `PIPESTATUS` is a bash variable and this shell is zsh. The `[ERROR]` output and "could not read 1 project" show that Maven failed.
- **Test results:** There are none, so no test or build claim can be made.
- **Likely cause:** `quarkus-smallrye-reactive-messaging-kafka` has no `<version>` in `projection-service/pom.xml`. The Quarkus BOM import is probably missing from the parent POM's `dependencyManagement`. Your uncommitted change to the root `pom.xml` may be the cause, but I haven't checked.
- **Log:** The full output is in `/tmp/payconductor-verify.log`.

Next step is to check `git diff pom.xml` against the BOM import. I can use `/keel:debug` to confirm the root cause before changing anything. Say if you want that.
```

Follow-up from this trial: standalone verify now runs the command in the foreground and writes no
log outside the repository; this trial had teed it to `/tmp`.

## Standalone capabilities on the sample repositories (T074)

Each capability also ran as a scenario check in a fresh sample repository on 2026-11-25. Each was
confirmed RED against a plugin copy without the skill, then GREEN:

| Capability | Check | Result |
|---|---|---|
| `/keel:debug` | `us6_debug_standalone`: a planted bug (`plus` subtracts) | root cause named, production code fixed, failing test untouched, suite green, nothing committed (8/8) |
| `/keel:verify` | `us6_verify_standalone` | guard first, `mvn` named, "2 run" evidence, no state, nothing committed (7/7) |
| `/keel:respond-review` | `us6_respond_review_standalone`: one wrong and one right comment | the wrong comment declined ("already" uses `addExact`); an overflow test added; suite green (7/7) |
| `/keel:test-audit` | `us6_test_audit_standalone` on maven-weak | report under `.git/keel/audit/`, all three seeded weaknesses named, tree unchanged (8/8) |

## Full-path trial (T080), 2026-11-25

- **Repo**: sample-maven; feature `001-price-discount`; model `sonnet`; wall time 6 min; resumes needed: 0.
- **keel-state next**: `STEP=done`.
- **Gates**: session 1 ended with: …yes**  Choose one: - **Approve** (full path: competing designs at Gate 2, plan review). - **Approve with the light path** (one gate, no competing designs or plan review). - **Tell me what to change.**
  session 2 ended with: …btle split formula. B adds a public type for one caller, and nothing in the spec needs it. Stacking discounts and fractional percentages are out of scope.  Pick A, B or C, or describe your own design.
- **Agents**: explorers 3, architects 3, plan reviewers 1, implementers 3, task reviewers 3, code reviewers 3.
  (distinct top-level Agent dispatches across all sessions)
- **Commits** (`f64696e..HEAD`):

```text
2318004 feat(001-price-discount): implement percentage discount for Price
9ab5916 test(001-price-discount): test-quality report
32f2a80 feat(price): T003 reject percentages outside 0..100
3052d8e feat(price): T002 make Price.discounted overflow-safe
2b6e20b feat(price): T001 add Price.discounted with half-up rounding
53be5c6 docs(001-price-discount): spec, plan and tasks
```

- **Evidence per behavior task**:
  - `T001` (behavior): evidence check pass; verify log present
  - `T002` (behavior): evidence check pass; verify log present
  - `T003` (behavior): evidence check pass; verify log present
- **Test quality**: **Result**: resolved; **Summary**: 16 mutants (13 in scope); killed 13; coverage gaps 0; assertion gaps 0; triaged 0; excluded 0
- **Spec status**: **Status**: Implemented (2026-11-25)
- **Finish verify** (keel-verify stdout): RESULT=pass FAILING=0 NEW=0 TESTS=present (log present)
- **Build files unchanged**: yes
- **Co-author trailers**: none; **tree**: clean; **remote refs**: none (no remote configured; the guard blocks pushes regardless).
- **Permission denials in the sessions (SC-001)**: 0; **Spec Kit CLI or speckit-* skill used (SC-007)**: 0; **speckit skills or commands reachable**: 0.
- **SC-006, Spec Kit reads the artifacts**: check-prerequisites: `{"FEATURE_DIR":"/var/folders/v3/z6rlh_z57yj7sbfj6trt8lh80000gn/T/keeltest.c41pU2/speckit-copy/specs/001-price-discount","AVAILABLE_DOCS":["research.md","data-model.md","quickstart.md","tasks.md"]}`
  `/speckit-analyze`: No critical issues. I only read the artifacts and changed nothing. `.specify/extensions.yml` doesn't exist, so no hooks ran.;- Total requirements: 9 (6 FR, plus SC-001 to SC-003, which need buildable work);- Critical issues: 0;
- **Final message**:

```text
`Price.discounted(int percent)` is implemented and committed on branch `001-price-discount`. The final `mvn -q verify` passes with 0 failing tests. I didn't push.

**What it does**
- It returns the discounted price, rounded half up to the cent, with no overflow even at `Long.MAX_VALUE`.
- A percentage below 0 or above 100 throws `IllegalArgumentException`. It is never clamped.

**Commits** (`f64696e..HEAD`)
- `53be5c6` docs: spec, plan and tasks
- `2b6e20b` T001: discount with half-up rounding
- `3052d8e` T002: overflow-safe arithmetic
- `32f2a80` T003: reject percentages outside 0..100
- `9ab5916` test-quality report
- `2318004` finish (spec marked Implemented)

**Run summary**
- **Path:** full. I passed Gate 1 (spec approval) and Gate 2 (you picked the pragmatic balance design).
- **Plan review:** one round, GO.
- **Test quality:** 13 of 13 in-scope mutants killed, with no gaps. The report lists some redundant and overlapping tests, and I left them in place.
- **Code review:** the simplicity, correctness and conventions reviewers each returned no findings.
- **Re-mutation at finish:** skipped, because no production code changed after the test-quality commit.

**Not pushed.** You can run `git push` yourself when ready. No instruction asked me to publish.

**Caveats**
- I saved the plan-review and task-review outputs as shortened or summarized text. They are not the reviewers' verbatim output, which the skill steps call for.
- I also staged `.specify/feature.json` in the docs commit, which the skill didn't list.
```

An earlier run the same day (feature `001-percent-discount`, 7 min, same outcome) was discarded,
because its script had three counting bugs, fixed before this run:
- **SC-007 showed 1, a false positive.** The raw grep matched keel's own
  `keel-state require specify --feature …`. It is now `scn_speckit_used`, which reads Skill and
  Bash tool calls only and matches `specify` only as a command.
- **The finish line had no RESULT.** keel-verify prints RESULT on stdout, not in the log. It is now
  read from the Bash call's output with `scn_bash_output`.
- **Agent counts were raw stream occurrences.** They are now `scn_dispatches`, summed across
  sessions.

The detect fix showed in this run. `keel-verify detect --host "mvn -q verify"` printed
`TESTFW=junit5`, so no test-setup task was added. The previous run had printed `TESTFW=none` for
the same POM.

Follow-ups from this run's final message:
- The plan-review and task-review outputs were saved summarized, not verbatim.
- `.specify/feature.json` was staged in the docs commit.

### Success criteria (T080)

| SC | Outcome | Evidence |
|---|---|---|
| SC-001 | met | Two approvals: Gate 1 ended session 1, Gate 2 ended session 2. Clarification answers came in the prompt. 0 permission denials in every result event. |
| SC-002 | met | No publish attempted and no remote. The publish-attempt corpus is blocked 100% by `tests/guard/` and the `us2_publish_blocked` scenario. |
| SC-003 | met | The last `keel-verify run` before each task commit printed `RESULT=pass` for T001, T002 and T003. Finish verify printed `RESULT=pass FAILING=0 NEW=0`. |
| SC-004 | met | T001–T003 are behavior tasks. Each evidence check passes (red before, green after). |
| SC-005 | met by the suites | This run needed no resume. Covered by `resume_matrix_test` and the `us4_resume_mid_implementation` scenario. |
| SC-006 | met | Spec Kit's `check-prerequisites` found the feature dir and docs. `/speckit-analyze` reported 0 critical issues, without edits. |
| SC-007 | met | superpowers and feature-dev were disabled. Spec Kit CLI or `speckit-*` skills used: 0. Reachable: 0. |
| SC-008 | met by the scenarios | Memory was off in this run. Covered by `us5_memory_absent` and `us5_memory_keyed`. |
| SC-009 | **pending** | Needs the maintainer's judgment after three real features. |
| SC-010 | met | Light-path trial T058 had 1 approval. Also `us1_light_one_gate` and `us1_no_light_for_contract`. |
| SC-011 | met | Standalone trials (T074), plus the four `us6_*_standalone` scenarios. |
| SC-012 | met | Test quality resolved: 13 of 13 in-scope mutants killed, 0 coverage or assertion gaps. |
| SC-013 | met | `us6_test_audit_standalone` on maven-weak named all three seeded weaknesses. |
| SC-014 | met | Build files unchanged (`pom.xml`, `mvnw`, `.mvn`). |

Still open, interactive only: whether user `!` commands get the session env, and the env after
`/clear`, compaction and fork (quickstart verified-facts table).

## Full-path trial after the verbatim and docs-staging fixes, 2026-11-26

- **Repo**: sample-maven; feature `001-price-discount`; model `sonnet`; wall time 6 min; resumes needed: 0.
- **keel-state next**: `STEP=done`.
- **Gates**: session 1 ended with: …o reverse? | yes | The change is additive |  **Qualifies as small:** yes  Reply **approve**, **approve with the light path** (one gate, no competing designs or plan review), or tell me what to change.
  session 2 ended with: … mirrors the rounding requirement, so exactness and no overflow are easy to check. - Nothing in the spec calls for A's speed or B's extra type.  Reply **A**, **B**, **C**, or describe your own design.
- **Agents**: explorers 3, architects 3, plan reviewers 1, implementers 2, task reviewers 2, code reviewers 3.
  (distinct top-level Agent dispatches across all sessions)
- **Commits** (`a439579..HEAD`):

```text
c0a4e21 feat(001-price-discount): implement percentage price discount
106e32c test(001-price-discount): test-quality report
9d1d160 feat(price): T002 reject discount percentages outside 0..100
938d430 feat(price): T001 add rounded percentage discount to Price
d8545f5 docs(001-price-discount): spec, plan and tasks
```

- **Evidence per behavior task**:
  - `T001` (behavior): evidence check pass; verify log present
  - `T002` (behavior): evidence check pass; verify log present
- **Test quality**: **Result**: resolved; **Summary**: 9 mutants (6 in scope); killed 6; coverage gaps 0; assertion gaps 0; triaged 0; excluded 0
- **Spec status**: **Status**: Implemented (2026-11-26)
- **Finish verify** (keel-verify stdout): RESULT=pass FAILING=0 NEW=0 TESTS=present (log present)
- **Agent outputs stored by the session itself** (must be 0): 0; **by the agents**: 8 (background agents' calls are not in the stream).
- **Commits touching `.specify/feature.json`**: none (the script printed an empty value here; fixed since. `git log a439579..HEAD -- .specify/feature.json` is empty)
- **Build files unchanged**: yes
- **Co-author trailers**: none; **tree**: clean; **remote refs**: none (no remote configured; the guard blocks pushes regardless).
- **Permission denials in the sessions (SC-001)**: 0; **Spec Kit CLI or speckit-* skill used (SC-007)**: 0; **speckit skills or commands reachable**: 0.
- **SC-006, Spec Kit reads the artifacts**: check-prerequisites: `{"FEATURE_DIR":"/var/folders/v3/z6rlh_z57yj7sbfj6trt8lh80000gn/T/keeltest.TB371C/speckit-copy/specs/001-price-discount","AVAILABLE_DOCS":["research.md","data-model.md","quickstart.md","tasks.md"]}`
  `/speckit-analyze`: - Total requirements: 9 (5 FR, 4 SC);- Critical issues: 0;
- **Final message**:

```text
**`001-price-discount` is done: `Price.discounted(int percent)` is implemented and committed locally. Not pushed.**

**Your actions**
- Run `git push` yourself when you're ready; no host instruction asked for publishing.
- `.specify/feature.json` is still untracked; keel leaves it out of its commits.

**Behavior**
- Returns the price reduced by 0 to 100 percent, rounded half up to the cent, including for the largest possible price.
- Any other percentage throws `IllegalArgumentException("percent must be between 0 and 100")`.

**Commits** (`a439579..HEAD`)
- `d8545f5` docs(001-price-discount): spec, plan and tasks
- `938d430` feat(price): T001 add rounded percentage discount to Price
- `9d1d160` feat(price): T002 reject discount percentages outside 0..100
- `106e32c` test(001-price-discount): test-quality report
- `c0a4e21` feat(001-price-discount): implement percentage price discount

**Gates (full path)**
- Gate 1: you approved the spec.
- Gate 2: you picked the pragmatic balance design (`BigDecimal`, `int` parameter).
- Plan review: GO in round 1. Its wording correction is fixed, and its task-coverage points went into `tasks.md`.

**Quality**
- **Tests first:** both tasks have recorded failing-then-passing runs and passed task review.
- **Mutation testing:** resolved; 9 mutants (6 in scope), all 6 killed, no gaps.
- **Redundant tests:** 7 tests in `PriceTest` are flagged as overlapping with the others. This doesn't block, and I kept them all.
- **Code review:** no findings from the simplicity, correctness or conventions reviewers, so no fix commits.
- **Re-mutation:** skipped, because no production code changed after the test-quality commit.

**Final verify**
- `mvn -q verify` passed with 0 failures; the surefire report shows 34 tests in `shop.PriceTest`.
- Log: `.git/keel/001-price-discount/verify/finish.log`

**Process note**
- T001 asked for a stub before the first failing test, which conflicts with keel's test-first check. The implementer recorded a failing run both before and after the stub, and the check passed.

No patches were recovered, the branch isn't stacked, and no tasks were committed by hand.
```

The rerun checks the two follow-ups from the 2026-11-25 run:
- **Verbatim outputs.** The session stored 0 agent outputs itself; the agents stored 8 with
  `keel-put`. Stored sizes are now 2,120 chars for plan-review round 1 (638 before), 746 and 828
  for the task reviews (5 to 38 before), and 1,414 and 684 for the reports (237 to 386 before).
  `keel-plan-round` put round 1 into `plan.md` byte for byte, and the session filled in its
  dispositions.
- **Docs staging.** `keel-branch stage-docs` staged the docs commit, and no commit touches
  `.specify/feature.json`.

The `us2_implement_red_green` scenario confirms the verbatim fix. Against the previous plugin it
failed (`main reports/T001.md; main reviews/T001-r1.md`); with the fix it passes 13/13.
