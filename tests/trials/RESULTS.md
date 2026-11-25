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
