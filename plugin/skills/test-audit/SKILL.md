---
name: test-audit
description: Audit how well a Maven module's tests catch bugs, with mutation analysis (PIT) on every class in the module or the ones given - coverage gaps, weak assertions, tests that kill nothing, duplicate tests - outside any feature run. Read-only for the project; the report goes to .git/keel/audit/<timestamp>/report.md. Use as "/keel:test-audit <module> [fqcn,…]".
argument-hint: "<module path> [<fully qualified class>,…]"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Bash(keel-mutate:*), Bash(keel-classify:*), Bash(keel-put:*), Bash(git rev-parse:*), Bash(date:*)
---

<!-- keel-authored (plan.md §Standalone capabilities; contracts/mutation-runner.md audit mode). -->

# keel: test-audit

You audit the tests of **one Maven module**: the path given as the first argument (`.` for a
single-module project). An optional second argument limits the audit to some classes.

## 0. Preconditions

Run `keel-state guard`. On a non-zero exit, stop and report it. A feature run isn't needed, and
this skill writes no feature state.

## Rules

- **Read-only for the project.**
  - Never edit `pom.xml`, `mvnw*`, `.mvn/` or any source or test file, and never commit.
  - `keel-mutate` runs PIT from the command line with pinned versions, so there's nothing to add to
    the build.
- **Raw output and the report live under `.git/keel/audit/<ts>/`.**
  - They are written only by keel's scripts: `keel-mutate --out`, `keel-classify --out` and
    `keel-put --audit`.
  - Never redirect into `.git` yourself, and never use the Write tool there.

## Steps

1. Set `ts=$(date +%Y%m%dT%H%M%S)` and `out=$(git rev-parse --absolute-git-dir)/keel/audit/$ts`.
2. Run `keel-mutate --out <out> --module <module> [--classes <fqcn,…>] [--maven "<host command>"]`
   **with `run_in_background`**, and wait for it to finish.
   - **Exit 10**: report "not run" with its `REASON=`, for example a JUnit 4-only module. Stop.
   - **Exit 11**: the module's tests fail or are flaky. Report it with the log path. Stop.
   - **Exit 12**: a tool failure. Report `REASON=` and the log tail, and never report gaps from a
     failed run. Stop.
3. Run `keel-classify <out>/mutants.tsv --out <out>/classification.tsv`. Then run
   `keel-classify <out>/mutants.tsv --summary` for the summary line.
4. **Write the report** with
   `keel-put --audit <ts>/report.md <<'KEEL_EOF' … KEEL_EOF`. It contains:
   - **Module, command and scope**: from `<out>/command.txt`, `classes.tsv`, `selection.tsv` and
     `excluded-tests.txt`.
   - **Summary**: the `--summary` line.
   - **Coverage gaps and assertion gaps**: grouped by class, as `Class:line`, method and mutator.
     Each with a one-line reading of what a test would need to check. That reading is a
     suggestion; write no test here.
   - **Tests that kill nothing**, **redundant tests** and **overlapping tests** (duplicates).
   - **Excluded mutants**, with their counts.
5. **Reply**: give the developer the report path, the summary line and the five most important
   findings. Suggest the next step, for example a keel feature or a focused change, but don't
   start it.
