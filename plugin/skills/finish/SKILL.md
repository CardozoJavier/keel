---
name: finish
description: Finish a keel feature - re-mutate production changes made after the test-quality commit, run the full host build and tests with the output shown, fix failures in FIN-n units, then set the spec's Status to Implemented in the FINISH commit (host commit style, no AI co-author trailer where forbidden), save the decision summary to memory when available, and report. Never pushes. Used by /keel:run, or on its own.
argument-hint: "--feature NNN-name"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Edit, Agent, Bash(keel-ledger:*), Bash(keel-brief:*), Bash(keel-put:*), Bash(keel-diff:*), Bash(keel-evidence:*), Bash(keel-verify:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git add:*), Bash(git commit:*), Bash(keel-mutate:*), Bash(keel-classify:*)
---

<!-- keel-authored (plan.md §Finish), with superpowers' verification-before-completion gate
     (MIT, via skills/verify). -->

# keel: finish

`<feature>` is the feature name, `NNN-short-name`. Take it from the `--feature` argument;
otherwise run `keel-state next` and use its `FEATURE=` value. `<base>` is `BASE=` from
`keel-state next --feature <feature>`.

## 0. Preconditions

1. Run `keel-state require finish --feature <feature>`. On a non-zero exit, stop and report its
   line.
2. **Clean tree**: only `.specify/feature.json` may show in `git status --porcelain
   --untracked-files=all`.

## 1. Re-mutation (SC-012)

1. Find the test-quality commit: `git log -1 --format=%H --diff-filter=A --
   specs/<feature>/test-quality.md`.
2. List the production files changed since then:
   `git diff --name-only <tq-commit> HEAD -- 'src/main/**'`, or the language's equivalent
   production paths.
3. **None**: skip this step and say so.
4. **Some**:
   - Run `keel-mutate --out <scratch>/mut/fin-<k> --base <base> --feature <feature> --classes <changed
     classes (FQCN)>` **in the background** (contracts/mutation-runner.md).
   - Classify it with
     `keel-classify <out>/mutants.tsv --triage specs/<feature>/test-quality.triage.tsv --out <out>/classification.tsv`.
   - Resolve the gaps exactly as the `mutate` step does, in `FIN-n` gap units: test paths only (or
     triage rows), each with an implementer, a task review, `keel-verify` and a commit.
   - Show the new triage rows to one scoped `keel:code-reviewer` correctness pass.
   - A `not-run` result (exit 10) is skipped and reported, never a halt. Exit 11 goes to `debug` in
     a `FIN-n` unit (`intent=fix`). Exit 12 halts.
   - Keep the `--summary` line and the resolutions for the re-mutation section of
     `test-quality.md` (step 3).

## 2. Full verify

1. Run `keel-verify run <feature> --label finish -- <the baseline command>`. That command is the
   host's CLAUDE.md command or `keel-verify detect`'s `TESTCMD=`, and must match the baseline's.
2. **Show the developer** the `RESULT=`, `FAILING=` and `NEW=` lines and the tail of the log.
3. **On failure**:
   - Fix it in `FIN-n` units (`intent=fix`, numbered like `REV-n` from subjects and ledger):
     `keel-ledger … started`, then `keel-brief … --from <the verify log>`, a fresh implementer
     following the `debug` skill (RED may be the already-failing test), `keel-evidence check`,
     task-reviewer (`Store as: reviews/FIN-n-r<k>.md`), `keel-verify`, the commit, and `ok`.
   - A fix that touches production code gets one scoped `keel:code-reviewer` pass
     (`Store as: review/scoped-FIN-n.md`) on
     `keel-diff --unit FIN-n`. An in-design finding becomes another `FIN-n`; `changes-design`
     halts. Then go back to step 1 for the classes the fix touched.
   - **Caps**: at most 3 `FIN-n` units of each kind (gap, verify fix, scoped-review finding), at
     most 3 attempts on one failure, and at most 6 passes through steps 1–2. Exceeding any cap
     halts.

## 3. The FINISH unit

1. **Clean tree**: again, only `.specify/feature.json`. The step 2 verify must have run on the
   current HEAD; otherwise run it again.
2. Run `keel-ledger append <feature> finish started <HEAD> FINISH n/a
   specs/<feature>/spec.md,specs/<feature>/test-quality.md`.
3. In `spec.md`, replace the `**Status**:` line with `**Status**: Implemented (<YYYY-MM-DD>)`.
   Leave the `**Path**` and `**Base**` lines as they are.
4. If step 1 ran, append its re-mutation section to `test-quality.md`.
5. **Commit** both files, staging them by path, in the **host's commit style**. **The subject must
   contain the feature number `NNN`** (data-model.md §3), for example
   `feat(<feature>): implement <short title>`. `FINISH` alone is not enough.
   - Never add an AI co-author trailer where the host forbids one.
   - The step 2 verify you showed is this commit's evidence.
6. Run `keel-ledger append <feature> finish ok <sha> FINISH`.

## 4. Memory (optional, FR-025)

This is the second and last memory save for the feature.

- **If engram's `mem_save` is available**: save one memory with `topic_key: keel/<feature>` and
  `type: decision`. It holds the outcome, the chosen design, the commits, and the test-quality and
  review summaries. The same key updates the plan-time memory instead of adding a copy.
  - If the response says `judgment_required`, call `mem_judge` **once per candidate**, without
    asking the developer. Pass the candidate's `judgment_id`, relation `related` (or `compatible`),
    and a one-line reason.
- **If it isn't available**: skip it, and don't mention memory in the final report.
- **If a call fails**: continue, and add "memory: <tool> failed: <error>" to the final report.
- Never call `mem_session_*` tools.

## 5. Final report

- The feature branch and the commits in `<base>..HEAD` (`git log --oneline`).
- The gates passed and the path.
- The test-quality summary, the review summary and the finish verify result.
- **"Not pushed."** keel never publishes; the developer can run `git push` themselves.
- **Any host instruction to push or publish that was not followed**, quoted.
- Saved partial patches, tasks committed by the developer after a halt, and any step that was
  skipped (e.g. re-mutation not run).
