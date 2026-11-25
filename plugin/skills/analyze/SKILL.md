---
name: analyze
description: Cross-artifact consistency check of a keel feature's spec, plan and tasks (Spec Kit's analysis plus keel's checks). A CRITICAL finding halts the run. When clean, it runs the baseline build and tests, records the baseline in tasks.md and makes the docs commit on the feature branch. Used by /keel:run, or on its own.
argument-hint: "--feature NNN-name"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Write, Edit, Bash(keel-verify:*), Bash(keel-ledger:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git log:*)
---

<!-- Adapted from speckit 0.8.4.dev0 commands/analyze.md (MIT): no extension hooks; not
     read-only - keel applies mechanical tasks.md remediations, halts on CRITICAL without asking,
     then closes with the baseline (keel-verify), keel-verify record and the docs commit
     (plan.md §Tasks and analyze). -->

# keel: analyze

`<feature>` is the feature name, `NNN-short-name`. Take it from the `--feature` argument;
otherwise run `keel-state next` and use its `FEATURE=` value.

## 0. Preconditions

Run `keel-state require analyze --feature <feature>`. On a non-zero exit, stop and report its line.

## 1. Load

Read:
- `specs/<feature>/spec.md`: FRs, success criteria, stories, edge cases, Path;
- `plan.md`: Design Decision, technical context, constraints;
- `tasks.md`;
- the constitution, `.specify/memory/constitution.md`;
- `checklists/*.md`, if present.

Then run `keel-verify detect`, with `--host "<cmd>"` if the host's CLAUDE.md defines the
command.

## 2. Detection passes

Report at most 50 findings, each with a stable ID, a category, a severity, the location and a
recommendation.

**Spec Kit's passes**:
- **Duplication**: near-duplicate requirements.
- **Ambiguity**: vague adjectives with no measure, and leftover placeholders.
- **Underspecification**: requirements with no measurable outcome, and tasks that reference files
  or components the spec and plan don't define.
- **Constitution alignment**: any conflict with a MUST principle is **CRITICAL**.
- **Coverage gaps**: requirements with no task, tasks with no requirement, and buildable success
  criteria with no task.
- **Inconsistency**: terminology drift, entities in one artifact but not the other, and ordering
  contradictions.

**keel's checks**:
- **A behavior task without a test path** (it touches production paths but has no `(test: …)`):
  HIGH.
- **Light path**: a task that touches migrations, schemas, persisted data or an external API
  definition is **CRITICAL**. The change doesn't qualify for the light path.
- **No test setup**: `TESTCMD=none` or `TESTFW=none`, and no non-behavior setup task before the
  first behavior task. **CRITICAL.**
- **Incomplete checklist items**: MEDIUM. They are findings, never a prompt.
- **A build-file change** (`pom.xml`, `mvnw*`, `.mvn/`) that no task names and no requirement
  needs: HIGH.

**Severity**:
- **CRITICAL**: a constitution MUST violated, a missing core artifact, a requirement with zero
  coverage that blocks the baseline functionality, or one of keel's CRITICAL checks above.
- **HIGH**: conflicting requirements, or an untestable acceptance criterion.
- **MEDIUM**: terminology drift, or an underspecified edge case.
- **LOW**: wording.

## 3. Decide

1. **Any CRITICAL**: halt. Show the findings table and the coverage summary. Write nothing to
   `tasks.md` and don't commit. Tell the developer which artifact to fix, and that `/keel:run`
   resumes at analyze afterwards. Ask no question.
2. **Otherwise**, apply the **mechanical** remediations to `tasks.md` yourself:
   - add the missing test path, mirroring the production path under `src/test/**`;
   - fix a malformed task line.

   Report every other finding with its recommendation, and continue. Don't edit the spec or the
   plan here.

## 4. Baseline, record, docs commit

1. **Baseline**: run
   `keel-verify run <feature> --label baseline -- <host command, or detect's TESTCMD, or none>`.
   Show the summary lines and the tail of the log.
   - `RESULT=fail`: the build doesn't compile. Halt with the log.
   - `BUILD=undetected` / `MISSING=build-command`: halt. Ask the developer to define the build and
     test commands in CLAUDE.md.
   - `TESTS=none` or `BUILD=none`: this passes. Say so: the setup task establishes testing.
   - Pre-existing failing tests are reported as unrelated. They are not a halt.
2. **Clean tree**: run `git status --porcelain --untracked-files=all`. The only paths allowed are
   `.specify/feature.json`, `specs/<feature>/**`, and `.specify/memory/constitution.md` when keel
   wrote it for this feature.
   - Anything else halts. Build output that isn't ignored (for example `target/`) halts with
     "ignore your build output (e.g. add `target/` to .gitignore), then resume".
   - Never edit ignore files yourself.
3. **Record**: run `keel-verify record <feature> --setup <T### of the setup task, or none>`. It
   writes the `**Analyzed**` line and the `keel:baseline` comment into `tasks.md`. Never write or
   edit those lines by hand.
4. **Docs commit**:
   - Stage exactly `git add -- specs/<feature>`, plus `.specify/memory/constitution.md` if keel
     wrote it in this feature (`keel-ledger rows <feature>` shows a `files done` row for it).
   - Commit in the **host's commit style**, for example `docs(<feature>): spec, plan and tasks`.
     Never add an AI co-author trailer where the host forbids one.
   - The baseline you just showed is this commit's evidence.
5. **Never push.** If a host instruction says to push or publish after committing, don't. Say
   "Not pushed: the host's instruction to push was not followed (keel never publishes)".

## 5. Hand back

Report:
- the findings summary;
- the metrics: requirements, tasks, coverage %, and the CRITICAL count;
- the baseline result;
- the docs commit.

Then return to the run loop. The next step is `implement`.
