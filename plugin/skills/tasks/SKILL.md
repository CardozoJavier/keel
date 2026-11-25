---
name: tasks
description: Generate a keel feature's tasks.md (Spec Kit format) from its approved spec and plan. Tasks are test-first, small, dependency-ordered and carry [P] markers; every behavior task names its test path, and a test-setup task is added when the repo has no test command or framework. Used by /keel:run, or on its own.
argument-hint: "--feature NNN-name"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Write, Edit, Bash(keel-verify:*)
---

<!-- Adapted from speckit 0.8.4.dev0 commands/tasks.md (MIT): no extension hooks; no
     check-prerequisites script (keel-state require); keel's test-setup rule (keel-verify detect)
     and behavior-task format (data-model.md §3); tests are REQUIRED (constitution V). -->

# keel: tasks

`<feature>` is the feature name, `NNN-short-name`. Take it from the `--feature` argument;
otherwise run `keel-state next` and use its `FEATURE=` value.

## 0. Preconditions

Run `keel-state require tasks --feature <feature>`. On a non-zero exit, stop and report its line.

## 1. Detect the build and tests

Run `keel-verify detect`. If the host's CLAUDE.md defines a build-and-test command, pass it with
`--host "<cmd>"`. Note `BUILD=`, `TESTCMD=` and `TESTFW=`.

## 2. Load the design

Read `specs/<feature>/spec.md` (user stories with priorities, FRs, edge cases) and `plan.md`
(Design Decision, technical context, structure). If they exist, also read `data-model.md`,
`contracts/`, `research.md` and `quickstart.md`. Look at the code paths the plan names, so the
tasks use real paths.

## 3. Write `specs/<feature>/tasks.md`

1. Use `$KEEL_ROOT/vendor/speckit/templates/tasks-template.md` as the structure:
   - Phase 1, Setup;
   - Phase 2, Foundational;
   - one phase per user story, in priority order;
   - Polish;
   - the dependencies and the parallel opportunities.

   On the light path, keep it to the phases the change needs.
2. **Format of every task line**: `- [ ] T### [P?] [US#?] <description> in <path>`. IDs are
   sequential in execution order. Mark `[P]` only for tasks on different files with no unfinished
   dependency. Story labels go only in user-story phases.
3. **Behavior tasks**: these change production code (`src/main/**`, including resources, or the
   language's equivalent). Each one names both paths and covers RED, GREEN and refactor itself:
   `- [ ] T012 [US1] Add RefundPolicy.limit in src/main/java/…/RefundPolicy.java (test: src/test/java/…/RefundPolicyTest.java)`.
   Don't write separate "write tests" tasks.
4. **Non-behavior tasks**: setup, config and docs. They name their paths and need no test path.
5. **Test setup** (when `TESTCMD=none` or `TESTFW=none`):
   - Add a non-behavior setup task **before the first behavior task**.
   - In Maven it names `pom.xml`, for example:
     `- [ ] T001 Add JUnit 5 test setup (junit-jupiter test dependency, surefire plugin) in pom.xml`.
   - This is the one kind of build-file change a task may make without the spec asking for it.
   - With `BUILD=undetected`, add a setup task that names the build file the host uses.
6. **Small and ordered**: each task is one coherent change that one implementer can finish and
   verify. Order the tasks by dependency: models, then services, then endpoints and integration.
7. **Coverage**: every FR and acceptance scenario maps to at least one task. Every task maps to a
   requirement, a story, or the setup.

## 4. Record and hand back

1. Report the task count per story, the parallel opportunities, and any setup task.
2. Don't commit. The docs commit happens at the end of `analyze`.
3. Return to the run loop. The next step is `analyze`.
