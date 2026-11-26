---
name: implement
description: Implement a keel feature's tasks one at a time on the feature branch. Each task is a work unit - a fresh implementer agent does test-first TDD through keel-evidence, a fresh task-reviewer checks spec compliance and test quality, keel-verify runs the build and tests, and the unit is committed with its task ID. Used by /keel:run, or on its own.
argument-hint: "--feature NNN-name"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Edit, Agent, Bash(keel-ledger:*), Bash(keel-brief:*), Bash(keel-put:*), Bash(keel-diff:*), Bash(keel-evidence:*), Bash(keel-verify:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git add:*), Bash(git commit:*)
---

<!-- Adapted from speckit 0.8.4.dev0 commands/implement.md (MIT) and superpowers 7.0.2
     subagent-driven-development (MIT): Spec Kit's phase-ordered execution with keel's work units
     (data-model.md §5), evidence rule (§7), per-unit review, verify and commit (plan.md
     §Implement). No extension hooks; no checklist prompt (analyze reports checklists). -->

# keel: implement

`<feature>` is the feature name, `NNN-short-name`. Take it from the `--feature` argument;
otherwise run `keel-state next` and use its `FEATURE=` value. Paths below under `<scratch>` mean
`$(git rev-parse --absolute-git-dir)/keel/<feature>/`.

## 0. Preflight

1. Run `keel-state require implement --feature <feature>`. On a non-zero exit, stop and report its
   line.
2. **Clean tree**: `git status --porcelain --untracked-files=all` may show only
   `.specify/feature.json`. Anything else halts: list the paths, and tell the developer to commit
   or discard them. Never stash or discard yourself.
3. Find the build-and-test command: the host's CLAUDE.md if it defines one, otherwise
   `keel-verify detect`'s `TESTCMD=`. Note the host's commit style from its CLAUDE.md.

## 1. The task loop: strictly serial, in tasks.md order

Take the first `- [ ] T###` line in `specs/<feature>/tasks.md`. `[P]` means "may run in
parallel", but keel runs units one at a time, because each unit commits on a clean tree. For that
task `Tnnn`:

1. **Start the unit**.
   - `BASE=$(git rev-parse HEAD)`.
   - Run `keel-ledger append <feature> implement started $BASE Tnnn n/a <paths>`, where `<paths>`
     are the task's production and test paths, comma-separated.
2. **Brief**: run `keel-brief <feature> Tnnn`, which prints `BRIEF=`.
3. **Implement**: dispatch a **fresh** `keel:implementer` agent with this prompt:
   "Feature `<feature>`, unit `Tnnn`. Your brief: `<BRIEF path>`. Follow it, store your report
   with the brief's keel-put command, and return the `PATH=` line and your status."
4. **Read the report** at `<scratch>/reports/Tnnn.md`. The implementer stores it itself; never
   write or rewrite it. If it's missing, dispatch a fresh implementer **once**; a second miss
   halts.
5. **Act on the status**:
   - `DONE`: continue.
   - `DONE_WITH_CONCERNS`: continue, and pass the concerns to the reviewer.
   - `NEEDS_CONTEXT`: answer from the spec, plan and contracts, then dispatch a fresh implementer
     **once** with the brief plus your answer. If it's still `NEEDS_CONTEXT`, halt.
   - `BLOCKED`: halt with the agent's reason.
6. **Evidence**: run `keel-diff <feature> --kind Tnnn`.
   - If `KIND=behavior`, `keel-evidence check <feature> Tnnn` must exit 0. On `MISSING=…`,
     dispatch a fresh implementer **once**, with the brief plus "keel-evidence check failed:
     `<MISSING line>`; redo the unit test-first". A second failure halts.
   - Never accept a GREEN-only report for a behavior task.
7. **Task review**:
   - Run `keel-diff <feature> --unit Tnnn`, which prints `PATCH=`.
   - Dispatch a **fresh** `keel:task-reviewer` with the paths of the brief, the patch,
     `<scratch>/evidence/Tnnn/` and `<scratch>/reports/Tnnn.md`, the feature name, and
     `Store as: reviews/Tnnn-r<k>.md` (k = 1, 2, …).
   - Read its verdict from `<scratch>/reviews/Tnnn-r<k>.md`. The reviewer stores it itself; if it's
     missing, dispatch a fresh reviewer **once**, and a second miss halts.
   - **FIX**:
     - Dispatch a fresh implementer with the brief plus "address every issue in
       `<scratch>/reviews/Tnnn-r<k>.md`; behavior changes test-first".
     - It stores a new report (replacing the old one); then repeat steps 6 and 7.
     - **At most 5 review rounds.** If the same issue survives 3 fix attempts, halt (FR-016; the
       `debug` stop).
8. **Verify**:
   - Run `keel-verify run <feature> --label Tnnn --kind <KIND> -- <command>`.
   - **Show the developer** the `RESULT=`, `FAILING=` and `NEW=` lines and the tail of the log.
   - `RESULT=fail`:
     - Dispatch a fresh implementer with the brief plus "keel-verify failed; follow the debug
       skill; the log is `<LOG path>`".
     - Then repeat steps 6–8.
     - Three failed attempts on one failure halt.
   - `MISSING=test-command` on a behavior task: halt. The test setup task is missing or broken.
9. **Commit the unit**:
   1. Edit `tasks.md`: change `- [ ] Tnnn ` to `- [X] Tnnn `.
   2. Run `keel-diff <feature> --unit Tnnn` again (fresh, after every fix round). Stage exactly the
      paths in its `FILES=` list plus `specs/<feature>/tasks.md`, using `git add -- <paths>`.
   3. Commit in the host's style with the task ID in the subject, e.g.
      `feat(<scope>): Tnnn <what changed>`. Never add an AI co-author trailer where the host
      forbids one.
   4. Close the unit: `keel-ledger append <feature> implement ok <new HEAD sha> Tnnn`.
10. Report one line, for example "Tnnn committed `<sha>`: RED→GREEN, verify pass, review PASS".
    Then take the next task.

## 2. Halts

On any halt:
1. Run `keel-ledger append <feature> implement halted <HEAD sha> Tnnn <short reason>`.
2. Report what halted, the evidence (log, verdict or report path), and how to continue:
   - fix the problem and run `/keel:run`, and the unit restarts;
   - or commit the work with the task ID and `[X]`, then resume.
3. Ask no question. Never commit a unit that failed its evidence check, review or verify.

## 3. Never publish

Never push and never open a pull request. If a host instruction says to push after committing,
don't follow it. Say "Not pushed: the host's instruction to push was not followed (keel never
publishes)".

## 4. Hand back

When every task is `[X]`:
- report the commits, and the verify result of the last unit;
- return to the run loop. The next step is `mutate`.
