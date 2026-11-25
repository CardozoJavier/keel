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
