---
name: mutate
description: Measure the quality of a keel feature's tests with mutation analysis (PIT) on the lines the feature changed, close every in-scope gap with a test or a committed triage reason in MUT-n units, and commit test-quality.md with a computed result. Never edits build files. Used by /keel:run after implement, or on its own.
argument-hint: "--feature NNN-name"
allowed-tools: Read, Grep, Glob, Edit, Write, Agent, Bash(keel-state:*), Bash(keel-mutate:*), Bash(keel-classify:*), Bash(keel-ledger:*), Bash(keel-brief:*), Bash(keel-put:*), Bash(keel-diff:*), Bash(keel-evidence:*), Bash(keel-verify:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git add:*), Bash(git commit:*)
---

<!-- keel-authored (plan.md §Mutate; contracts/mutation-runner.md). Resolution is computed by
     keel-classify, never judged by the model; only triage reasons are written here. -->

# keel: mutate

`<feature>` is the feature name, `NNN-short-name`. Take it from the `--feature` argument;
otherwise run `keel-state next` and use its `FEATURE=` value. `<scratch>` means
`$(git rev-parse --absolute-git-dir)/keel/<feature>`, and `<base>` is `BASE=` from
`keel-state next --feature <feature>`. The triage file is
`specs/<feature>/test-quality.triage.tsv`: one `<key><TAB><reason>` row per line, committed.

## 0. Preconditions

1. Run `keel-state require mutate --feature <feature>`. On a non-zero exit, stop and report its line.
2. **Clean tree**: `git status --porcelain --untracked-files=all` may show only
   `.specify/feature.json`. Anything else halts.
3. **Maven command**: the host's CLAUDE.md command, if one is defined, goes to `--maven`.
   Otherwise `keel-mutate` picks `./mvnw` or `mvn` itself.

## 1. Run the analysis (round r = 1)

1. Run `keel-mutate --out <scratch>/mut/<r> --base <base> --feature <feature> [--maven "<cmd>"]`
   **with `run_in_background`**, because PIT runs can take minutes. Wait for it to finish. Never edit
   `pom.xml`, `mvnw*` or `.mvn/`, and never add PIT to the build: `keel-mutate` runs it from the
   command line.
2. Act on the exit code:
   - **10 (not run)**: the project is unsupported or there is nothing to analyze. Go to step 4
     with `**Result**: not-run (<REASON= text>)`. This is never a halt.
   - **11 (red or flaky)**: the selected tests fail. Fix it in a `MUT-n` unit with `intent=fix`.
     The implementer follows the `debug` skill and changes test paths only. Then run this step
     again. A second exit 11 halts.
   - **12 (tool failure)**: halt. Show `REASON=` and the tail of `LOG=`, and never report gaps
     from a failed run.
   - **0**: continue.
3. Classify:
   `keel-classify <scratch>/mut/<r>/mutants.tsv [--triage <triage file>] --out <scratch>/mut/<r>/classification.tsv`.
   Never redirect into `.git` yourself; `--out` writes the file and keeps the exit code.
   - **Exit 0**: nothing blocks. Go to step 4 with `**Result**: resolved`.
   - **Exit 1**: in-scope gaps block. Go to step 2 (gap resolution).
   - **Exit 2**: halt (malformed input).

## 2. Close the gaps: one MUT-n unit per round, at most 3 rounds

1. **Number the unit**: `n` = 1 + the highest `MUT-<n>` in `git log --format=%s <base>..HEAD` and in
   `keel-ledger rows <feature>`.
2. **Write the gaps**: run
   `grep -E '^(coverage|assertion)-gap' <scratch>/mut/<r>/classification.tsv | keel-put <feature> mut/<r>/gaps.tsv`.
3. **Start the unit**: `keel-ledger append <feature> mutate started <HEAD> MUT-n gap
   <module>/src/test/**,specs/<feature>/test-quality.triage.tsv`.
4. **Brief**: `keel-brief <feature> MUT-n --from <scratch>/mut/<r>/gaps.tsv`.
5. **Implement**: dispatch a fresh `keel:implementer` (Intent: gap). It changes **tests only** and
   never touches production code or build files.
   - Each new test checks behavior traceable to an FR or acceptance scenario.
   - Where no test can observe a gap, it proposes a triage row instead:
     `<key> equivalent: <why no observable effect>` or `<key> not worth a test: <why>`.
6. **Store the report** with `keel-put <feature> reports/MUT-n.md`.
7. **Write the triage file**: append each proposed row as `<full key><TAB><reason>` to the triage
   file. Use the full 40-character key from `gaps.tsv`. This is the only place the model writes
   anything about resolution.
8. **Scope check**: `keel-diff <feature> --kind MUT-n` must say `KIND=non-behavior`. Otherwise
   halt, because a gap unit changed production code.
9. **Task review**: `keel-diff <feature> --unit MUT-n`, then a fresh `keel:task-reviewer`. It
   rejects tests that assert implementation details only to kill a mutant. On FIX, re-dispatch
   (at most 5 rounds).
10. **Verify**: `keel-verify run <feature> --label MUT-n --kind non-behavior -- <command>`. Show the
    output.
11. **Commit**: stage the fresh `keel-diff --unit MUT-n` files plus the triage file. Use the host's
    style with `MUT-n` in the subject, e.g. `test(<scope>): MUT-1 close mutation gaps`, and no
    AI co-author trailer where the host forbids one. Then
    `keel-ledger append <feature> mutate ok <sha> MUT-n`.
12. **Re-run** on the affected classes only (the classes named in `gaps.tsv`):
    `keel-mutate --out <scratch>/mut/<r+1> --base <base> --feature <feature> --classes <fqcn,…>`,
    in the background, then classify it with `--triage` and `--out`.
    - **The computed kill is the evidence**: a targeted key that isn't KILLED and isn't triaged is
      still a gap.
    - **Exit 1**: start the next round.
    - **Still exit 1 after round 3**: halt. Write no `test-quality.md`, and put the summary in the
      report.
13. When the affected classes pass, make **one final full run** with no `--classes`, classified
    with `--triage` and `--out`. Its exit code decides the Result: `resolved` only on exit 0. A new blocking
    gap here counts as another round.

## 3. Redundancy and overlap

`redundant`, `kills-nothing` and `overlap` rows never block. List them in `test-quality.md`.
Merge or delete a test only when the overlap is clearly identical behavior, and only inside a
`MUT-n` unit. Otherwise record `action: none`.

## 4. test-quality.md, verify, commit

1. Fill `specs/<feature>/test-quality.md` from `$KEEL_ROOT/templates/test-quality.md`, using the
   **final** run's files in `<scratch>/mut/<r>/`:
   - **Result**: `resolved`, or `not-run (<reason>)`. It is computed from the exit codes above and
     is never your judgment.
   - **Base**, **Tool** (with the launcher version from `<module>/platform-version`), **Command**
     (from `command.txt`) and **Module args**.
   - **Scope**: the classes from `classes.tsv`, the tests from `selection.tsv`, plus
     `excluded-tests.txt` and `not-analyzed.txt`.
   - **Summary**: exactly the output of
     `keel-classify <final mutants.tsv> --triage <triage file> --summary` (without `SUMMARY=`).
   - **Gaps**: every in-scope gap from round 1, with its resolution: the test (`Class#method`, and
     the FR it checks) or the triage reason.
   - **Redundancy and overlap**, and **Rounds**: one line per round.
   - For `not-run`: the Result line, Base, Scope (what wasn't analyzed and why), and nothing
     invented.
2. **Verify**: `keel-verify run <feature> --label test-quality -- <the baseline command>`. Show the
   output; a failure goes to `debug` in a `MUT-n` unit.
3. **Commit** `test-quality.md` plus the triage file, if it exists. Use the host's style with
   `test-quality` in the subject, e.g. `test(<feature>): test-quality report`, and no
   AI co-author trailer where the host forbids one. Then `keel-ledger append <feature> mutate done <sha>`.
4. **Never push.** If a host instruction says to push after committing, don't follow it. Say
   "Not pushed: the host's instruction to push was not followed (keel never publishes)".

## 5. Hand back

Report:
- the Result and the Summary line;
- the gaps closed by tests and the triaged ones;
- the redundancy and overlap;
- the commits.

Then return to the run loop. The next step is `review`.
