# Feature Specification: Spec-to-Commit Feature Delivery (keel v1)

**Feature Branch**: `001-spec-to-commit-flow` (created 2026-11-25 from `main` at the Spec Kit scaffold commit)
**Created**: 2026-11-24
**Status**: Approved (Gate 1, 2026-11-25)
**Input**: User description: "keel v1, end-to-end spec-driven feature delivery as a single Claude Code
plugin: take a plain-language feature description through Spec Kit's flow to a local commit on a
feature branch, ready to push, never pushing, combining the strongest parts of Spec Kit, superpowers
and feature-dev so those can be disabled."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - From feature description to an approved, reviewed plan (Priority: P1)

A developer working in a git repository describes a feature in plain language. keel first recalls
related past decisions (when memory is available), then asks focused questions about intent, goals,
non-goals and anti-goals as well as missing requirements, and writes a spec. The developer approves
the spec (Gate 1). keel then maps the code relevant to the feature, proposes two or three competing
designs with their trade-offs and a recommendation, and the developer picks one (Gate 2). An
independent reviewer with no prior context checks the resulting plan and returns GO or NO_GO before
anything is built.

**Why this priority**: Most of the value of combining the three tools is front-loaded: an
understood intent, a design chosen from real alternatives, and a plan that has survived independent
review. It is also the part every later step depends on.

**Independent Test**: In a sample repository, describe a small feature, answer the clarification
questions, approve the spec and choose a design. The run ends with a Spec Kit-compatible spec and
plan under `specs/NNN-feature/`, the plan records chosen and rejected designs, and a GO verdict is
attached, with exactly two approval interactions.

**Acceptance Scenarios**:

1. **Given** a repository with no prior keel or Spec Kit setup, **When** the developer describes a
   feature, **Then** keel establishes the repository's constitution from its existing instructions
   (referring to them rather than copying them) and proceeds to the spec.
2. **Given** a written spec, **When** the developer has not yet approved it, **Then** keel does not
   start planning.
3. **Given** an approved spec, **When** planning runs, **Then** the developer sees two or three
   distinct designs, each with trade-offs, plus keel's recommendation, and is asked to choose.
4. **Given** a chosen design, **When** the independent review returns NO_GO, **Then** keel revises
   the plan and reviews it again; if the same blocker survives three rounds, keel stops and asks the
   developer.
5. **Given** a repository that already uses Spec Kit, **When** a new feature starts, **Then** keel
   reuses the existing constitution and continues the existing feature numbering.
6. **Given** a change keel classifies as small, **When** the developer approves the spec and accepts
   the classification, **Then** the run proceeds without competing designs or plan review, and that
   approval is the only one in the run.
7. **Given** a change that alters an API contract or persisted data, **When** keel writes the spec,
   **Then** it does not offer the light path.

---

### User Story 2 - From approved plan to a verified local commit (Priority: P1)

With a GO plan, keel breaks the work into small, test-first, dependency-ordered tasks, checks that
spec, plan and tasks agree, and implements each task on a feature branch: a fresh context per task
writes a failing test, makes it pass and refactors, and a per-task review checks it against the spec
and for quality. After all tasks, mutation analysis checks that the tests actually catch changes in
the new code (User Story 3), then three independent reviews look at the whole change (simplicity
and duplication, correctness, project conventions). keel then runs the project's build and tests, shows
the output, and commits on the feature branch following the project's conventions. Nothing is
pushed.

**Why this priority**: This is the other half of the end-to-end promise: work that arrives
committed, tested and reviewed, ready for the developer to push.

**Independent Test**: Starting from an approved plan produced by User Story 1, run keel to
completion in a sample repository. The result is one or more commits on a
feature branch, every task has a test that was seen failing before its implementation, the final
build and test output is shown and passing, and no publish action occurred.

**Acceptance Scenarios**:

1. **Given** a GO plan, **When** the run completes, **Then** the feature branch holds the commits,
   the working tree is clean, and the branch has not been published.
2. **Given** a task, **When** it is implemented, **Then** a test for its behavior was observed
   failing before the implementation and passing after it.
3. **Given** a test or build failure during implementation, **When** keel responds, **Then** it
   identifies the root cause before changing code, and after three failed fix attempts on the same
   problem it stops and reports.
4. **Given** the final review, **When** a verified finding stays within the approved spec and
   design, **Then** keel fixes it and re-verifies; **When** a finding would require changing the
   approved spec or design, **Then** keel stops and reports.
5. **Given** the project's instructions specify commit style or forbid AI co-author trailers,
   **When** keel commits, **Then** the commit follows those instructions.

---

### User Story 3 - Test quality is measured, not assumed (Priority: P2)

LLM-written tests often look thorough but assert too little, overlap each other, or miss whole
branches. After all tasks are implemented, and before the final reviews, keel runs mutation analysis
on the code the feature changed: it makes small deliberate changes to that code and checks whether
any test notices. keel reports changed code no test runs, changes that tests run but don't catch,
and tests that add nothing beyond what other tests already catch. Gaps are closed with tests tied to
the spec's behavior, or recorded with a reason; redundant tests are reported. The setup belongs to
keel, not to the project: the project's build files stay untouched.

**Why this priority**: Test-first discipline guarantees tests exist, not that they are good. This
measures it, and the reviewers then see tests that have been shown to catch defects.

**Independent Test**: In a sample project, implement a feature whose tests are deliberately weak
(a missing assertion, an untested branch, two duplicate tests). The analysis reports all three; the
missing assertion and the untested branch are fixed with behavior-level tests or triaged with a
reason, the duplicates are reported, and the project's build files are unchanged.

**Acceptance Scenarios**:

1. **Given** implemented tasks, **When** mutation analysis runs, **Then** it covers only the code
   the feature changed and writes a summary to the feature's directory.
2. **Given** a change that tests run but don't catch, **When** keel resolves it, **Then** the new or
   strengthened test checks behavior traceable to the spec, not implementation details.
3. **Given** a change with no observable effect, **When** it survives, **Then** keel records it as
   triaged with the reason, and does not add a test for it.
4. **Given** findings that can't be resolved, **When** the step ends, **Then** the run stops and
   reports them before the reviews.
5. **Given** a project in a language or build tool keel doesn't support, **When** the step is
   reached, **Then** the summary and final report say the analysis was not run, and why.

---

### User Story 4 - Resume an interrupted run (Priority: P2)

A run is interrupted (session ends, context resets, the developer stops it). Later the developer
asks keel to continue. keel works out from the feature's artifacts and the branch's commits which
step was last completed and resumes from there without redoing finished work or asking again for
approvals already given.

**Why this priority**: Full feature runs are long and will regularly outlive a single session.
Without resume, interruptions mean redone work or lost approvals.

**Independent Test**: Interrupt a run after each step in turn (spec approved, design chosen, plan
reviewed, mid-implementation, after review). Each time, resuming completes the run with no completed
task redone and no approval asked twice.

**Acceptance Scenarios**:

1. **Given** a run interrupted after Gate 2, **When** the developer resumes, **Then** keel continues
   from plan review without asking for the design choice again.
2. **Given** a run interrupted mid-implementation with some tasks committed, **When** resumed,
   **Then** only the remaining tasks are implemented.

---

### User Story 5 - Decisions carry across features (Priority: P3)

When the memory integration (engram) is present, keel searches it for related past decisions before
specifying and before planning, and saves one memory per feature (after the design is approved and
after the commit) under a stable key so the second save updates the first. When the integration is
absent, nothing changes in the run.

**Why this priority**: Useful continuity, but the flow is complete without it.

**Independent Test**: Run two related features with memory present: the second feature's spec or
plan cites the first feature's decision, and memory holds exactly one entry per feature. Run again
with memory absent: the run completes with the same outcome and no errors.

**Acceptance Scenarios**:

1. **Given** memory is available, **When** a feature completes, **Then** exactly one memory entry
   exists for it, and no session-lifecycle function of the memory tool was used.
2. **Given** memory is unavailable or returns errors, **When** a run executes, **Then** the memory
   steps are skipped silently and the run's outcome is unaffected.

---

### User Story 6 - Debug, verify, audit tests and handle review feedback outside a feature run (Priority: P3)

With superpowers disabled, the developer still needs its everyday disciplines outside a full feature
run: tracking down a bug to its root cause before fixing it, refusing to call something done without
build and test evidence, and checking code-review feedback against the code before applying it. They
also want to audit the tests of existing code with the same mutation analysis the flow uses. keel
offers these four on their own, behaving the same as the matching steps inside a run.

**Why this priority**: Disabling superpowers would otherwise remove capabilities used daily. The
flow needs all four internally, so offering them standalone adds little.

**Independent Test**: With no feature run in progress, ask keel to debug a failing test, to verify a
change, to respond to a set of review comments, and to audit the tests of a named module. Each one
works on its own and follows the same rules as its in-run counterpart.

**Acceptance Scenarios**:

1. **Given** a failing test and no feature run, **When** the developer asks keel to debug it,
   **Then** keel establishes the root cause before proposing a fix and stops after three failed fix
   attempts.
2. **Given** a change the developer believes is finished, **When** they ask keel to verify it,
   **Then** keel runs the project's build and tests and reports the result with the output.
3. **Given** review comments on a change, **When** the developer asks keel to respond to them,
   **Then** each comment is checked against the code and either applied or answered with a reason.
4. **Given** a module the developer names, **When** they ask keel to audit its tests, **Then** keel
   reports coverage gaps, uncaught changes and redundant tests for that module, without modifying
   the project's build files.

### Edge Cases

- **Publish attempts**: any attempt by keel, or by the assistant during a keel-enabled session, to
  publish commits or open a pull request is blocked and reported. The developer can still push
  themselves.
- **Ambiguous commands**: when the guard cannot tell whether a command publishes, it blocks.
- **Host instructions that ask for publishing** (e.g. "push after commit"): the never-push rule
  wins; keel reports that it did not follow that instruction.
- **Uncommitted changes at start**: keel stops and reports rather than stashing, discarding or
  mixing the developer's work into the feature.
- **Repository on its default branch or with no commits yet**: keel creates the feature branch
  before writing code.
- **Pre-existing build or test failures unrelated to the feature**: keel distinguishes them from
  failures it introduced, reports them, and does not "fix" unrelated code; if they prevent
  verification, it stops.
- **No automated tests in the host project**: the plan must establish a way to test the feature;
  verification is never skipped silently.
- **Developer rejects all proposed designs**: the developer's own design is recorded as the chosen
  one, with its trade-offs against the proposed ones.
- **Parallel tasks touching the same files**: they run one after another.
- **A review finding contradicts the approved design**: treated as blocking; keel stops and reports.
- **Tests fail or are flaky when mutation analysis starts**: the analysis needs a passing, stable
  suite; keel treats this like any unexpected failure (root cause first) and does not run the
  analysis on a red or unstable suite.
- **Slow test suites**: the analysis is limited to the changed code and the tests that exercise it;
  if it still can't complete, keel stops and reports rather than skipping it.
- **Changes with no observable effect**: they can't be caught by any test; keel records them as
  triaged instead of writing contrived tests for them.

## Requirements *(mandatory)*

### Functional Requirements

**Setup and constitution**

- **FR-001**: keel MUST run in any git repository with only keel installed: Spec Kit's CLI,
  superpowers and feature-dev are not required.
- **FR-002**: keel MUST establish the repository's constitution from its existing instructions,
  referring to them rather than duplicating their content; when no instructions exist, it MUST
  propose principles for the developer to accept.
- **FR-003**: keel MUST store all feature artifacts in the Spec Kit layout (`specs/NNN-feature/`
  with Spec Kit's file names and formats) and MUST NOT create any other artifact tree.

**Specify and clarify**

- **FR-004**: Before writing a spec, keel MUST look up related past decisions when memory is
  available and cite the relevant ones in the spec.
- **FR-005**: Clarification MUST cover intent and why, goals, non-goals and anti-goals as well as
  missing requirements, asking one question at a time.
- **FR-006**: keel MUST present the spec and wait for the developer's explicit approval (Gate 1)
  before planning.

**Plan**

- **FR-007**: Before proposing designs, keel MUST map the code relevant to the feature through
  several independent explorations, each reporting the files and patterns that matter.
- **FR-008**: keel MUST propose two or three designs with distinct priorities (smallest change,
  cleanest structure, pragmatic balance), each with its trade-offs, and recommend one with reasons.
- **FR-009**: keel MUST wait for the developer to choose a design (Gate 2) and MUST record the
  chosen and rejected designs, with trade-offs, in the plan.
- **FR-010**: After the plan is written, a reviewer with no prior context MUST assess it and return
  critical flaws, missing assumptions, proposed changes and a GO or NO_GO verdict. NO_GO MUST lead
  to revision and a fresh review; a blocker that survives three rounds MUST be escalated to the
  developer; keel MUST NOT build under an open NO_GO.

**Tasks and analysis**

- **FR-011**: keel MUST break the plan into small, dependency-ordered tasks, each with its test
  written first, and MUST mark tasks that can run in parallel.
- **FR-012**: keel MUST check spec, plan and tasks for consistency before implementation; critical
  findings MUST stop the run.

**Implementation**

- **FR-013**: All changes MUST be made on a feature branch, never on the default branch.
- **FR-014**: Each task MUST be implemented in a fresh context: a failing test first, then the
  smallest change that passes it, then refactoring, with the failing and passing results recorded.
- **FR-015**: Each completed task MUST be reviewed for spec compliance and quality before the next
  dependent task starts; issues MUST be fixed before moving on.
- **FR-016**: On an unexpected failure, keel MUST establish the root cause before changing code;
  after three failed fix attempts on the same problem it MUST stop and report.
- **FR-017**: Tasks marked parallel MAY run at the same time only when they do not touch the same
  files.

**Test quality (mutation analysis)**

- **FR-030**: After all tasks and before the final reviews, keel MUST run mutation analysis on the
  code the feature changed relative to its base branch, using the tests that exercise that code.
- **FR-031**: keel MUST classify the results into: changed code that no test runs (coverage gaps);
  changes that tests run but don't catch (assertion gaps); tests whose caught changes are all also
  caught by other tests (redundancy candidates); and tests with identical caught changes (overlap).
  The classification MUST be computed from the analysis tool's results, not judged by the model.
- **FR-032**: keel MUST try to resolve every coverage and assertion gap in changed code
  automatically: either with a test that checks behavior traceable to the spec's requirements or
  acceptance scenarios, or by recording it as triaged with a reason (no observable effect, or not
  worth a test, with the justification). Gaps still unresolved after that MUST stop the run. Tests
  that assert implementation details only to catch a specific change MUST be rejected.
- **FR-033**: Redundancy and overlap findings MUST NOT stop the run. keel reports them, and merges
  or removes tests only when both their caught changes and the behavior they check are identical.
- **FR-034**: Mutation analysis MUST run without modifying the project's build files or committed
  configuration. Its raw output MUST stay out of version control, and a summary (`test-quality.md`)
  MUST be written to the feature's directory.
- **FR-035**: v1 MUST support Java projects built with Maven. For any other project, the summary
  and the final report MUST state that mutation analysis was not run and why; it MUST never be
  skipped silently.

**Review, verification and commit**

- **FR-018**: After all tasks, keel MUST run three independent reviews of the whole change
  (simplicity and duplication, correctness, project conventions), reporting only findings above a
  confidence threshold.
- **FR-019**: Each review finding MUST be checked against the code before it is acted on. Verified
  findings within the approved spec and design MUST be fixed and re-verified; findings that would
  change the approved spec or design MUST stop the run.
- **FR-020**: Before committing, keel MUST run the project's build and tests as the project's
  instructions define them (or as detected from the repository when they don't), show the output,
  and MUST NOT commit while either fails.
- **FR-021**: keel MUST commit on the feature branch following the project's and the user's
  conventions (message style, attribution rules such as no AI co-author trailers).
- **FR-022**: keel MUST block every action that publishes commits or opens a pull request while it
  is active, including when instructed to do so; the block MUST NOT rely on instructions alone, and
  MUST fail closed when a command's effect is unclear.

**Run control**

- **FR-023**: keel MUST ask for approval only at Gate 1 and Gate 2 (only Gate 1 on the light path,
  FR-028); clarification questions are inputs, not gates. Every other step MUST run without
  prompting, stopping only on the conditions defined in FR-010, FR-012, FR-016, FR-019, FR-020,
  FR-032 and the edge cases above.
- **FR-024**: An interrupted run MUST resume from the last completed step, determined from the
  feature's artifacts and commits, without redoing completed work or repeating given approvals.

**Memory integration**

- **FR-025**: When memory is available, keel MUST save one entry per feature, written after Gate 2
  and updated after the commit, under a stable per-feature key; it MUST NOT call the memory tool's
  session-lifecycle functions. When memory is unavailable or failing, these steps MUST be skipped
  without affecting the run.

**Provenance**

- **FR-026**: keel MUST ship a NOTICE attributing Spec Kit (MIT), superpowers (MIT) and feature-dev
  (Apache-2.0), record for each copied source its upstream version and license, and mark modified
  Apache-2.0 files with a change notice.

**Scope decisions**

- **FR-027**: keel MUST provide four capabilities usable on their own, outside any feature run:
  root-cause debugging, verification before claiming something is done, responding to code-review
  feedback, and auditing the tests of code the developer names with mutation analysis. They MUST
  behave the same as the in-run steps they correspond to (FR-016, FR-020, FR-019 and FR-030 to
  FR-035).
- **FR-028**: When writing the spec, keel MUST say whether the change qualifies as small, with its
  reason. A change qualifies only if it touches no external contract (API, webhook, schema),
  changes no persisted data or its structure, and is easy to reverse. If the developer accepts the
  classification as part of approving the spec, the run skips the competing designs and the plan
  review; keel states the single design it will follow in the plan. Test-first tasks, per-task
  review, mutation analysis, the final review, verification and the commit still apply. keel MUST
  NOT apply the light path without that acceptance.
- **FR-029**: keel v1 targets the maintainer's own machines and repositories. Installation from the
  local repository and documentation for the maintainer's own use are sufficient, and portability to
  other setups is not tested. The constitution still applies: only bash and git are required, and
  memory stays optional.

### Key Entities

- **Feature run**: one pass of the flow for one feature; has a current step, the gates passed, and
  a link to its artifacts and branch.
- **Feature artifacts**: the Spec Kit set for one feature (spec, plan, research, data model,
  contracts, quickstart, tasks, checklists) under `specs/NNN-feature/`.
- **Constitution**: the repository's governing principles, derived from and referring to its
  existing instructions.
- **Design option**: one proposed design with its priority (smallest change, cleanest structure,
  pragmatic balance), trade-offs, and whether it was chosen.
- **Review verdict**: the result of a plan review (GO or NO_GO with blockers) or a code review
  (findings with severity, confidence and verified status).
- **Memory entry**: one per feature, keyed stably, holding the chosen design and the outcome.
- **Provenance record**: per copied source, its upstream location, version, license and local
  changes.
- **Mutation result**: one deliberate change to the feature's code, its outcome (caught, not
  caught, not run by any test) and which tests caught it.
- **Test-quality summary**: per feature, the gaps found and how each was resolved or triaged, the
  redundancy and overlap findings, or the reason the analysis was not run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In trial runs on small features, the developer goes from description to local commit
  with exactly two approval interactions (plus clarification answers) and no other prompts.
- **SC-002**: Zero publish actions across all trial runs; 100% of a prepared set of publish
  attempts (direct, aliased, chained and indirect variants) are blocked.
- **SC-003**: 100% of keel commits are preceded, in the same run, by a shown and passing build and
  test run.
- **SC-004**: 100% of implemented tasks show a test that failed before and passed after the
  implementation.
- **SC-005**: Interrupting a run after each step and resuming completes it every time, with zero
  completed tasks redone and zero approvals asked twice.
- **SC-006**: Artifacts produced by keel are accepted by plain Spec Kit commands without edits.
- **SC-007**: A full run completes with superpowers, feature-dev and Spec Kit's CLI all disabled or
  absent.
- **SC-008**: With memory absent, runs complete with the same outcome and no errors; with memory
  present, each completed feature has exactly one memory entry.
- **SC-009**: After running at least three real features through keel (e.g. in PayConductor), the
  maintainer judges that disabling superpowers and feature-dev lost nothing they relied on.
- **SC-010**: Light-path runs need exactly one approval, and 100% of changes touching an external
  contract or persisted data are kept off the light path.
- **SC-011**: The four standalone capabilities each complete a trial task with no feature run in
  progress.
- **SC-012**: Before every keel commit, 100% of coverage and assertion gaps in changed code are
  either caught by a test or triaged with a recorded reason.
- **SC-013**: On a seeded suite with known weaknesses (missing assertions, untested branches,
  duplicate tests), the analysis reports 100% of the seeded gaps and duplicates.
- **SC-014**: Zero changes to the project's build files across all trial runs.

## Assumptions

- v1 is for the maintainer's own use (FR-029); sharing with teammates is a later decision.
- Claude Code is the only host agent; other coding agents are out of scope for v1.
- One request starts or resumes a run; individual steps can also be run on their own, as in Spec
  Kit.
- The constitution is set up once per repository and updated when the host's instructions change,
  not rewritten for every feature.
- Pushing, opening pull requests and creating issues are out of scope; the developer publishes.
- superpowers and feature-dev will be disabled once keel is adopted; keel does not need to coexist
  with them (including superpowers' startup behavior).
- Host machines provide bash and git; host projects define their build and test commands in their
  instructions or use a standard build tool that can be detected from the repository.
- "Blocking" means: a critical analysis finding, a NO_GO surviving three review rounds, a review
  finding that would change the approved spec or design, three failed fix attempts on one problem,
  test-quality gaps still unresolved after automatic resolution, or failing verification. Verified
  findings inside the approved design are fixed automatically.
- Mutation analysis supports Java with Maven in v1, because that covers the maintainer's main
  repositories; other languages (e.g. TypeScript) come later.
- keel may download its own pinned test-quality tools from the package repositories the project's
  build already uses (constitution v1.2.0).
- Work is committed task by task on the feature branch, so progress is visible and resumable; how
  commits are combined before pushing is the developer's choice.
- The run works in the current checkout on a feature branch; separate working copies are not
  required for v1.
- Taking over a feature written with plain Spec Kit ("adopt") is out of scope for v1.
  - Spec Kit's task lists put tests in separate tasks, which conflicts with per-task test-first
    evidence.
  - keel's own artifacts stay readable by plain Spec Kit (SC-006).
  - Amended 2026-11-25 by the maintainer during plan review.
