# Implementation Plan: Spec-to-Commit Feature Delivery (keel v1)

**Branch**: `001-spec-to-commit-flow` | **Date**: 2026-11-25 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-spec-to-commit-flow/spec.md` (approved, Gate 1)
**Plan status**: complete

## Summary

keel is a Claude Code plugin. It takes a plain-language feature description through Spec Kit's
flow:
- constitution → specify → clarify → plan → tasks → analyze → implement;
- then keel's own test-quality → review → verify → commit steps.

The run ends with local commits on a feature branch and never publishes.

keel is self-contained. It adapts three upstreams:
- **Spec Kit**: the flow and its artifacts.
- **superpowers**: TDD, root-cause debugging, verification, and a fresh implementer per task with
  review.
- **feature-dev**: explorers, competing architects and confidence-filtered reviewers.

The chosen design (Gate 2) is **Pragmatic balance plus three additions from the Clean design**:
- **Code backs only the guarantees the spec makes measurable**:
  - the push block, in three layers: git-level environment config (a pre-push hook plus a push-URL
  rewrite), execution-time `git`/`gh` shims, and a static hook;
  - derived run state and resume;
  - gate ordering;
  - RED-before-GREEN evidence;
  - verify-before-commit;
  - mutation classification.
- Everything else is skill and agent prose.

Mutation analysis uses PIT through the Maven command line with two extra jars on its classpath. It
needs no POM edit and no worktree (research R5, approach B′).

## Technical Context

**Language/Version**:
- Bash, compatible with **bash 3.2**. macOS ships only `/bin/bash` 3.2.57, so the code avoids:
  - associative arrays, `mapfile`, `${var,,}`, `[[ -v ]]`;
  - `\u` in `printf`;
  - unguarded empty `"${a[@]}"` under `set -u`.
- POSIX awk (BSD awk 20200816 on macOS: no gawk extensions, no `\b`) under `LC_ALL=C`.
- Portable sed: `sed -E` only, and no `-i` without a suffix.
- Markdown for skills and agents.

**Primary Dependencies**:
- Claude Code ≥ 2.1.295 (`onFailure: "block"`); installed 2.1.332.
- git ≥ 2.31 for `GIT_CONFIG_COUNT`, plus config-defined hooks (`hook.<name>.event`), which were
  verified on the installed 2.54. The exact minimum version is confirmed at M1 from the release
  notes. The `pushInsteadOf` rewrite works on any modern git.
- For mutation analysis only:
  - the host's Maven and JDK;
  - PIT 1.30.2, pitest-junit5-plugin 1.2.3, and the junit-platform-launcher matching the project's
    JUnit Platform version;
  - maven-dependency-plugin 3.8.1 and maven-help-plugin 3.5.1.
  - All of these are pinned and fetched through the host's Maven.
- Optional: the engram MCP server.

**Storage**:
- Spec Kit artifacts under `specs/NNN-feature/`.
- `.specify/memory/constitution.md` and `.specify/feature.json`.
- Untracked run scratch under `$(git rev-parse --git-dir)/keel/NNN-feature/`, written only by
  keel's scripts. `.git` is a protected path, so Write/Edit there always prompts.

**Testing**:
- `tests/run.sh`, a plain-bash harness with no bats.
- Fixture git repos in temp dirs.
- A seeded Maven fixture (slow tier).
- `claude plugin validate plugin/`.
- `claude plugin eval plugin --eval-dir tests/eval --no-publish --allow-tools Bash`. Each case is
  a single non-interactive session; gate scenarios are chained through `context.history_file`.
- A sed-based mutation self-check of keel's critical scripts.

**Shell model** (verified 2026-11-25 with a probe plugin in `claude -p`):
- The Bash tool runs the user's zsh with Claude Code's shell snapshot loaded, so profile aliases
  exist (e.g. `gp` = `git push`).
- cwd persists between calls; exported variables don't, except through a SessionStart
  `CLAUDE_ENV_FILE`.
- A plugin's `bin/` is **appended** to PATH.
- git puts its own exec-path first for the processes it spawns: hooks, `!` aliases, `rebase -x`
  and the like.
- Login shells run `path_helper`, which moves prepended directories to the end of PATH.
- Environment config (`GIT_CONFIG_*`) is inherited by every git process. That is why A0 is the
  primary layer for git.
- A SessionStart hook can **prepend** a directory through `CLAUDE_ENV_FILE`. This was verified with
  a `git` shim that intercepted `gp` and `eval`.
- `CLAUDE_PLUGIN_ROOT` is not set in the Bash tool, so keel exports `KEEL_ROOT` through the env
  file, and scripts fall back to their own path.
- Bash tool calls time out at 2 minutes by default and 10 at most. Long Maven and PIT runs use
  `run_in_background`.

**Permission model**:
- keel runs are meant for `acceptEdits` or auto mode, plus the allow rules in the quickstart:
  - each script by name (`Bash(keel-state:*)`, `Bash(keel-branch:*)`, … `Bash(keel-classify:*)`);
    a wildcard inside the command name is not relied on;
  - `Bash(git add:*)`, `Bash(git commit:*)`, `Bash(git switch:*)`, `Bash(git status:*)`,
    `Bash(git diff:*)`, `Bash(git log:*)`, `Bash(git restore:*)`, `Bash(git rev-parse:*)`;
  - `Bash(mvn:*)`, `Bash(./mvnw:*)`.
- Step skills also declare `allowed-tools`.
- No keel step writes under `.git` through Write/Edit or a visible redirect.

**Target Platform**: macOS (primary) and Linux, Claude Code CLI, maintainer's machines (FR-029).

**Project Type**: Claude Code plugin. Its root is `plugin/`, and the repo root holds the
marketplace, specs and tests.

**Performance Goals**:
- Push guard layer B: p95 under 100 ms per Bash call.
- Layer A shim: under 15 ms per git or gh call.
- Mutation analysis is bounded by changed lines and unit tests, with a default budget of 900 s.

**Constraints**:
- Only bash and git are required.
- Enforcing hooks fail closed.
- No host file edits outside the feature's own changes.
- No network beyond the host build, except keel's pinned test-quality tools fetched through it.
- Orchestration runs in the main session, because subagents can't spawn subagents.

**Scale/Scope**: one feature per run.
- 15 user-facing skills plus 1 internal skill.
- 6 agents.
- About 14 scripts.
- 2 hook events and 7 shims.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design and after plan review
round 1.*

Evaluated against constitution **v1.3.0**, amended by this plan.

| Principle | Status | How the design satisfies it |
|---|---|---|
| I. Never Push | PASS | **A0**: SessionStart environment config gives every git process, however it is started, a config-defined pre-push hook and an empty-prefix `pushInsteadOf` rewrite. Verified: the rewrite blocks even `--no-verify`. **A**: `git`, `gh` and other tool shims, first on PATH, see final argv (aliases, functions, eval) and give clear early denials. **B**: a static PreToolUse guard covers PATH bypasses for `gh` and the other tools, A0 tampering, forge HTTP writes, GitHub MCP writes and Codex full-access runs. Publishing only: local git is allowed. All layers fail closed. A keel run halts if A0 or A is inactive. Tested with layer-tagged deny/allow corpora (SC-002). |
| II. Spec Kit Flow Is the Backbone | PASS | Step skills mirror Spec Kit's sequence, followed by test-quality → review → verify → commit. Artifacts are Spec Kit's files plus `test-quality.md` and `test-quality.triage.tsv` (keel's triage decisions, one file, not a tree). Scratch sits under `.git/keel/`, untracked and not an artifact tree. Adopting plain Spec Kit features is out of scope for v1 (spec Assumptions, maintainer decision). |
| III. Self-Contained, Attributed Vendoring | PASS | The runtime uses only plugin files. `plugin/vendor/` holds Spec Kit scripts and templates verbatim, upstream `LICENSE` files, `PROVENANCE.md` and `CHANGELOG.md`. Adapted files carry source headers. feature-dev derivatives carry Apache §4(b) change notices. Root `NOTICE`. |
| IV. Human Gates Only Where Judgment Is Irreplaceable | PASS | Exactly two prompts: Gate 1 in `clarify`, Gate 2 in `plan`. The light path has one. `keel-state require` refuses out-of-order steps. Every automated check halts and reports. The only other contact is the FR-010 three-round escalation. No extra permission prompts under the documented setup, because scratch writes go through scripts. |
| V. Evidence Before Claims | PASS | `keel-verify` runs build and tests, shows the output, and must pass (new failures only, compared with the baseline) **before every commit**. That includes the docs commit, made at the end of analyze after the baseline verify. The baseline passes when the build compiles (or there is nothing to build yet), its failing set becomes the reference, and `TESTS=none`/`BUILD=none` are shown and reported, never skipped silently. `keel-evidence` checks RED-before-GREEN by exit codes and tree ids wherever the per-unit rule (data-model.md §7) requires it: every behavior task and every fix-intent unit. Mutation runs on changed lines, and finish re-runs it on production changes made after the
test-quality commit. keel's own scripts have tests, skills have eval scenarios, and critical scripts have a mutation self-check. |
| VI. Optional Integrations Degrade Gracefully | PASS | engram: `mem_search` before specify and plan. `mem_save` with `topic_key: keel/<NNN-feature>` after Gate 2 (or the light-path plan) and after finish. Skipped if absent or failing. No `mem_session_*` calls. `judgment_required` is resolved without prompting. No other saves during a run. |
| VII. Host Instructions Win | PASS | `verify`/`finish` take build, test and commit rules from host CLAUDE.md files (global and project). No CLAUDE.md marker edits, no ignore-file patching. A host instruction to publish is reported as not followed (constitution I wins). |
| Plugin Constraints | PASS | Writes outside the repo are limited to Maven's own `~/.m2`, when it downloads pinned tools (carve-out), and the session file Claude Code hands to SessionStart hooks (`CLAUDE_ENV_FILE`, carve-out). `${CLAUDE_PLUGIN_DATA}` is unused. Nothing goes to `/tmp`. |

### Constitution amendment (v1.2.0 → v1.3.0, MINOR), made with this plan

- **I**: local-only git operations are not publishing and MUST NOT be blocked (maintainer, Gate 2).
  Forge API writes that create pull requests or remote commits count as equivalents.
- **II**: the post-implement sequence is test-quality → review → verify → commit (FR-030).
- **Plugin Constraints**:
  - exceptions for the host build tool's own caches when it downloads keel's pinned test-quality
    tools, and for files Claude Code provides to plugins for session state (`CLAUDE_ENV_FILE`);
  - run scratch lives inside the repository's git directory.

### Interpretations recorded for verification

- **SC-003 / Constitution V**: "before any commit" means every keel commit: docs, tasks,
  every work unit, test-quality and finish.
  - The spec, plan and tasks are committed together, after a passing baseline verify.
  - Until then, gate evidence lives in working-tree files.
- **Verify scope**: the host's build and test command. A host instruction may define a faster
  per-task command (VII). The full command always runs at finish.
- **Pre-existing failures**: "passing" means no new failure compared with the baseline's failing
  set, and the build compiles. The baseline's failures are reported as unrelated (edge case).
- **SC-012**: per-task commits necessarily come before mutate (FR-030), and `REV-n` and `FIN-n`
  fixes are committed before finish's re-mutation. "Before every keel commit" is therefore read as
  "before the commits that close the feature": the test-quality commit and the finish commit.
  Finish re-mutates every production change made after the test-quality commit.
- **SC-005**: an interruption inside a work unit (task, mutation round, review-fix round, finish
  fix or the `FINISH` edit) is
  recovered: the partial diff is saved to scratch, the unit's BASE is restored and the unit
  restarts (data-model.md §5). This happens only when every changed path is attributable to the
  unit. Anything else may be the developer's work, so keel halts (edge case).
- **Threat model (FR-022)**: the guard defends against mistaken or instructed publishing, including
  prompt-injected instructions and ordinary indirection. It does not defend against an adaptive
  adversary that runs code built to defeat it. The residuals are listed in
  contracts/push-guard.md.
- **SC-003 with no build or no tests**: the docs commit's evidence is the shown baseline output,
  "nothing to build or test" or "compiled, no tests". The first behavior task can't be committed
  until a test command exists; `keel-verify` returns `MISSING=test-command` there.
- **SC-014 "zero changes to build files"**: counts changes made by keel's own tooling (mutation,
  verify). A build-file change the feature itself needs, such as a test-setup task adding a
  test dependency, is allowed only through a task that names the file (data-model.md §7).
- **SC-004 and developer commits after a halt**: tasks the developer commits by hand after a halt
  have no keel RED/GREEN evidence. The final report lists them as "committed by the developer, no
  keel evidence".
- **SC-001 "no other prompts"**: holds under the documented permission setup. Without it, Claude
  Code's own permission prompts are outside keel's control.
- **SC-008 "exactly one entry"**: counts entries under keel's topic key. engram's own protocol
  (its session summaries and proactive saves) is engram's function, which keel must not duplicate
  (Principle VI). It is unaffected, and its skill can be disabled in keel repositories (see the
  quickstart).

## Design Decision

**Chosen**: Pragmatic balance + three Clean additions (Gate 2, 2026-11-25), with two maintainer
amendments.

- **Why it was recommended**: it is the only design with a working run early (through implement at
  M3, light path), and it puts code exactly where SC-002, SC-004 and SC-005 would otherwise fail.
- **What the additions do**: they close the gaps prose leaves around SC-004 and Principle IV, and
  remove duplicated discipline text (FR-027).

### Chosen design

- **Skills** (`/keel:<name>`):
  - Orchestrator `run`.
  - Step skills `constitution`, `specify`, `clarify`, `plan`, `tasks`, `analyze`, `implement`,
    `mutate`, `review`, `finish`.
  - Standalone `debug`, `verify`, `respond-review`, `test-audit`.
  - Internal `tdd`.
- **Agents**: `explorer`, `architect` (lens in brief), `plan-reviewer`, `implementer`,
  `task-reviewer`, `code-reviewer` (lens in brief).
- **Scripts** (`plugin/bin/`; also reachable through `KEEL_ROOT`):
  - `keel-state`, `keel-branch`, `keel-ledger`, `keel-put`, `keel-brief`, `keel-diff`;
  - `keel-evidence`, `keel-verify`;
  - `keel-mutate`, `keel-classify`.
- **Guard**: the A0 environment config from `plugin/hooks/session-env.sh` and
  `plugin/hooks/deny-push`; `plugin/shims/` (layer A); `plugin/hooks/guard-push.sh` (layer B).
- **State**: derived from artifacts and git, latest-first. The `.git/keel/` ledger is an
  accelerator.
- **Clean addition 1, `keel-evidence`**: test runs are recorded with exit code and working-tree id.
  `check` requires a failing run whose tree has the test but not the production change, followed
  by a passing run after the production change (SC-004).
- **Clean addition 2, `keel-state require <step>`**: the first action of every step skill. It
  refuses steps whose preconditions aren't evidenced, and refuses to run without the push shim
  (FR-006, Principle IV).
- **Clean addition 3, shared discipline skills**: `tdd` (internal), `debug` and `verify` are each a
  single source, preloaded into agents through `skills:` frontmatter. The standalone skills are
  the same files (FR-027).
- **Maintainer amendment A, narrow push guard**: block only publishing, with no git subcommand
  allowlist. `git stash`, `rebase`, `reset` and `cherry-pick` stay allowed.
  - Plan review rounds 1 and 2 showed that text parsing misses shell aliases and that PATH shims
    miss git's own child processes. It is therefore implemented as three layers: A0, A and B. The
    decision is unchanged, only its implementation.
- **Maintainer amendment B, PIT runner B′**: Maven CLI with `-DadditionalClasspathElements`, chosen
  over the maintainer's worktree suggestion. The spike showed identical results without a second
  checkout or compile. The PIT command-line runner (C) is the documented fallback, not built in v1.

### Rejected designs

| Design | What it offered | Why rejected |
|---|---|---|
| **Smallest change** | One `run` skill with step files. Four agents (one reviewer with modes). Four scripts. `.keel/` scratch excluded through `.git/info/exclude`. | Gates and resume rest on prose and text markers alone, which is exactly where SC-001, SC-004 and SC-005 fail. One large skill defeats progressive disclosure and standalone steps. Its git-subcommand allowlist would block stash, rebase, reset and cherry-pick in every session. The first full run came at M4–M7. |
| **Clean architecture** | About 25 scripts behind a typed step registry. A patch-based vendor pipeline (`upstream/` + `patches/` → `dist/`, `sync.sh`). A runner adapter contract (detect, prepare, run, cleanup). An approval content hash. | Too much code before anything works (first full run at M8). The patch pipeline is overkill for a personal v1 (FR-029): `PROVENANCE.md` plus `CHANGELOG.md` keep upstream diffable. Its three most valuable ideas were adopted. |

**Kept as later options, not built in v1**: the approval content hash, file-disjoint parallel
groups (FR-017) and a multi-ecosystem runner registry.

## Architecture

### Run control and state (FR-023, FR-024)

**Invocation**:
- `/keel:run "<description>"` starts a new feature.
  - `run` binds it: `keel-branch next-number`, then `ensure`, then it writes `feature.json`.
  - From then on, `run` passes `--feature` to every script and step skill, so a stale
    `feature.json` never redirects the run.
- `/keel:run` resumes the feature in `.specify/feature.json`.
- `/keel:run NNN` resumes the named feature and rewrites `feature.json`.

**Order inside `run`**:
1. Run `keel-state recover --feature <f>`, then `keel-branch ensure`, then `recover` again if it
   returned `RECOVERED=deferred`. This happens before any write, so the feature branch exists
   before the constitution or the spec is written (FR-013).
   - For a new feature, `<f>` is the new name, so `recover` is a no-op. It never runs with a
     stale `feature.json`.
2. The orchestrator loops: `keel-state next`, then the step skill through the Skill tool, then
   repeat. It stops on `done`, a halt or a gate.
3. Each step skill begins with `keel-state require <step>`. That check also verifies that guard
   layers A0 and A are active.

**Step order**: `constitution → specify → clarify (Gate 1) → plan (explore, design, Gate 2, write
artifacts, plan review) → tasks → analyze → implement → mutate → review → finish`.
- The light path skips the designs, Gate 2 and the plan review (FR-028).

**State derivation** (data-model.md §2) converges. The next step is the earlier of the latest-first
progress candidate and the first missing gate prerequisite.
- Finish evidence means `done`.
- Analyze makes the docs commit as its last action, after its checks and the baseline verify pass.
  Its evidence is the `**Analyzed**` line it writes into `tasks.md`. That is a file in HEAD's
  tree, so it doesn't depend on commit subjects and survives `[X]` edits.
- Review evidence is the step-completion ledger row `review done <sha>` (data-model.md §2).
  Without it, review re-runs.
- A lost `.git/keel/` costs at most a re-run of analyze or review, unless a unit is open. Then
  `recover` halts on the unattributable changes and the developer decides.

**Commits**: every **work unit** ends in its own commit. All commits are on the feature branch,
and each is preceded by a passing, shown `keel-verify`, plus the evidence the per-unit rule in
data-model.md §7 requires. There is no uncommitted state carried across units or rounds, so:
- the tree is clean between units;
- recovery only ever restores to the unit's BASE (HEAD);
- every later analysis reads committed history.

| Commit | When | Subject contains |
|---|---|---|
| docs | at the end of analyze: spec, plan, research, data model, contracts, quickstart, tasks, keel-written constitution (`feature.json` is never committed) | anything in the host style; identified by the `**Analyzed**` line |
| `T###` | one per task | the task ID |
| `MUT-n` | one per mutation gap-resolution round (new tests and triage file updates) | `MUT-n` |
| test-quality | `test-quality.md`, at the end of mutate | `test-quality` |
| `REV-n` | one per review-fix round | `REV-n` |
| `FIN-n` | one per finish fix or finish re-mutation round | `FIN-n` |
| finish | the Status edit, last | `NNN` |

**Halts** report the condition, the evidence and the step to resume, then end the turn without a
question. The halting conditions are FR-010, FR-012, FR-016, FR-019, FR-020, FR-032 and the spec's
edge cases.

### Branching (FR-013, edge cases)

**`keel-branch ensure`** is local-only.
- **Dirty tree**: it halts. keel never stashes, discards or mixes in the developer's work. The
  exemptions are:
  - `.specify/feature.json` (always);
  - a keel-written constitution and the feature's spec directory, once they are in the ledger;
  - and, when HEAD is the branch named `<feature>`, `specs/<feature>/**` and an untracked
    `.specify/memory/constitution.md` even without a ledger.
- **Unborn HEAD**: it switches HEAD to the feature branch.
- **Otherwise**: it creates the branch from HEAD, or switches to it if it exists.
- **Numbering**: one more than the highest spec directory or local `NNN-*` branch.
- **Base**: resolved from the ledger, then the spec's `**Base**` line, then
  `git merge-base HEAD <default>`, then the empty tree in an unborn repository.
- **Diffs**: two-dot (`<base> HEAD`) everywhere, so they also work against the empty tree.

**Stacking**: a feature started while on another feature branch is created from HEAD. The spec's
`**Base**` line records it, and the final report says it is stacked.

**Constitution placement**: a keel-written constitution is committed on the feature branch with
the docs commit. A second feature started from the default branch before the first is merged
re-runs the constitution step. That is expected.

**Interrupted work unit**: an interruption inside any unit (`T###`, `MUT-n`, `REV-n`, `FIN-n`) is
recovered per data-model.md §5. Between units the tree is clean, so a stop there needs no
recovery.

### Specify, clarify, Gate 1 (FR-002 to FR-006, FR-028)

- **`constitution`**: runs once per repo, or when host instructions change.
  - It builds the constitution from host CLAUDE.md files and *refers* to them.
  - With no instructions, it proposes principles. The developer accepts them as part of Gate 1.
- **`specify`**:
  1. `mem_search` (optional).
  2. Questions one at a time on intent and why, goals, non-goals, anti-goals and missing
     requirements (FR-005).
  3. Writes `spec.md` from the vendored template, plus `## Change Classification` (FR-028).
- **`clarify`**:
  - Runs Spec Kit's ambiguity scan, with up to 5 questions.
  - Ends with **Gate 1**: the spec and classification are presented, and the developer gives one
    approval.
  - Approval writes the Status line and the Path line (`full`, or `light` when the light path is
    accepted). `specify` already wrote the keel-only `**Base**` line together with `spec.md`,
    which is how keel tells its own features from plain Spec Kit ones.
  - A change that touches a contract or persisted data never offers `light` (SC-010).

### Plan, Gate 2, plan review (FR-007 to FR-010)

**Full path**:
1. `mem_search`.
2. Two or three parallel `explorer` agents.
3. Two or three `architect` agents, one lens each (smallest change, clean, pragmatic).
4. Recommendation, then **Gate 2**.
5. Write `plan.md` with `## Design Decision` **as soon as the Gate 2 answer arrives**, recording
   the chosen and rejected designs. A developer's own design is recorded as chosen.
6. Write the Phase 0 and Phase 1 artifacts, then `**Plan status**: complete`.
7. A fresh `plan-reviewer` returns critical flaws, missing assumptions, deltas and GO or NO_GO.
   - NO_GO: revise, then run a new reviewer with the prior output plus a disposition log.
   - The same blocker after 3 rounds: escalate to the developer.
   - A developer resolution is recorded as `**Verdict**: GO (developer decision)`.
   - Rounds are stored with `keel-put` and appended under `## Plan Review`.
8. `mem_save` with key `keel/<NNN-feature>`.

**Re-entry** (resume inside plan):
- If `## Design Decision` already has `**Chosen**:`, the skill skips `mem_search`, the explorers,
  the architects and Gate 2.
- It continues at step 6, or at step 7 if `**Plan status**: complete` is already present.
- Gate 2 is therefore never asked twice (US4-AS1, Principle IV).

**Light path**: `plan.md` states the single design (no Gate 2, no plan review). Then
`**Plan status**: complete` and `mem_save`.


### Tasks and analyze (FR-011, FR-012)

**`tasks`**: Spec Kit's format, test-first, with `[P]` markers kept.
- **Test setup**: when no test command or no test framework is detected (`keel-verify detect`:
  `TESTCMD=none` or `TESTFW=none`), `tasks` adds a non-behavior test-setup task before the first
  behavior task. In Maven, that task names `pom.xml`. Analyze's CRITICAL finding
  is the backstop if it's missing.
- **Behavior tasks** carry their own test: one task covers RED, GREEN and refactor, and names both
  the test path and the production path.
- **Non-behavior tasks**: setup, config, docs.
- keel's tasks template (vendored and edited, with the edit logged in `CHANGELOG.md`) says so.

**`analyze`**: Spec Kit's checks plus keel's.
- A behavior task without a test path is a finding.
- On the light path, a task that touches migrations, schemas or API definitions is CRITICAL.
- Incomplete checklists are findings, never a prompt.
- CRITICAL findings halt.
- **Closing analyze**:
  1. Once the checks pass, `keel-verify --label baseline` runs. It always uses `-fae
     -Dmaven.test.failure.ignore=true` and records the failing set.
  2. A build that doesn't compile halts (edge case).
  3. **No tests yet** (`TESTS=none`, including a repo with nothing to build, `BUILD=none`): the
     baseline passes, and the test-setup task from `tasks` sets up testing (the edge case "the plan
     must establish a way to test the feature"). An undetected build (`BUILD=undetected`) halts
     with a request to define build and test commands in CLAUDE.md.
  4. After the baseline, `git status --porcelain` must be clean apart from the ensure-scope
     exemptions. Build output that isn't ignored (e.g. `target/`) halts with "ignore your build
     output". keel never patches ignore files.
  5. Analyze writes the `**Analyzed**` line (baseline count, build, tests, setup task) and the
     `keel:baseline` comment (command, failing set) into `tasks.md`.
  6. The docs commit stages `specs/<NNN>/**` plus a keel-written constitution, or an untracked
     constitution under the branch-name rule when the ledger was lost.

**SC-006**: after M4, a check runs the vendored `check-prerequisites.sh --json --require-tasks
--include-tasks` and Spec Kit's analyze against keel's artifacts.

### Implement (FR-013 to FR-017)

**Preflight**: confirm that HEAD's `tasks.md` has the `**Analyzed**` line and that the tree is
clean apart from the exemption list.

**Per task**, in `tasks.md` order and **strictly serial** (`[P]` honored as "may"):
1. Record the work-unit row in the ledger: BASE = HEAD (never `HEAD~1`; the tree is clean), unit
   ID and named paths.
2. `keel-brief Tnnn` writes the brief.
3. A fresh `implementer`, preloaded with `tdd` and `debug`, works through `keel-evidence run`.
   It stores its own report with `keel-put` (the orchestrator never retypes it; amended
   2026-11-26 after the full-path trial showed retyped reports shortened).
4. For a behavior task (`keel-diff --kind`), `keel-evidence check` must pass. On failure the task
   gets one re-dispatch; a second failure halts.
5. `keel-diff --unit Tnnn` writes the diff: BASE's tree against a temp-index tree of the working
   tree. Then `task-reviewer` checks spec compliance, RED validity and test quality.
6. Fix loop: at most 5 review rounds. Three failed fixes on one problem halts (FR-016, `debug`).
7. `keel-verify --label Tnnn`. A new failure goes to the `debug` path.
8. Mark `[X]`. Take a fresh `keel-diff --unit Tnnn` at commit time, after the fix rounds, and stage
   exactly its files plus `tasks.md`. `feature.json` is excluded from every temp index. Commit with
   the task ID in the host's style and close the unit (`ok <sha> Tnnn`).

**Statuses**: `NEEDS_CONTEXT` is answered from the artifacts and the task re-dispatched once.
`BLOCKED` halts.

### Mutate (FR-030 to FR-035; [contracts/mutation-runner.md](./contracts/mutation-runner.md))

All task commits exist when mutate starts, so `keel-mutate --base <feature base>` reads committed
history (`<base>..HEAD`).
1. `keel-mutate --base <base>` runs in the background, with a budget.
   - The analysis covers only the changed lines (`in_scope`).
   - Exit 10 means unsupported. `test-quality.md` records `not-run` with the reason (FR-035).
   - Exit 11 (red or flaky) goes to `debug`.
   - Exit 12 (tool failure) halts.
2. `keel-classify --triage` computes the blocking rows: gaps minus triaged keys.
3. Gap resolution runs up to 3 rounds. Each round is a work unit `MUT-n`, and a gap is resolved one
   of two ways:
   - **A test** traceable to an FR or acceptance scenario, written by `implementer` and reviewed by
     `task-reviewer`. It counts only if its target key turns KILLED on the re-run.
   - **A triage row** with its reason, in the committed triage file
     `specs/<NNN>/test-quality.triage.tsv` (keel's addition next to `test-quality.md`). The
     implementer proposes triage rows in its report, and the orchestrator writes them within the
     unit.
   - A test whose target key doesn't turn KILLED stays committed. The next round either fixes it
     or reports it as kills-nothing.
   - Exit 11 during mutate goes to `debug` inside a `MUT-n` unit.

   Each round ends with `keel-diff --kind MUT-n` = `non-behavior` (a production change halts),
   `task-reviewer`, `keel-verify --label MUT-n` and its commit. Then `keel-mutate --base <base>
   --classes <affected>` re-runs. Blocking rows that remain after round 3 halt the run.
4. Redundancy and overlap are reported, never blocking (FR-033).
5. `keel-verify --label test-quality`, then commit `test-quality.md`. The test-quality commit is
   the reference point for finish's re-mutation check.

### Review (FR-018, FR-019)

1. `keel-diff --base` writes the review diff (`<base>..HEAD`, committed).
2. Three parallel `code-reviewer` agents run (simplicity/DRY, correctness, conventions). They report
   findings with severity, confidence ≥ 80, scope and file:line, and each stores its own findings
   with `keel-put`.
3. The orchestrator verifies each finding with the `respond-review` rules.
4. Findings are handled by severity:
   - **Critical or Important `in-design`**: fixed in a work unit `REV-n` by `implementer`, with
     the `intent` and evidence set by the per-unit rule (data-model.md §7): `task-reviewer` first,
     then `keel-verify`, then the commit. Then `keel-verify --label REV-n` and the
     commit, followed by one scoped re-review of `keel-diff --unit REV-n` (the committed range
     `BASE..HEAD` of that unit). At most 3 rounds.
   - **Any verified `changes-design`**: halts the run.
   - **Minor**: fixed if trivial (as a `REV-n` unit), otherwise reported.
5. Append the step-completion row `review done <HEAD>`, also written when there were no fixes.
   Mutation is not re-run here: finish re-checks every production change made after the
   test-quality commit (SC-012).

### Finish (FR-020, FR-021, FR-025)

1. **Re-mutation**: if production files changed between the test-quality commit and HEAD (review
   fixes), run `keel-mutate --base <feature base> --classes <changed since test-quality>`.
   - The test-quality commit is the one that **added** `specs/<f>/test-quality.md`
     (`git log -1 --diff-filter=A -- <path>`), so a later subject mentioning "test-quality" can't
     shift the range.
   - The run reads committed history, so the fix lines are in scope.
   - Gaps are resolved in `FIN-n` gap units exactly as in mutate step 3 (implementer, verify,
     commit). Their triage rows are shown to one scoped `code-reviewer` correctness pass.
   - Exit 10 or a `not-run` result is skipped and reported, never a halt. Exit 11 goes to `debug`
     in a `FIN-n` unit. Exit 12 halts.
2. **Verify**: `keel-verify --label finish` runs the full host build and tests and shows the output.
   - On failure, `debug` runs inside `FIN-n` fix units (implementer, `intent=fix`, at most 3
     attempts on one problem). Each fix is verified and committed.
   - If a fix touches production code, it gets one scoped `code-reviewer` pass on `keel-diff --unit
     FIN-n`. An in-design finding becomes another `FIN-n` unit; `changes-design` halts. Then step 1
     repeats for the classes the fix touched.
   - If verify still fails after 3 attempts, the run halts. A halted summary goes to the final
     report and scratch, never into a commit.
3. **Clean-tree check**: `git status --porcelain` may show only `.specify/feature.json` (unit
   scope). Every unit is already committed, so anything else halts. `FINISH` starts only if the
   `finish` verify ran on the current HEAD. After any `FIN-n` commit, go back to step 1, then
   step 2.
   - **Caps**: at most 3 `FIN-n` units of each kind (gap, verify fix, scoped-review finding), and
     at most 6 passes through steps 1–2 overall. Exceeding either halts the run.
4. **The `FINISH` unit**:
   - Record `finish started <HEAD> FINISH n/a spec.md,test-quality.md` in the ledger.
   - Set `**Status**: Implemented (date)` in `spec.md`.
   - If step 1 ran, append its re-mutation section to `test-quality.md`.
   - If this unit is interrupted, `recover` restores both files and the unit restarts.
5. **Finish commit**: commit both files in the host's style, with no AI co-author trailer where the
   host forbids it. Step 2's verify (made on the same code) is the commit's evidence, the same
   pattern as analyze's docs commit. Then close the unit.
6. `mem_save`, under the same key.
7. **Final report**:
   - commits and gates;
   - the test-quality and review summaries;
   - "not pushed";
   - any host publish instruction that was not followed;
   - any saved partial patches;
   - any tasks the developer committed after a halt (no keel evidence).

### Push guard (FR-022, SC-002; [contracts/push-guard.md](./contracts/push-guard.md))

**Layer A0, git-level environment config (primary for git)**:
- SessionStart writes `GIT_CONFIG_COUNT/KEY/VALUE` into `CLAUDE_ENV_FILE`, appending after any
  existing entries. The entries are a config-defined pre-push hook (`hooks/deny-push`) and an
  empty-prefix `url.keel-blocked-push://.pushInsteadOf`.
- A helper, `git-remote-keel-blocked-push`, gives a clear message.
- **Verified**: every `git push` fails, however it was started: hooks, `!` aliases, `rebase -x`,
  login shells, `xcrun`, `env -P`, absolute paths. The URL rewrite also blocks `--no-verify`,
  while fetch and clone keep working. Plumbing (`send-pack`, `http-push`) is covered only by A
  and B.
- **Functional self-check** (push-guard.md §Self-check), run by every keel step:
  - the hook is listed and enabled;
  - every remote's push URL is rewritten;
  - only keel's `pushInsteadOf` exists, and no `pushurl`;
  - `git` resolves into the shims.

**Layer A, execution-time shims**:
- SessionStart also prepends `plugin/shims/` to PATH and exports `KEEL_ROOT` and the resolved real
  binaries.
- Shims exist for `git`, `gh`, `jj`, `sl`, `gt`, `glab` and `hub`. They give early, clear denials
  with final argv: shell aliases and functions, eval, variables.
- They are the primary layer for `gh` and the non-git tools, which A0 doesn't cover.
- They deny attempts to weaken A0 (`pushInsteadOf`, `hook.*` config writes).
- Recursion guard: `KEEL_SHIM_DEPTH`.

**Layer B, static PreToolUse guard** (anchored matchers, `onFailure: "block"`):
- Shell tools (Bash, Monitor, PowerShell) are checked for:
  - PATH bypasses (absolute paths, `xcrun`, `env` options, `command -p`, PATH edits) after
    unwrapping wrappers;
  - A0 or shim tampering (`GIT_CONFIG_*`, `KEEL_*`, `GIT_EXEC_PATH` assignments or unsets);
  - literal publish commands;
  - literal `sh -c`/`-lc` and `rebase -x`-style payloads, parsed recursively;
  - unresolved command words next to publish vocabulary;
  - forge HTTP writes;
  - inline interpreter payloads.
- GitHub MCP tools are default-deny, except reads and named non-publishing writes.
- Codex runs with full access are denied.

**Settings**: keel is installed per repository with `--scope local`, so its hooks don't run in
other sessions. `defaultEnabled: false` is not used: `claude plugin eval` can't enable such a plugin
(research R7).

**Escape hatch**: `claude --settings '{"disableAllHooks": true}'`.

### engram (FR-025, Principle VI)

- **Reads**: `mem_search` before specify and plan. Relevant hits are cited (FR-004).
- **Writes**: `mem_save` with `topic_key: keel/<NNN-feature>`, type `decision`. It runs after
  Gate 2 (or the light-path plan) and after finish.
- **Prompts**: `judgment_required` is resolved without asking, with `related` or `compatible`.
  Conflicts are noted in the final report.
- **Failure**: every call is conditional on the tool. Errors are swallowed and noted.
- **Not called**: `mem_session_*`, and no other saves during a run.

### Vendoring and provenance (FR-026, Principle III)

- **`plugin/vendor/speckit/`** (0.8.4.dev0, verbatim):
  - `scripts/bash/{common,check-prerequisites}.sh` and the `spec`, `plan`, `tasks`, `checklist`
    and `constitution` templates.
  - Edits are logged in `CHANGELOG.md`: the tasks template's behavior-task-with-test rule, and the
    spec and plan templates' keel marker lines.
  - `setup-plan.sh` and `create-new-feature.sh` aren't vendored; the latter needs the network.
- **`plugin/vendor/superpowers/`** (7.0.2) and **`plugin/vendor/feature-dev/`** (1.0.1): the
  upstream `LICENSE` plus pristine copies of every adapted source.
- **Adapted files** carry a header: `Adapted from <upstream> <version> <path> (<license>)`. Apache
  derivatives also carry §4(b) change notices.
- **`PROVENANCE.md`** has one row per source. The root `NOTICE` attributes all three.

### Standalone capabilities (FR-027)

- `debug` and `verify` are the same skills the flow uses.
- `respond-review` is the procedure `review` uses.
- `test-audit <module>` runs `keel-mutate --module` and `keel-classify`. Its report goes to
  `.git/keel/audit/<ts>/report.md` (written by the script). It doesn't edit build files and needs
  no feature run.
- Each of the four still runs `keel-state require` for the shim check only.

## Testing strategy (keel's own, Principle V)

- **Guard suites**:
  - Layer A0: git runs against a local bare-remote fixture with only the A0 environment, covering
    every bypass form (hooks, `!` aliases, `rebase -x`, login shells, `xcrun`, `env -P`, absolute
    paths, `--no-verify`). The remote must stay unchanged, and fetch and clone must still work.
    The self-check is tested against a `pushurl`, a longer and a tying `pushInsteadOf`,
    `hook.keel-nopush.enabled=false` (the environment `true` must win), a repo with no remotes,
    and a simulated git without config hooks.
  - Layer A: the shims are run directly with argv cases, and through `zsh -ic` with a copy of the
    shell snapshot, to cover aliases and functions.
  - Layer B: hook JSON cases (`deny`, `allow`, `failclosed`), plus the full C1–C3 corpus from plan
    review round 1.
  - Perf checks for both layers.
  - A crash simulation.
- **Script suites** run in temp git repos:
  - `keel-state` at every row and drift case, including:
    - finish meaning done;
    - interleaved features;
    - lost `.git/keel/`;
    - recovery from a mid-task interruption.
  - `keel-branch`: no network (unroutable remote), unborn HEAD, the exemptions.
  - `keel-brief`, `keel-put`, `keel-diff` (kind detection), `keel-evidence` (tree rules),
    `keel-verify` (baseline subset).
  - The PIT XML parser, on a fixture copy of the spike output plus entity and dynamic-test cases.
  - `keel-classify`, on seeded TSVs with triage and scope.
- **Slow tier**: `tests/fixtures/maven-weak/`, with a missing assertion, an untested branch and
  duplicate tests. It must report all three (SC-013), and the POM must stay byte-identical
  (SC-014).
- **Mutation self-check**: sed mutants of the shims, `guard-push.sh`, `keel-classify`,
  `keel-state` and `keel-evidence` must each fail a suite. Survivors are triaged in this feature's
  `test-quality.md`.
- **Eval scenarios**:
  - exactly two gates;
  - plan refused before Gate 1;
  - no light path for a contract change;
  - publish attempts blocked;
  - resume doesn't re-ask Gate 2;
  - an unsupported project reports "not run";
  - same outcome with memory absent.
- **Trials**:
  - M3: a light-path trial through implement.
  - M8: a full trial in a sample repo.
  - Then real PayConductor features (SC-009).
  - Permission prompts are counted during trials (SC-001).

## Verification items (empirical, early milestones)

1. Does Claude Code run user `!` commands with the session env, so that layer A covers them?
2. Do `skills:` frontmatter preloads work in plugin agents in 2.1.332? The docs say yes; confirm.
3. What tool name does the Monitor tool present to matchers, and what is its payload in ws mode?
4. Confirm the `claude plugin eval` case format, `history_file` chaining and graders in 2.1.332.
5. Does the SessionStart `CLAUDE_ENV_FILE` environment apply to subagents' Bash and to
   skill-injected commands? **Decision rule**, if it doesn't:
   1. Restrict the implementer's Bash in its agent `tools` to `Bash(keel-evidence:*)` and
      `Bash(keel-verify:*)`, if patterns are supported there (item 11). Those scripts export A0
      and the shims to everything they spawn, so every implementer shell command is guarded.
   2. If patterns aren't supported, use a PreToolUse `updatedInput` for subagent Bash calls only,
      prefixing the guard environment, and add the prefixed forms to the quickstart allow rules.
   3. Only if both fail: accept layer B alone for the implementer's direct commands. Record it in
      Known limits, and tell the implementer to run all tests and builds through `keel-evidence`
      or `keel-verify`.
6. Do the quickstart allow rules and skill `allowed-tools` apply inside plugin subagents? Does
   `Bash(keel-put:*)` match a here-document call whose body contains `;`, `&&` or `$(`? If not,
   `keel-put` takes a file path written by the Write tool outside `.git` instead.
7. What is the `PreSkillShellCommand` payload, and does `onFailure: "block"` apply to it?
8. Does the env file survive CwdChanged, `/clear`, compaction, resume and fork? Also confirm the
   `/reload-plugins` degraded case: layer B only, and keel runs halt on the self-check.
9. Which git version introduced config-defined hooks (`hook.<name>.event`)? This sets the git
   minimum.
10. Does `-pl <module> -am` work with `mutationCoverage`, given that upstream modules share a
    reports directory? If it does, it may replace the `-f` default (M5).
11. Do plugin agent `tools` accept Bash permission patterns such as `Bash(keel-evidence:*)`?
    (Item 5, decision step 1.)

Already verified on 2026-11-25:
- Plugin `bin/` is appended to PATH.
- A SessionStart `CLAUDE_ENV_FILE` prepend works.
- A shim intercepts zsh aliases and `eval`.
- `CLAUDE_PLUGIN_ROOT` is absent in Bash.
- git's exec-path prepend bypasses shims for hooks, `!` aliases and `rebase -x`.
- A0 blocks all of those, plus login shells, `xcrun`, `env -P` and absolute paths. Its URL rewrite
  also blocks `--no-verify`.
- A longer file-config `pushInsteadOf` and an explicit `pushurl` defeat A0's rewrite, which the
  self-check detects.
- Plumbing (`send-pack`) skips both A0 mechanisms.
- `git hook list`, `get-url --push` and `--show-scope` behave as the self-check needs.

## Project Structure

### Documentation (this feature)

```text
specs/001-spec-to-commit-flow/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md
├── contracts/{push-guard,mutation-runner,run-state,agent-handoffs}.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
.claude-plugin/marketplace.json     # local marketplace; source ./plugin (FR-029)
plugin/                             # the plugin root (no CLAUDE.md here, so validate stays clean)
├── .claude-plugin/plugin.json      # installed per repository (--scope local)
├── skills/{run,constitution,specify,clarify,plan,tasks,analyze,implement,mutate,review,finish,
│           debug,verify,respond-review,test-audit,tdd}/SKILL.md
├── agents/{explorer,architect,plan-reviewer,implementer,task-reviewer,code-reviewer}.md
├── hooks/{hooks.json,session-env.sh,deny-push,guard-push.sh}
├── shims/{git,gh,jj,sl,gt,glab,hub,git-remote-keel-blocked-push}
├── bin/keel-{state,branch,ledger,put,brief,diff,evidence,verify,mutate,classify}
├── lib/{common,json,pit-xml,versions,shim-common,guard-check}.sh, lib/git-builtins.sh
├── templates/{brief,report,test-quality,plan-review,finding}.md
├── vendor/{PROVENANCE.md,CHANGELOG.md,speckit/,superpowers/,feature-dev/}
└── NOTICE
tests/
├── run.sh  lib.sh  mutation-self-check.sh
├── guard/{shims/cases/*.tsv, hook/cases/{deny,allow,failclosed}/*.json, *_test.sh, perf_test.sh}
├── scripts/*_test.sh
├── fixtures/{repos/,pit/,maven-weak/,sample-maven/,surefire/,snapshot/}
├── slow/  trials/RESULTS.md  tools/
└── eval/
specs/  .specify/  .claude/skills/speckit-*   # keel's own development (Spec Kit)
NOTICE  README.md  CLAUDE.md
```

**Structure decision**:
- `plugin/` is the installable root. It keeps keel's development files (specs, tests, CLAUDE.md)
  out of the package and out of `claude plugin validate` warnings.
- `vendor/` is the single vendor area.
- keel's own development keeps using its Spec Kit install until keel can run its own flow.

## Build sequence (feeds tasks.md; each milestone is verifiable on its own)

- **M0 Skeleton**:
  - Contents: marketplace, `plugin.json`, vendor copy, licenses,
    PROVENANCE, CHANGELOG, NOTICE, test harness, `lib/common.sh` (root discovery, portability
    helpers).
  - Check: `claude plugin validate plugin/` passes and the harness is green.
- **M1 Push guard**:
  - Contents:
    - `session-env.sh` (A0 + shims), `deny-push`, the remote helper;
    - `lib/shim-common.sh` and the shims;
    - `lib/json.sh`, `guard-push.sh`, `hooks.json`;
    - layer-tagged corpora with the C1–C3 and K1 cases, the perf checks, the self-check.
  - Verification items 1, 3, 5, 7, 8 and 9.
  - Check:
    - suites green;
    - a live session shows `gp`, a pushing post-commit hook and `zsh -lc 'git push'` blocked;
    - `git stash push` and `git rebase -x 'mvn -q test'` allowed.
- **M2 State scripts**:
  - Contents: `keel-state` (progress + gate candidates, recover, guard self-check),
    `keel-branch`, `keel-ledger`,
    `keel-put`, `keel-brief`, `keel-diff`, `keel-evidence`, `keel-verify`.
  - Check: row, drift and recovery fixtures green.
- **M3 First run through implement, light path**:
  - Skills: `run`, `constitution`, `specify`, `clarify`, `plan` (light path only), `tasks`,
    `analyze` (light), `implement`, `tdd`, `debug`, `verify`.
  - Agents: `implementer`, `task-reviewer`.
  - The quickstart permission block.
  - Verification items 2 and 6.
  - Check: a light-path trial in a sample repo commits every task with evidence and verify output,
    with one approval and no other prompts.
- **M4 Full path**:
  - Contents: `explorer`, `architect`, full `plan` (Gate 2, Design Decision), the `plan-reviewer`
    loop with escalation, full `analyze`.
  - Check: the "two gates" eval, a recorded GO, and SC-006 (vendored `check-prerequisites` and
    Spec Kit analyze accept the artifacts).
- **M5 Mutation**:
  - Contents: `lib/pit-xml.sh`, `keel-classify`, `keel-mutate` (B′), `mutate`, `test-audit`, the
    maven-weak fixture.
  - Verification item 10.
  - Check: SC-013 and SC-014 on the fixture; PayConductor `payment-service` audit report.
- **M6 Review and finish**:
  - Contents: `code-reviewer` lenses, `respond-review`, `review` (severity, scope, intent, `REV-n`
    units), `finish` (re-mutation of post-test-quality changes, `FIN-n` units, the `FINISH`
    unit).
  - Check: a seeded-defect trial, where an in-design finding is fixed and a design change halts;
    the first full end-to-end run on the light path.
- **M7 Resume and memory**:
  - Contents: the resume matrix across every row, plus:
    - interleaved features;
    - mid-task interruption and resume after a halt;
    - an interruption between Gate 2 and `Plan status: complete`;
    - an interruption between a task commit and its ledger write;
    - an interruption between `[X]` and the task commit;
    - an interruption in MUT-2 after MUT-1 was committed;
    - a stop between the MUT-1 commit and the start of MUT-2;
    - a stop between the REV-1 commit and its ledger `ok`;
    - an interruption in FIN-1 after the review was recorded;
    - an interruption between the finish Status edit and the finish commit;
    - resuming 001 from branch 002 with a unit started and a dirty tree (expected: halt);
    - keel-state: `review done` followed by FIN commits (holds), and `review done` followed by a
      commit without an ID (review re-runs);
    - resuming 001 from branch 002 while a unit is started;
    - starting a new feature with a stale `feature.json`, pointing to a plain Spec Kit feature
      or to a finished keel feature;
    - lost `.git/keel/` before and after the docs commit;
    - done after finish.
  - All of this is SC-005. Also engram present and absent (SC-008).
- **M8 Hardening**:
  - Contents: the full eval suite, the mutation self-check, README and quickstart, a full-path
    trial.
  - Check: SC-001 to SC-008 and SC-010 to SC-014 on trials. SC-009 follows real use.

## Risks

1. **Layers A0 and A depend on SessionStart env propagation** (subagents, skill commands, env-file
   lifetime).
   - Mitigation:
     - verification items 5 and 8 at M1;
     - `keel-evidence` and `keel-verify` export the guard env to the commands they spawn;
     - the `keel-state` self-check halts keel runs that would run unguarded;
     - layer B still blocks literal and bypass forms.
2. **Guard false positives in every keel-enabled session**.
   - Mitigation: block publishing only, large allow corpora, `defaultEnabled: false`,
     per-repo enablement, the escape hatch, and messages that say how to run the command
     yourself.
3. **Orchestrator drift** (skipping or repeating a gate).
   - Mitigation: `keel-state require` in every step, latest-first derivation, eval scenarios.
4. **Main-session context growth**.
   - Mitigation: file-based handoffs, short agent returns, and commits at every step, so
     compaction or a new session resumes cleanly.
5. **PIT selection misses tests or a sibling SNAPSHOT is stale**.
   - Mitigation: changed-tests plus naming plus reference selection; the stale-SNAPSHOT warning
     with the `-f` default; `-pl -am` verified at M5; selection printed in the summary.
6. **Per-task full verify is slow on large suites**.
   - Mitigation: host instructions can define a per-task verify command (VII); the full suite
     always runs at finish; long runs go to the background.
7. **bash 3.2 and BSD portability**.
   - Mitigation: suites run under `/bin/bash` 3.2 with BSD tools; no GNU-only flags.

## Complexity Tracking

No unjustified violations. Writes outside the repo are Maven's `~/.m2` cache for pinned tools and
Claude Code's `CLAUDE_ENV_FILE`. Both are covered by the constitution v1.3.0 carve-outs made with
this plan.

## Plan Review

### Round 1 (2026-11-25)

**Verdict**: NO_GO

<details>
<summary>Reviewer output (verbatim)</summary>

Review of keel v1 plan (specs/001-spec-to-commit-flow)

All documents are under /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/ (plan.md, data-model.md, research.md, quickstart.md, contracts/push-guard.md, contracts/run-state.md, contracts/mutation-runner.md, contracts/agent-handoffs.md).

These were checked on this machine:
- The Bash tool shell is zsh with the oh-my-zsh git plugin. `type gp` prints "alias for git push", and 12 aliases expand to `git push`.
- `\bpush\b` matches nothing in BSD awk 20200816 or in bash 3.2 `=~`.
- gh 2.92 has `pr new` (an alias of create), `pr update-branch` and `pr revert`.
- In `mcp__codex__codex-reply` the schema has no `sandbox` field. `mcp__codex__codex` accepts a free-form `config` override.
- The Monitor tool's `command` field is optional (there is a `ws` mode).
- Claude Code docs:
  - `.git` is a protected path. Writes to it are prompted in default and acceptEdits modes, and allow rules cannot pre-approve them.
  - Regex matchers are unanchored.
  - PreToolUse does not fire for skill-injected commands; those go to `PreSkillShellCommand`.
  - `CLAUDE_PLUGIN_ROOT` is not in the Bash tool's environment.
  - Plugin agents support `skills:`.
  - `claude plugin eval` runs each case as one non-interactive session.

## 1. Critical flaws

**C1. Shell aliases and functions bypass the push guard** (push-guard.md §Parsing step 4, G5/G6; plan §Push guard)
- The guard resolves only git and gh aliases. Bash-tool commands run in the user's zsh with profile aliases and functions loaded.
- So `gp`, `gpsup`, `ggpush` and the function `ggp` publish unblocked.
- Claude Code's shell snapshot (`~/.claude/shell-snapshots/snapshot-zsh-*.sh`) contains `alias -- gp='git push'`.
- This fails SC-002 ("aliased") and FR-022 on the maintainer's own machine.

**C2. The command-word step fails open on common forms** (push-guard.md §Parsing 3–4, G1–G3, H1, Registration). All of these pass as written:
- Reserved words and compound commands: `if true; then git push; fi`, `! git push`, `{ git push; }`, `while/for … do git push`.
- A leading redirection: `>/dev/null git push`.
- Paths, escapes and zsh forms: `/usr/bin/git push`, `\git push`, zsh `=git push`, and the dashed form `git-push`.
- Wrappers not on the closed list: `caffeinate`, `xcrun`, `arch`, `script`, `direnv exec`, `mise exec`. keel's own `keel-evidence run … -- git push` also passes.
- `gh pr new`, `gh pr update-branch` (creates a remote commit) and `gh pr revert` (opens a PR).
- Skill-injected `!`git push`` (needs a `PreSkillShellCommand` registration) and the PowerShell tool.

**C3. Fail-closed only works when the payload is visible** (push-guard.md I1, S1, G6, G7). I1 needs publish words in the visible command text, so hidden payloads pass:
- Variables, braces and escapes: `x=push; git $x`, `git ${x}sh`, `git {push,}`, `git pu\sh`.
- Shells fed from stdin, sourced files and command substitution: `echo … | sh`, `sh < f`, `source f`, `. f`, `$(cat f)` as the command word, `xargs git < args`.
- G6 does not say what happens when a non-builtin subcommand resolves to nothing. That leaves config injected in the same command open: `GIT_CONFIG_COUNT/KEY/VALUE`, `--config-env=alias.p=V`, `git config alias.p push && git p`.
- G7 scans only post-* hooks. pre-commit, commit-msg, prepare-commit-msg, reference-transaction (which fires on stash, reset, branch and tag) and pre-auto-gc can all run `git push`.
- It also ignores an inline `-c core.hooksPath=` and `GIT_DIR=`.
- Write/Edit into the hooks dir is unguarded, so the assistant can plant a hook G7 never reads.

**C4. Word boundaries are not portable** (push-guard.md V1; data-model.md §3 `\bT[0-9]{3}\b`)
- `\b` does not work in BSD awk or bash 3.2 regex.
- Implemented as written, the whole vocabulary layer (I1, S1, S2, G6, G7) is a no-op on macOS, and task-commit matching never matches, so every resume reports drift.

**C5. Prompts outside the gates** (agent-handoffs.md §Brief "Write reports/T###.md", §Task review, §Code review finding; data-model.md §4; quickstart.md)
- All scratch is under `.git/keel/`. Write/Edit there, or a visible `>` redirect there, always prompts, and no allow rule fixes it.
- Reviewers are specified to write `reviews/…` and `findings-…` files but have no Write tool.
- The plan has no permission strategy (skill `allowed-tools`, settings rules, subagent behaviour).
- Result: SC-001 and FR-023 ("no other prompts") fail.

**C6. State derivation does not converge** (data-model.md §2; plan §Run control)
- (a) `tasks` is done only when tasks.md is committed, but the tasks commit happens "after analyze passes". So `next` returns `tasks` forever.
- (b) The analyze hash covers spec + plan + tasks. tasks.md changes on every task commit (`[X]`) and spec.md at finish. So `next` falls back to analyze after T001 and after finish.
- (c) Review evidence is the HEAD sha, and the finish commit moves HEAD. After finish, `next` returns `review`, not `done`.
- (d) `specify` is done only if feature.json points to the feature. Resuming 001 after starting 002 re-runs specify.
- Breaks FR-024 and SC-005.

**C7. The first run in a fresh repo halts** (run-state.md §keel-branch; plan §Branching, §Commits; US1-AS1)
- `constitution` writes `.specify/memory/constitution.md` before `keel-branch` runs at the start of specify.
- `keel-branch` counts untracked files as dirty, and its only exemption is on resume.
- The constitution is never committed, so the implement preflight's clean-tree check halts too.
- An untracked `.specify/feature.json` blocks every second feature the same way.
- Committing the constitution on the default branch instead would break FR-013.

**C8. Separate test tasks conflict with per-task evidence and commits** (plan §Tasks and analyze "preceding test task"; run-state.md §keel-evidence)
- A test-only task can never pass `keel-evidence check`, which needs a green run.
- Committing that task red breaks FR-020 and Constitution V.
- Setup, config and docs tasks have no test at all. Every standard tasks.md therefore re-dispatches and halts.

**C9. Most commits have no build and test run before them** (plan §Implement step 7, §Commits along the way; Constitution Check row V)
- Constitution V, FR-020 and SC-003 require build + tests before every commit.
- The per-task, spec, plan and tasks commits run no `verify`. The Constitution Check still claims PASS.
- Review-fix commits made after mutate skip mutation analysis (SC-012).

**C10. Mutation gaps and triage cannot be computed as designed** (mutation-runner.md §Scope, §Output, §keel-classify, §Gap resolution)
- PIT mutates whole changed classes and there is no changed-line filter. Every untested mutant in a legacy class the feature touches becomes a blocking gap (FR-030: "code the feature changed").
- Mutant `id` is stable only within one run, and `keel-classify` takes no triage input. Mutants triaged in round 1 reappear as blocking in later rounds.
- So "resolved" ends up judged by the model, which FR-031 forbids and US3-AS3 depends on.

**C11. US2's independent test cannot pass** (data-model.md §6; spec US2)
- The spec says to start "from an approved Spec Kit plan produced by plain Spec Kit".
- `keel-state require` needs keel-only markers (Approved status, Change Classification, Design Decision, Plan Review GO), so it sends the run back to clarify and plan.

**C12. M3 cannot be verified as written** (plan §Build sequence M3)
- The light path still needs `plan` (single design), and `mutate` and `review` must be done before `finish`.
- M3 includes none of them, so its own check ("light-path trial ends as local commits") cannot pass.

## 2. Missing assumptions

- **Shell model:** the Bash tool runs `$SHELL` (zsh here) with the profile loaded. The guard must model zsh (`=cmd`, `alias -g`, `noglob`, `repeat`) and Claude Code's shell snapshot. Env vars do not persist between Bash calls; cwd does. The guard can rely on that, but the plan should say so.
- **Permissions:** `.git` is a protected path. The run's permission mode is unstated, and it is unverified whether skill `allowed-tools` or settings rules apply inside plugin subagents.
- **Timeouts:** the Bash tool foreground limit is 2 minutes by default and 10 minutes at most. Maven verify and PIT runs can exceed it.
- **Script paths:** `CLAUDE_PLUGIN_ROOT` is absent in Bash, so `bin/` scripts must find `lib/`, `templates/` and `vendor/` from their own path.
- **engram plugin:** installed here, it injects always-on instructions: proactive `mem_save`, a "MANDATORY" `mem_session_summary`, and asking the user on memory conflicts. These contradict FR-023, FR-025, SC-008 and Principle VI unless keel's skills override them or the engram skill is disabled in keel repos. R6 verified only the MCP upsert.
- **Eval harness:** one non-interactive session per case. Multi-turn only through `context.history_file`. Bash needs `--allow-tools` and the OS sandbox. Reports publish to claude.ai unless `--no-publish`. The target is the plugin dir, so `claude plugin eval tests/eval` (quickstart) is wrong.
- **Plugin root:** the plugin root is the repo root and holds CLAUDE.md, so `claude plugin validate` warns (and fails with `--strict`).
- **Enablement:** a user-scope install with `defaultEnabled: true` runs the guard in every session. The maintainer's own `/ship` and `/steward` stop working wherever keel is enabled. A guard crash blocks every Bash call; an escape hatch is needed (`claude --settings '{"disableAllHooks": true}'`).
- **Pre-existing test failures:** no rule says what "passing" means (for example, the failing set is a subset of the baseline).
- **Projects with no tests:** who adds the test harness, and verify halting when no test command exists, are unspecified.
- **Maven:**
  - With `-f`, sibling SNAPSHOT modules come from `~/.m2`, possibly stale or missing, and keel must not `install`.
  - JUnit 4, TestNG and JUnit 6 compatibility of pitest-junit5-plugin 1.2.3 is unchecked.
  - If the host POM configures pitest-maven, its plugin-level config overrides the command-line `-D` values.
  - maven-dependency-plugin and maven-help-plugin are unpinned, so Maven may download them beyond the carve-out.
- **SC-012 and SC-003 vs fixed decisions:** per-task commits necessarily come before mutate (FR-030). The plan must state the interpretation: gaps are resolved before the commits that close the feature. The same applies to doc-only commits if they stay.
- **Mid-task interruption:** resume halts until the developer discards the partial work. This should be stated as the SC-005 interpretation.
- **Constitution placement:** it lives on the feature branch until merged. A second feature started from the default branch before that re-runs the constitution step.
- **Forge coverage:** only github.com, bitbucket.org and GitLab-style URLs are covered. GHE `/api/v3` and Gitea are not. jj, sl, gt, glab and hub are not installed today but are unguarded.
- **Codex:** with `sandbox` omitted, `CODEX_HOME` config decides. `config` or `~/.codex/config.toml` can turn on network in workspace-write.

## 3. Revised plan (deltas only)

**push-guard.md**
- **Registration**
  - Add a `PreSkillShellCommand` entry, and add `PowerShell` to the shell matcher.
  - Anchor regex matchers with `^…$`. Unanchored, the current one also catches `create_pull_request_review`.
  - GitHub MCP: deny by default, except `^(get|list|search)_` and a short list of named writes that don't publish.
  - Add a `Write|Edit|NotebookEdit` matcher that denies writes into the active hooks dir (or `core.hooksPath`, e.g. `.husky/`) when they contain publish commands.
  - Allow Monitor calls that have no `command` (ws mode).
- **Step 4 rewrite**
  - Skip reserved words, leading redirections and zsh precommand modifiers.
  - Normalize the command word: drop a leading `\` and zsh `=`, take the basename, and treat `git-<x>` as `git <x>`.
  - Resolve aliases and functions from the newest Claude Code shell snapshot. Re-parse alias values; parse function bodies. If the snapshot can't be read and the word is not a PATH executable, builtin or keyword, deny (new rule F5).
  - Replace the closed wrapper list with structural argv parsing for `xargs`, `find -exec/-execdir/-ok`, `parallel`, `timeout` and `keel-evidence run … --`.
  - Backstop rule G0: deny any simple command with a `git` or `gh` token (or basename) followed by a publish subcommand.
- **Hidden payloads**
  - X1: if the command word or the git/gh subcommand position holds `$`, a backtick, braces, glob characters or a backslash, substitute literal assignments from the same command. If it is still unresolved, deny.
  - X2: for a shell or interpreter reading stdin, a file or a heredoc, parse what is visible. If the producer isn't literal, deny.
  - Fold `source` and `.` into S1.
  - Parse `bash -c '<literal>'` recursively instead of scanning it for words.
- **Scanning**
  - Use the shell parser, not V1 words, for S1 scripts, `!` aliases, G7 hook files, the invoked Makefile target's recipe and prerequisites, and package.json scripts (add `npm test|start|publish`).
  - Keep V1 for non-shell interpreters and opaque payloads, and apply it to the payload only. This avoids false positives like `rg -l push | xargs sed …` and a Makefile with a `docker push` target.
- **V1 portability:** use `(^|[^A-Za-z0-9_])push([^A-Za-z0-9_]|$)`, set `LC_ALL=C`, and tokenize in one awk pass.
- **G6:** when there is no alias and no `git-<x>` on PATH, deny if `GIT_CONFIG_*`, `--config-env` or `git config … alias.` appears in the same command. Handle `git-lfs` by name (deny `lfs push`) instead of F3.
- **G7:** cover every client hook the command can trigger (pre-*, *-msg, post-*, reference-transaction, post-index-change, pre-auto-gc). Extend the command list to stash, reset, branch, tag, update-ref, worktree, gc and add. Honor inline `-c core.hooksPath`, `GIT_DIR`, `-C` and a preceding `cd`.
- **gh rules**
  - H1: add `pr new`, `pr update-branch`, `pr revert` and `pr reopen`.
  - H2: add `pulls/N/update-branch` and the GraphQL mutations `updatePullRequestBranch`, `revertPullRequest`, `reopenPullRequest`, `enqueuePullRequest`. Parse `-XPOST` and `--method=POST`.
  - H3: let `gh --version`, `gh help` and `gh version` pass.
  - W1: add GHE `/api/v3/` and smart-HTTP `…/git-receive-pack`.
- **T2 (codex):** allow `codex-reply`. Deny `codex` when `config` sets `sandbox_mode` or turns on network, or when `~/.codex/config.toml` does. With `sandbox` absent, use the default from that file.
- **Corpus**
  - Deny cases: every example in C1–C3.
  - Allow cases: `git stash push -m x`, `eval "$(ssh-agent -s)"`, `"$MVN" test`, `git lfs pull`, and the false-positive cases above.
- **plugin.json:** set `defaultEnabled: false`.

**data-model.md §2 and run-state.md §keel-state**
- Derive state latest-first. Find the furthest step with committed evidence; earlier steps are checked only for drift. `done` holds if and only if the finish evidence holds.
- `tasks` is done when tasks.md exists. `analyze` is done when the `tasks` commit exists, and that commit is made only after analyze passes. Drop the hash row.
- `specify` is done when spec.md exists. `keel-state` rewrites feature.json on resume.
- `plan` is done when Design Decision plus a Phase-1-complete marker exist.
- Record a NO_GO escalation outcome as `**Verdict**: GO (developer decision)`.
- Task commits match when the subject *contains* the ID (portable boundary) or carries a `Keel-Task:` trailer where the host allows trailers. Fix "starts with" in data-model.md §2.
- `next` with no feature checks `constitution` first.

**run-state.md §keel-branch**
- `keel-branch ensure` is the first action of `run` (and of standalone `constitution`), before any write.
- Always exempt `.specify/feature.json`, and exempt `.specify/memory/constitution.md` when keel wrote it.
- Commit both with the Gate 1 commit.
- Numbering: one more than the highest of the specs dirs and local `NNN-*` branch names.
- Use two-dot `git diff <base> HEAD` everywhere (three-dot fails on the empty-tree base).

**plan.md §Tasks and §Implement; run-state.md §keel-evidence**
- Each behavior task includes its own test. analyze checks that each one names a test path.
- Non-behavior tasks (no production change, worked out mechanically by `keel-diff`) need only a passing verify. SC-004 counts behavior tasks.
- `keel-evidence` records a temp-index tree id per run. `check` requires the RED tree to have the test but not the production change, and the GREEN tree to have both.
- Add step 6.5: `verify` (build + full suite; the failing set is a subset of the baseline set), output shown, before every task commit.
- Either run verify before the doc commits too, or make Gate 1, Gate 2 and plan-review evidence file-only and commit the docs right after the implement preflight's passing baseline run.
- Re-run `keel-mutate` on the review-fix diff before the review-fix commit.
- Add an "adopt plain Spec Kit feature" path, so US2's independent test can start from a plain Spec Kit plan.

**agent-handoffs.md and quickstart.md (permissions)**
- Agents never write into `.git/keel`. They return their text, and the orchestrator stores it with a new `keel-put <feature> <relpath>` script that reads stdin (no visible redirect).
- Remove "Write reports/T###.md" from the brief template.
- Add skill `allowed-tools` (`Bash(keel-*:*)`, `Bash(git add:*)`, `Bash(git commit:*)`, `Bash(mvn:*)`, `Bash(./mvnw:*)`) and a quickstart `permissions.allow` block.
- New verification item 5: do these rules apply inside plugin subagents?
- Add an eval: zero permission prompts.
- engram: keel skills must say no `mem_session_*` calls, no extra saves during a run, and handle `judgment_required` silently. Document disabling the engram skill in keel repos.

**mutation-runner.md**
- Add `changed-lines.tsv` from `git diff -U0`. Mutants on unchanged lines become `out-of-scope` (reported, not blocking).
- Use a stable mutant key `class|method|desc|line|mutator|indexes`. Add `keel-classify --triage <tsv>`; blocking = gaps minus triaged.
- Compute check 3 from mutations.xml: tests were selected, yet every `coveringTests` is empty or the log says "Ran 0 tests". Drop `-q`; the spike ran without it.
- Use `targetClasses=X,X$*`.
- Normalize `[test-factory]/[dynamic-test]` IDs and decode XML entities (`&lt;init&gt;`). Fall back to a generic form instead of exit 12.
- Multi-module: run from the root with `-pl m -am -DfailWhenNoMutations=false`, or exit 10 with the reason.
- With no junit-platform-engine, or when the host POM already configures pitest-maven, exit 10 with the reason (or take a JUnit 4 path).
- Pin the dependency and help plugin versions.
- List non-Java changed sources as "not analyzed".
- Add a bash `--budget` watchdog (macOS has no GNU `timeout`), and run long commands with `run_in_background`.

**bash 3.2 and BSD notes for lib/ (common.sh, json.sh, pit-xml.sh)**
- bash 3.2 `printf` has no `\u`, and BSD awk `%c` writes bytes: decode ASCII `\u00XX` only.
- `"${a[@]}"` on an empty array fails under `set -u`.
- Keep `=~` patterns in variables.
- Missing on macOS: `timeout`, `tac` (use `tail -r` or awk), `date -d`, `stat -c`, `find -printf`, `xargs -r`.
- Give `mktemp` an explicit template under the scratch dir.
- Measure perf with `TIMEFORMAT=%3R; time …`; bash 3.2 has no `$EPOCHREALTIME` and BSD `date` has no `%N`.

**plan.md §Build sequence**
- M1: add the C1–C3 corpus. Verify the snapshot path and the `PreSkillShellCommand` payload.
- M3: add `plan` (light path) and change the check to "through implement, all tasks committed with evidence". Never ship a stub `not-run`.
- M4: add an SC-006 check with vendored `check-prerequisites.sh --json --require-tasks --include-tasks` and `/speckit-analyze`.
- M7: add interleaved features, a mid-task interruption, `next` = done after finish, and loss of `.git/keel`.
- Evals: `claude plugin eval . --eval-dir tests/eval --no-publish --allow-tools Bash --scaffold`, with gate scenarios as `history_file` chains.

## 4. Verdict

**NO_GO.** On this machine the push guard has verified holes (`gp` and other profile aliases, compound commands, hidden payloads). The state walk never reaches `done`, a fresh repo halts on the first run, scratch under `.git` forces prompts, and the test-task, evidence and commit rules conflict. These must be fixed before task generation.

### Critical Files for Implementation
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/push-guard.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/data-model.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/run-state.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/mutation-runner.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/plan.md

</details>

**Dispositions** (revision 1, 2026-11-25):
- **C1 (shell aliases and functions)**: resolved. Layer A puts execution-time shims first on PATH
  through the SessionStart `CLAUDE_ENV_FILE`. Verified in a probe session: the shim received zsh
  `gp --dry-run` as `push --dry-run`.
- **C2 (command-word fail-open forms)**: resolved.
  - Layer A sees final argv, which covers reserved words, compound commands, redirections,
    wrappers, `\git`, `=git` and `keel-evidence run … -- git push`.
  - Layer B normalizes the command word and skips reserved words and redirections.
  - `gh pr new|update-branch|revert|reopen` were added.
  - The PowerShell matcher was added, and `PreSkillShellCommand` is registered (item 7).
- **C3 (hidden payloads)**: resolved by layer A, because variables, braces, escapes, stdin shells,
  `source`, `$(cat f)` and `xargs` are all expanded before exec.
  - `GIT_CONFIG_*`, `--config-env` and inline or configured aliases are resolved by the real git
    inside the shim.
  - Every git hook runs `git` through the inherited PATH.
  - The G7 hook scan and the hooks-dir Write matcher were dropped as redundant.
- **C4 (`\b` portability)**: resolved. Explicit boundary classes under `LC_ALL=C`, and the
  commit-ID pattern was updated.
- **C5 (prompts outside the gates)**: resolved.
  - Agents return text; the orchestrator stores it with `keel-put` through a here-document.
  - Only scripts write under `.git`.
  - Permission model and allow rules were added, plus skill `allowed-tools` (item 6).
- **C6 (state doesn't converge)**: resolved.
  - Derivation is latest-first.
  - Analyze's evidence is the docs commit; review's is the ledger row or review-fix commits.
  - Finish evidence means done, and specify means spec.md exists.
  - `feature.json` is rewritten on resume.
- **C7 (fresh repo halts)**: resolved.
  - `keel-branch` runs first in `run` and in standalone `constitution`.
  - Exemptions cover `feature.json`, a keel-written constitution and the feature directory.
  - The constitution goes in with the docs commit.
- **C8 (test tasks vs evidence)**: resolved.
  - Behavior tasks carry their own tests; non-behavior tasks need verify only.
  - `keel-evidence` checks tree ids.
- **C9 (verify before commits)**: resolved. `keel-verify` runs before every commit:
  - the docs commit, after the baseline;
  - each task;
  - test-quality;
  - review fixes, after mutation re-runs;
  - finish, with the full suite.
- **C10 (mutation scope and triage)**: resolved.
  - Changed lines set `in_scope`.
  - Mutant keys are stable, and `keel-classify --triage` computes blocking rows.
- **C11 (US2 from plain Spec Kit)**: resolved. `keel-state adopt` / `--adopt`; adopted plans
  still get the plan review.
- **C12 (M3 not verifiable)**: resolved. M3 includes the light-path plan and is checked through
  implement. The first full end-to-end run moves to M6.
- **Missing assumptions**: all resolved in Technical Context, Interpretations, the contracts and
  the quickstart:
  - Shell model, permissions, timeouts and script paths.
  - engram: no prompts, `judgment_required` handled silently, the SC-008 interpretation.
  - Eval command and plugin root (`plugin/`).
  - Enablement: `defaultEnabled: false` plus an escape hatch.
  - Baseline failure semantics, and projects with no tests (`keel-verify` halts with
    `MISSING=test-command`).
  - Maven: reactor `-pl -am` with an `-f` fallback, JUnit 4/TestNG or host-configured PIT give
    "not run", pinned helper plugins.
  - SC-003 and SC-012 interpretations.
  - Constitution placement: accepted as stated.
  - Codex: `config` and `config.toml` rules; `codex-reply` allowed.
- **Mid-task interruption**: resolved differently than suggested. The partial diff is saved to
  scratch, the task's BASE is restored, and the task restarts. Halting would fail SC-005.
- **Deltas rejected as redundant with layer A**:
  - parsing snapshot aliases and functions statically (F5);
  - static payload resolution (X1, X2, S1/S2 parser scans);
  - the full G7 hook list;
  - the hooks-dir Write/Edit matcher.
- **Deferred**:
  - Gitea endpoints: not in use, personal v1.
  - `Keel-Task:` trailer: rejected, because the subject ID is enough and hosts may forbid
    trailers.

### Round 2 (2026-11-25)

**Verdict**: NO_GO

<details>
<summary>Reviewer output (verbatim)</summary>

## 1. Critical flaws

**K1. Layer A has bypasses I reproduced here, so the rejected layer-B deltas are still needed.** (C2/C3 resolved only on paper.) Refs: push-guard.md §Layer A step 3 ("`!shell` alias … inner git calls hit the shim"), §Failure handling ("git hooks (git runs them with the caller's PATH)"), deny corpus lines 195–204; plan.md §Push guard; disposition C3 and "Deltas rejected as redundant".

All of these were run with the scratchpad `pathprobe` shim first on PATH:
- **git puts its own exec-path first for everything it spawns.** `git -c alias.x='!command -v git' x` prints `/Library/Developer/CommandLineTools/usr/libexec/git-core/git`, and the inner PATH starts with that git-core directory, ahead of the shims. `git-core/git` is a real git (a symlink to `../../bin/git`).
  - So a `git push` run from any of these skips the shim: git hooks (pre-commit, post-commit, reference-transaction, husky), `!` aliases, external `git-*` commands, `rebase -x/--exec`, `submodule foreach`, `bisect run`, and pager or editor commands set through config.
  - Rebase must stay allowed, so `git rebase -x 'git push origin HEAD' HEAD~1` publishes.
  - The corpus row "commit with a hook running git push" will fail at M1.
- **Login shells move the shims to the end of PATH.** macOS `path_helper` does this, so `bash -lc` and `zsh -lc` both resolve `/usr/bin/git`. `zsh -lc` also resolves `/opt/homebrew/bin/gh` (via `.zprofile`).
  - Layer B no longer parses `-c` payloads (X2 was rejected), so `zsh -lc 'gh pr create'` passes both layers.
- **`xcrun git push` and `env -P /usr/bin git push` never reach the shim.**
  - B3 doesn't normalize `xcrun`.
  - B2 lists `env -i` and `env -u` but not `env -P`.
- **A variable holding an absolute path gets past layer B.** Example: `G=/opt/homebrew/bin/gh; $G pr create`. B1 only matches literal paths, and X1 was rejected.

**K2. The state machine still can't get from analyze to implement.** (C6 has moved, not been fixed.) Refs: data-model.md §2 (the analyze row's evidence is the docs commit; `require <step>` needs every row before it) vs plan.md §Implement preflight step 4 (the docs commit is made *inside* implement).
- After analyze passes, `next` returns `analyze` again.
- `require implement` exits 3 until the docs commit exists, but only implement makes that commit. M3 will hit this.

**K3. A mid-task resume can't reach recovery, and recovery can wipe the developer's edits.** Refs: plan.md §Run control step 1, run-state.md §keel-branch (dirty tree means exit 3; exemptions are only `feature.json`, the constitution and `specs/NNN/**`), data-model.md §5.
- `run` always calls `keel-branch ensure` first. The partial `src/` changes make the tree dirty, so it halts before §5 runs. The SC-005 interpretation can't be implemented as written.
- §5 treats every change as the task's once "started row + HEAD==BASE" holds. Edits the developer made after the interruption get reverted, and new untracked files get deleted (saved to a patch first). The spec's edge case says not to stash or discard the developer's work.

**K4. The adopt path is broken, so US2's test starting from plain Spec Kit still fails.** (C11 resolved only on paper.) Refs: run-state.md §adopt, data-model.md §2.
- `adopt` doesn't write `**Plan status**: complete`, so the plan row fails.
- If `tasks.md` exists, latest-first picks the tasks row and returns `analyze`, which skips the plan review (FR-010). The alternative is a halt from the drift rule ("marker present while a lower row is missing").
- If `tasks.md` doesn't exist, `next` is `plan`, which re-runs explorers and architects and asks Gate 2 again.

**K5. `keel-verify` can report a false pass whenever the baseline already has failures.** (FR-020, SC-003, the pre-existing-failures edge case.) Ref: run-state.md §keel-verify.
- Maven stops at the first failing module. If the baseline fails in an upstream module, the downstream modules never run, and "failed only on baseline tests" returns pass.
- Old surefire reports in `target/` get counted as current results.
- `--label baseline` has no defined semantics, and the rule "a missing baseline means any failure is fail" makes a red baseline fail against itself. The docs commit then has no passing verify before it.

## 2. Missing assumptions

- **Facts verified on this machine** that belong in push-guard.md:
  - git puts its exec-path first for child processes.
  - login shells run `path_helper`, which moves the shims to the end of PATH.
  - `xcrun` and `env -P` don't search the caller's PATH.
  - `/usr/bin/git` is an xcrun trampoline, about 10 ms per exec.
  - `git --list-cmds=main,others` costs about 16 ms per call, so running it on every call misses the 15 ms target.
- **Threat model**: it should be stated as "the assistant follows instructions or is prompt-injected; it is not an adversary." That is what makes the hidden-in-file residuals acceptable.
- **Shim recursion**: skipping only PATH entries equal to `$KEEL_SHIMS` loops forever when two shim directories are on PATH (a nested `claude -p` or eval with a different plugin root). Also unhandled:
  - empty or relative PATH entries;
  - a directory named `git` (it passes `-x`).
- **Degraded mode**: if SessionStart didn't run (for example, keel enabled mid-session with `/reload-plugins`), only layer B is active for non-keel turns. Say so, or have SessionStart emit `additionalContext`.
- **Untested env-file lifetime**: CwdChanged, `/clear`, compact, resume and fork were not tested. The docs say CwdChanged clears the variables it wrote; whether that also clears SessionStart's is unknown.
- **The `updatedInput` fallback** (verification item 5) has a cost. The docs say permission rules are evaluated against the rewritten input, so `PATH=… git commit` no longer matches the allow rules and triggers prompts. Without a `permissionDecision`, auto mode may deny the call. That puts SC-001 at risk.
- **`Bash(keel-*:*)`** mixes a wildcard with the legacy `:*` form. Verify it matches, or list each script explicitly.
- **Interruptions inside `mutate` or `review`** leave non-exempt dirty files, so the run halts. Record this in the SC-005 interpretation.
- **`feature.json`**: committing it makes it tracked on one branch and untracked on another, which blocks `git switch` between interleaved features.
- **New feature started from a feature branch**: the branch is created from HEAD, so it stacks on the other feature, and the ledger's base and the re-derived merge-base disagree.
- **Unverified Maven and PIT behavior**: the spike only tested `-f`, not `-pl m -am … mutationCoverage`. With `-am` the goal also runs in upstream modules, and they write to the same `reportsDirectory`.
- **Scope wording**: the stated scope covers "updating/reopening a PR", but `gh pr edit` and `gh api -X PATCH repos/o/r/pulls/N -f state=open` are allowed. For `gh api graphql -F query=@file`, the contract doesn't say how the file is read.

## 3. Revised plan (deltas only)

**push-guard.md**
- **New layer A0, a git-level block that doesn't depend on PATH.**
  - SessionStart also exports `GIT_CONFIG_COUNT/KEY/VALUE` that add a config hook: `hook.keel-nopush.event=pre-push` with `hook.keel-nopush.command=<abs>/hooks/deny-push`. If the variables already exist, append at the next index.
  - Verified here: `GIT_CONFIG_COUNT=2 … git hook run pre-push` ran the injected command and exited 1.
  - It covers hooks, `!` aliases, `rebase -x`, `submodule foreach`, `bisect run`, externals, `xcrun`, `env -P`, login shells and absolute paths.
  - Set the git minimum to the first release with `hook.<name>.event` (it is in 2.54).
  - The `keel-state` self-check also checks A0.
  - Optional hardening: a shadow `GIT_EXEC_PATH` whose `git` points to the shim.
- **Fix the shim text** about `!` aliases and hooks. Either expand `!` aliases inside the shim with the shims first on PATH, or attribute those cases to A0.
- **Real-binary discovery:**
  - skip the shim's own resolved directory and any entry whose `git` carries a keel marker;
  - skip empty and relative entries;
  - require `-f` and `-x`;
  - add a `KEEL_SHIM_DEPTH` guard that exits 2 with rule `AF`.
- **Shim performance**: embed the builtin subcommand list, and call `--list-cmds` only for unknown words.
- **Layer B restorations, kept narrow:**
  - Recursively parse literal payloads of `sh|bash|zsh|dash|ksh … -c`, including `-lc` and `--login`. Do the same for `git rebase -x/--exec`, `submodule foreach`, `bisect run`, `-c alias.*=!…`, and `-c core.pager|core.editor|sequence.editor|diff.external=`.
  - Normalize these wrappers to the tool they run: `xcrun`, `env` (all options), `sudo`, `ssh <host> <cmd>`.
  - Deny when the command word is unresolved (`$…`, a backtick, `$(…)`) and the same simple command matches the git or gh publish vocabulary.
  - Deny when any of these appears in the visible text: `--no-verify` together with push, `send-pack` or `http-push`, or an override or unset of `GIT_CONFIG_*` or `hook.keel*`.
- **Corpus**:
  - Deny every K1 example.
  - Allow `git rebase -x 'mvn -q test' HEAD~3` and `bash -lc 'mvn test'`.
- **Known limits**: a hidden-in-file `--no-verify` or `send-pack` run through an absolute path, JGit, and degraded mode.
- **Scope consistency**: either add `gh pr edit` and `PATCH pulls/N` to A4/A5, or narrow the scope text. For `query=@file`, read the file, and deny if it can't be read.

**data-model.md §2 and run-state.md**
- **K2**: `analyze` ends with checks, then `keel-verify --label baseline`, then the docs commit. Implement preflight only confirms the docs commit and a clean tree.
- **K4**: treat gate rows as hard prerequisites. `next` = min(the step after the furthest holding row, the first missing gate among constitution, Gate 1, and plan-review GO or light). `adopt` writes `**Plan status**: complete`, and an adopted feature goes to plan-review, never to Gate 2.
- **Clarify row**: also accept `Implemented (…)`. Otherwise a finish interrupted before its commit drift-halts.
- **K3**: `run` order becomes `keel-state recover`, then `keel-branch ensure`. Skip the dirty check when HEAD is already the feature branch and recovery has handled the tree. Restore only when every changed path appears in a `keel-evidence` tree diff against BASE for that task, or in the task's named paths. Otherwise halt.
- **Docs-commit evidence**: use a fixed token (for example `docs(NNN): spec`). A task commit like "T001 … spec" also stages `tasks.md`, so it matches the current rule.
- **`feature.json`**: don't commit it. Resolution falls back to the branch name.

**run-state.md §keel-verify**
- `--label baseline` passes if the build compiled and reports were produced; it records the failing set.
- If the baseline is red, later runs add `-fae` or `-Dmaven.test.failure.ignore=true`.
- `NEW` also counts tests that ran in the baseline but have no fresh report.
- Ignore reports older than a start marker (`find -newer`).
- Define "compiled" as: no module failed outside surefire or failsafe.

**run-state.md §keel-evidence**
- Rule 3: the RED tree's production paths must equal BASE's. That is what plan.md §Design Decision already claims.
- `--kind`: `src/main/resources/**`, including migrations and config, counts as production.

**mutation-runner.md**
- Re-mutation after review fixes: scope is the feature base, and the classes are those the fix touched plus those whose tests changed or were removed.
- Define the key and resolution of `NO_TEST` rows.
- Verify `-pl -am` with `mutationCoverage` at M5; keep `-f` as the fallback.

**plan.md §Verification items**
- Add:
  - env-file survival across CwdChanged, `/clear`, compact, resume and fork;
  - the `/reload-plugins` case;
  - the cost of the `updatedInput` fallback;
  - the `Bash(keel-*:*)` syntax.
- Prefer having `keel-evidence` and `keel-verify` put the shims first on PATH for the commands they spawn, so subagents are covered without rewriting input.

## 4. Verdict

**NO_GO.** Layer A has bypasses I reproduced on this machine (git's exec-path prepend covers hooks, `!` aliases and `rebase -x`; login shells; `xcrun` and `env -P`), and those are exactly what the rejected layer-B deltas were covering. Separately, the state machine can't get from analyze to implement, and the adopt and mid-task resume paths contradict their contracts. The fixes are all at contract level, and A0 is cheap.

### Critical Files for Implementation
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/push-guard.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/data-model.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/run-state.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/plan.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/mutation-runner.md

</details>

**Dispositions** (revision 2, 2026-11-25):
- **K1 (layer A bypasses)**: resolved with a new layer A0, git-level environment config. A
  config-defined pre-push hook plus an empty-prefix `pushInsteadOf` URL rewrite are inherited by
  every git process. Verified against a local bare remote:
  - blocked: plain push, `!` alias, post-commit hook, `rebase -x` (also with `--no-verify`),
    `zsh -lc`, `xcrun`, `env -P`, absolute path, and `--no-verify` (by the URL rewrite);
  - still working: fetch, ls-remote and clone.
  - The shim text was corrected: `!` aliases and hooks are A0's job.
  - The narrow layer-B restorations were adopted: recursive literal `-c`/`-lc` and `rebase -x`-style
    payloads, wrapper unwrapping (`xcrun`, all `env` options, `sudo`, `ssh`, …), unresolved command
    words next to publish vocabulary, and A0/shim tampering.
  - Remaining risk: a longer file-config `pushInsteadOf` beats A0's rewrite. The self-check halts
    keel runs when one exists, and it is listed as a known limit for ordinary turns.
- **K2 (analyze → implement)**: resolved. Analyze makes the docs commit as its last action, after
  the baseline verify. Implement preflight only confirms it. The commit is identified by adding
  `tasks.md`, not by its subject.
- **K3 (mid-task resume)**: resolved.
  - `keel-state recover` runs before `keel-branch ensure`.
  - Recovery applies only when every changed path is attributable to the interrupted work unit
    (its named paths, or the diff between its BASE and its evidence trees). Otherwise keel halts
    and touches nothing.
  - Work units cover tasks, mutation rounds and review-fix rounds.
- **K4 (adopt)**: resolved.
  - `adopt` writes `**Plan status**: complete` and `**Base**`.
  - Gate prerequisites are hard: `next` is the earlier of the progress candidate and the first
    missing gate, so an adopted feature with `tasks.md` still goes to plan-review and Gate 2 is
    never asked.
  - The clarify row also accepts `Implemented`.
- **K5 (keel-verify false pass)**: resolved.
  - Baseline pass means it compiled and produced reports.
  - A red baseline makes later runs use `-fae -Dmaven.test.failure.ignore=true`.
  - `NEW` includes baseline tests without a fresh report.
  - Stale reports are ignored through a start marker.
  - "Compiled" is defined from the reactor summary.
- **Missing assumptions**:
  - Verified facts were added to push-guard.md.
  - The threat model is stated in the plan Interpretations and push-guard.md.
  - Shim recursion and discovery hardened: `KEEL_SHIM_DEPTH`, a marker skip, empty or relative
    entries skipped, `-f -x` required.
  - Degraded mode is stated, and the quickstart says to start a new session.
  - Env-file lifetime and the `updatedInput` cost became verification items 8 and 5. The primary
    fallback is that `keel-evidence` and `keel-verify` export the guard env.
  - Allow rules now list each script explicitly.
  - Interruptions in mutate or review are covered by work units.
  - `feature.json` is never committed.
  - Stacked features are recorded in `**Base**`.
  - Mutation runs default to the spike-verified `-f`, with `-pl -am` as M5 verification item 10.
  - Scope wording was narrowed to "creating, merging, reopening a PR or updating its branch":
    `PATCH pulls/N state=open` was added and `gh pr edit` is allowed.
  - `query=@file` is read (unreadable → deny).
  - Shim performance: an embedded builtin list and resolved real binaries skip the xcrun
    trampoline.
- **Rejected**: none.
- **Deferred**: an optional shadow `GIT_EXEC_PATH`, because A0 already covers git's child
  processes.

### Round 3 (2026-11-25)

**Verdict**: NO_GO

<details>
<summary>Reviewer output (verbatim)</summary>

Plan review, round 3: keel v1 (specs/001-spec-to-commit-flow)

I read rounds 1–2 and their dispositions, plan.md, data-model.md, the four contracts, quickstart.md, spec.md, constitution v1.3.0 and research.md. I ran experiments in `/private/tmp/claude-501/-Users-javiercardozo-dev-projects-payconductor/e517ffa1-998e-4d0f-9be1-7666010ddcae/scratchpad/a0r3/` (git 2.54, local bare remotes, nothing pushed to a real remote).

**What holds up:**
- Pushes are blocked from inside `submodule foreach` (the A0 env survives into it), and explicit-URL pushes are blocked even with `--no-verify`.
- `git log <empty-tree>..HEAD` works, so the empty-tree base is fine for unborn repos.
- Neither the maintainer's global git config nor PayConductor's has `url.*` or `pushurl` rules, so the self-check won't wrongly halt there.
- K1 (except R3), K2 and K3 are resolved. K5's false pass is fixed.

## 1. Critical flaws

**R1. Projects with no tests, and empty repositories, can never get past analyze.** This is left over from a revision-1 disposition and round 2 didn't catch it. It blocks.
- Refs:
  - run-state.md §keel-verify: "Baseline: RESULT=pass iff … test reports were produced" and "No test command or test reports: exit 3 MISSING=test-command".
  - plan.md §Tasks and analyze, "Closing analyze".
  - data-model.md §2, analyze row.
- The docs commit needs a passing baseline. The baseline needs test reports. The tasks that would add the test harness can only run after the docs commit. So the run deadlocks.
- This breaks the spec edge case "No automated tests in the host project: the plan must establish a way to test the feature". It also breaks the "no commits yet" case when the repo is empty, because there is no build to run yet. A fresh M3 sample repo would hit it.

**R2. Adopt still fails US2's start from plain Spec Kit in both of its common states (K4 is not fully fixed).** It blocks.
- Refs: plan.md §Run control order 1 and §Branching exemptions; run-state.md §keel-branch ("Exempt when keel wrote them … recorded in the ledger by the writing step") and §adopt; data-model.md §2, analyze row.
- (a) Plain Spec Kit leaves `specs/NNN/**` untracked, and often `.specify/memory/constitution.md` too. keel didn't write them, so they aren't exempt. `keel-branch ensure` runs "before any write", so before `adopt`, and halts with `MISSING=clean-tree`.
- (b) The developer committed the artifacts, including `tasks.md`, on the feature branch. Then the analyze row ("first commit in base..HEAD that adds tasks.md") already holds before analyze has run.
  - After plan-review GO, `next` returns implement. FR-012's consistency checks and the baseline are skipped, so keel-verify has no `baseline.failing` or `baseline.ran`.
  - If `tasks.md` was added before `<base>`, the analyze evidence can never hold and analyze loops.

**R3. The A0 self-check doesn't prove A0 works, and the contract overclaims.** I reproduced every case below. Under the stated threat model each one also needs `--no-verify` or git plumbing run through a path that skips the shim, so this is not NO_GO on its own. The fix is cheap.
- Refs: push-guard.md §Verified facts ("loses only to a longer pushInsteadOf …"), §Pieces ("every git process … refuses to push, however it was started"), §Self-check, A8, §Known limits; plan.md Constitution Check row I.
- **An explicit `remote.<name>.pushurl` turns off the URL rewrite.** git's docs say "If a remote has an explicit pushurl, Git will ignore this setting." With the A0 env set, `git push --no-verify origin main` published to the bare remote. The self-check doesn't look at pushurl, and A8 doesn't cover `git remote set-url --push`.
- **A file-config `hook.keel-nopush.enabled=false` disables the hook.** `git hook list pre-push` then shows `disabled keel-nopush`, yet the self-check as written (three command-line entries present) still passes. A git that predates config hooks has the same blind spot: the keys are present but inert, and Linux is a stated target.
- **`git send-pack <url> main` published under A0.** Plumbing skips both the pre-push hook and pushInsteadOf. The shim's A1 rule and layer B's literal match catch it, but A0 doesn't, and Known limits doesn't list it (round 2 suggested listing it).

**R4. Resuming after Gate 2 can ask for the design choice again.**
- Refs: data-model.md §2 plan row, which needs both Design Decision and `Plan status: complete`; plan.md §Plan steps 1–8, which have no re-entry rule.
- Suppose the run is interrupted between step 5 (Design Decision written) and step 6 (Plan status complete). Then `next` returns plan, and the skill re-runs the explorers, the architects and Gate 2.
- That breaks US4-AS1, SC-005 and Principle IV.

**R5. The keel-verify contract will make real multi-module runs halt for no reason.** It never passes wrongly; it fails safe.
- Refs: run-state.md §keel-verify (the `NEW` missing-report clause, the "Red baseline" rule); plan.md Interpretations "Verify scope" and Risk 6.
- **Faster per-task command:** if the host defines one, as VII and Risk 6 allow, most tests in `baseline.ran` don't run. `NEW` is then above 0, so every task's verify fails.
- **Red baseline:** the baseline run itself doesn't use `-fae -Dmaven.test.failure.ignore=true`. A failing upstream module stops the reactor, so the baseline misses downstream tests. Later runs, which do use `-fae`, report those pre-existing failures as new.
- **Removed tests:** tests the feature deletes or renames (refactors, FR-033 merges) count as new failures.
- PayConductor is a 5-module reactor, so it will hit these.

**R6. Two sentences in the state derivation would be implemented wrongly.**
- data-model.md §2 says "evaluate the evidence rows from the bottom up", but the table lists finish at the top. Read literally, the first row that holds is constitution.
- data-model.md §1 derives `base` without the spec's `**Base**` line, which §3 calls the fallback. Without the ledger, a stacked feature gets the merge-base with the default branch. Mutation scope and the review diff then include the parent feature, which breaks FR-030's scope.

## 2. Missing assumptions

- **Resume after a halt:**
  - Halts should append a `halted` unit row. Otherwise `recover` treats the developer's fixes after a halt as an interrupted unit and reverts them into a patch.
  - Say how the developer continues: commit with the task ID and `[X]`, or discard.
  - If the tree is clean and HEAD has moved past BASE (task committed, ledger `ok` missing), `recover` should close the unit, not halt.
- **`untracked-baseline.txt` is always empty.** `keel-branch` halts on any untracked file. Either drop the baseline or define which untracked files are tolerated and keep them out of task diffs and staging.
- **Losing `.git/keel/` before the docs commit** removes the exemptions for keel-written files, so `keel-branch` halts on keel's own spec directory. The claim "costs at most a re-run" only holds after the docs commit.
- **Losing `.git/keel/` after the docs commit** with a red baseline loses `baseline.failing`, so every later verify fails. State this.
- **Verification item 5 has no decision rule.** If the session env doesn't reach subagents, the implementer's non-test commands only have layer B, which misses git's child processes. Say whether v1 accepts that or switches to the `updatedInput` fallback.
- **Re-exporting A0 in keel-verify and keel-evidence** must not append the entries again when they are already present.
- **Layer B rule B2 false positives:**
  - `export PATH=$JAVA_HOME/bin:$PATH && … git …` is denied, and that's a likely pattern for JDK switching between Java 11 and 21 modules.
  - `GIT_CONFIG_NOSYSTEM=` and `GIT_CONFIG_GLOBAL=` don't weaken A0 but are denied.
- **The implementer brief** should also say: no stash, reset, checkout or clean.
- **Adopted specs** have no `## Change Classification`. Say that analyze doesn't flag this.

## 3. Revised plan (deltas only)

**push-guard.md**
- **Fourth A0 entry:** `hook.keel-nopush.enabled=true`, making the count N+4. I verified that the env value beats a file-config `false`.
- **Functional self-check**, replacing the pushInsteadOf check:
  1. `git hook list pre-push` lists `keel-nopush` without a `disabled` prefix. This also proves git is new enough.
  2. For every remote, every value of `git remote get-url --push <r>` starts with `keel-blocked-push://`. This catches pushurl and longer pushInsteadOf rules.
  3. `command -v git` is in `$KEEL_SHIMS`.
- **Verified facts:** add pushurl, and that `send-pack`/`http-push` skip both A0 mechanisms.
- **§Pieces wording:** change it to "every `git push`, however started; plumbing is A/B only".
- **A8 and B2:** also deny `remote.*.pushurl` writes and `git remote set-url --push`.
- **Known limits:** add file-hidden `send-pack`/`http-push`, and pushurl remotes on ordinary turns.
- **Deny corpus:** add pushurl with `--no-verify` and `enabled=false`, both expected to fail the self-check. Tag `send-pack` as A/B.
- **B2:** for a PATH prepend, deny only if a prepended directory contains `git`, `gh`, `jj`, `sl`, `gt`, `glab` or `hub` (`-x` check at hook time). Limit the `GIT_CONFIG_*` rule to `COUNT`, `KEY_*`, `VALUE_*` and `PARAMETERS`.

**run-state.md §keel-verify, and plan.md Interpretations**
- **Baseline flags:** the baseline always runs with `-fae -Dmaven.test.failure.ignore=true`. Later labels add them only if `baseline.failing` is non-empty.
- **Baseline with no tests:** `RESULT=pass TESTS=none` if the build compiles. In an empty repo with no build files, `RESULT=pass BUILD=none TESTS=none`. Show the output either way.
- **Analyze:** a CRITICAL finding if `TESTS=none` and `tasks.md` has no task that sets up a test command.
- **When `MISSING=test-command` halts:** only after that task, or at the first behavior task, if there is still no command.
- **SC-003 interpretation:** for the docs commit in a repo with no build, the shown "nothing to build or test" baseline counts.
- **`NEW` missing-report clause:** it applies only when the label's command equals the baseline command (finish always runs the full one). It excludes tests whose source file the feature changed or deleted.

**data-model.md §1–§5, run-state.md §keel-state and §keel-branch, plan.md §Plan, §Run control, §Commits**
- **Row order:** change "from the bottom up" to "from finish (top row) downward".
- **Base order:** ledger, then the spec's `**Base**` line, then merge-base, then the empty tree.
- **Analyze evidence:**
  - Analyze writes the header line `**Analyzed**: <date> (baseline <n> failing)` into `tasks.md`, then makes the docs commit.
  - The evidence is that HEAD's tree has this line.
  - It survives `[X]` edits, works when `tasks.md` was committed earlier, and doesn't depend on the subject.
  - Confirm at M4 that SC-006 tolerates the line.
- **Adopt:** `keel-branch ensure --adopt` records `specs/<NNN>/**` and an existing constitution as belonging to the feature, in the ledger, before the dirty check. `adopt` then writes the markers.
- **keel-branch:** when HEAD is the branch named `<feature>`, exempt `specs/<feature>/**` even without a ledger.
- **Docs commit:** stage `specs/<NNN>/**` (which includes `checklists/`) plus a keel-written constitution, not a file list.
- **Plan skill re-entry:**
  - If `## Design Decision` has `**Chosen**:`, skip `mem_search`, the explorers, the architects and Gate 2. Go to step 6, or to step 7 if `Plan status: complete`.
  - Write the Design Decision as soon as the Gate 2 answer arrives.
  - Add "interrupt between Gate 2 and Plan status complete" to the M7 matrix.
- **Recover:**
  - Halts append `<step> halted <ref> <unit>`.
  - `recover` acts only when the unit's last row is `started`.
  - With a clean tree, HEAD past BASE and a matching commit, it appends `ok` and returns `RECOVERED=none`.

## 4. Verdict

**NO_GO.** K1–K3 and K5's false pass are fixed. But the docs commit still waits on a baseline that needs test reports, so projects without tests and empty repos can never reach implement, against a spec edge case (R1). And adopt still fails US2's start from plain Spec Kit in both its common states (R2). These and R3–R6 are all contract-text fixes, with no redesign and no change to the fixed decisions, so round 4 should be short.

### Critical Files for Implementation
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/run-state.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/data-model.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/push-guard.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/plan.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/mutation-runner.md

</details>

**Dispositions** (revision 3, 2026-11-25):
- **R1 (no tests or empty repo)**: resolved.
  - A baseline with `TESTS=none`, or `BUILD=none TESTS=none`, passes when the build compiles, and
    its output is shown.
  - Analyze reports CRITICAL if no test-setup task precedes the first behavior task.
  - `MISSING=test-command` fires only at the first behavior task.
- **R2 (adopt)**: **escalated to the maintainer**. This blocker survived 3 rounds (C11 → K4 → R2).
  - Applied already: the `**Analyzed**` line is analyze's evidence, which fixes R2(b): artifacts
    the developer committed no longer skip analyze or the baseline.
  - Pending the maintainer's decision: the R2(a) fix (`keel-branch ensure --adopt` claims
    untracked Spec Kit artifacts) versus dropping adoption from v1.
- **R3 (A0 self-check)**: resolved.
  - Added a fourth entry, `hook.keel-nopush.enabled=true`.
  - The self-check is now functional: `git hook list pre-push` lists `keel-nopush`, and every
    `git remote get-url --push --all` URL starts with `keel-blocked-push://`.
  - Verified on git 2.54:
    - the env `enabled=true` beats a file-config `false`;
    - `get-url --push` shows the rewritten URL, and shows the real URL when a pushurl is set.
  - A8/B2 now cover `remote.*.pushurl` and `remote set-url --push`.
  - Plumbing is listed as A/B-only, in Known limits and the corpus.
- **R4 (Gate 2 re-ask)**: resolved.
  - The Design Decision is written as soon as Gate 2 is answered.
  - The re-entry rule skips explorers, architects and Gate 2.
  - Added to the M7 matrix.
- **R5 (keel-verify false halts)**: resolved.
  - The baseline always runs with `-fae -Dmaven.test.failure.ignore=true`.
  - The missing-report clause applies only when the command equals `baseline.cmd`, and it excludes
    tests whose files the feature changed or deleted.
- **R6 (derivation wording)**: resolved.
  - The rows are read from finish (the top row) downward.
  - Base order: ledger, then the spec's `**Base**` line, then merge-base, then the empty tree.
- **Missing assumptions**: all resolved.
  - Halted unit rows and closing a unit after its commit.
  - Untracked baseline dropped: untracked files halt, and finish requires `git status --porcelain`
    to be empty.
  - `.git/keel/` loss: before the docs commit the branch-name exemption covers it; after it, the
    baseline failing set comes back from `tasks.md`.
  - Item 5 decision rule, with the agent `tools` Bash patterns as new item 11.
  - Idempotent A0 re-export.
  - B2 false positives: a JDK PATH prepend and `GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL` now pass.
  - Implementer brief: no tree, index or ref-changing git; tests only through `keel-evidence` and
    `keel-verify`.
  - Adopted specs without a Change Classification: pending the R2 decision.

**Maintainer decision on the escalated blocker** (2026-11-25): R2, which ran C11 → K4 → R2, is
resolved by **dropping adoption of plain Spec Kit features from v1**.
- In the spec, US2's independent test now starts from a keel-made plan, a new Assumption records
  the scope boundary, and checklist iteration 4 is logged.
- `keel-state adopt` and `--adopt` were removed. A spec without keel markers halts with
  `not-a-keel-feature`.
- The adopted-spec Change Classification item is moot.
- R2(b) is still covered by the `**Analyzed**` evidence line.

### Round 4 (2026-11-25)

**Verdict**: NO_GO

<details>
<summary>Reviewer output (verbatim)</summary>

Plan review, round 4: keel v1 (specs/001-spec-to-commit-flow)

I read rounds 1–3, their dispositions, the maintainer's decision, plan.md, data-model.md, the four contracts, quickstart.md, spec.md with the 2026-11-25 amendment, checklists/requirements.md, constitution v1.3.0 and research.md. Throwaway probes ran only in `/private/tmp/claude-501/-Users-javiercardozo-dev-projects-payconductor/e517ffa1-998e-4d0f-9be1-7666010ddcae/scratchpad/r4probe/` on git 2.54. Nothing in the keel repo was changed.

**Where the round-3 items stand**
- **R4**: resolved (plan.md §Plan "Re-entry", M7 matrix).
- **R6**: resolved in data-model.md. One stale sentence remains (delta).
- **R3**: resolved in push-guard.md. plan.md and run-state.md still carry the old presence-check wording (delta).
- **R5**: resolved, except one detail about comparing commands (delta).
- **R1**: only half fixed. See N3.
- **R2**: dropped by the maintainer. spec.md, the checklist and quickstart.md agree with that. No adopt references are left dangling; data-model §2's "works when tasks.md was committed earlier" is harmless leftover text. The halt that replaces adopt has a flaw, though: see N1.
- **Round-3 missing assumptions**: resolved, except two:
  - `feature.json` against the new clean-tree rule (N2);
  - recovery cases with no defined outcome (delta).

## 1. Critical flaws

**N1. The not-a-keel-feature test misclassifies keel's own features, and starting a new feature can resolve to the wrong one.** Introduced in revision 3.
- **Refs**:
  - run-state.md §keel-state, "No adoption in v1": "a spec without keel's Status, Path and Base lines";
  - plan.md §Specify, clarify, Gate 1: "Approval writes the Status line, and the Path line when the light path is accepted";
  - run-state.md `PATH=<full|light|unknown>`;
  - .specify/templates/spec-template.md line 5: `**Status**: Draft`.
- **Status can't tell them apart**: Spec Kit's own template already writes `**Status**: Draft`.
- **Path isn't written until Gate 1**, and the plan's wording says it is written only when the light path is accepted. Read literally:
  - `next` halts right after `specify` on every run, before clarify;
  - it halts again on every full-path feature after Gate 1;
  - this breaks FR-023, FR-024 and SC-005, and the M3 check would fail on its first run.
- **The new feature isn't bound**:
  - Feature resolution goes `--feature`, then `feature.json`, then the branch, and `feature.json` is rewritten only "when resuming".
  - In a Spec Kit repo (US1-AS5), `feature.json` names the last plain feature. Any `next` or `require` called without `--feature` after `keel-branch ensure` therefore halts with `not-a-keel-feature`.
  - In a keel repo with a finished feature, the same call returns `done`.
  - No contract says the run binds the new feature.
- **Fix**:
  - The test becomes: `spec.md` exists and has no `**Base**:` line. That line is keel-only and is written by `specify` together with `spec.md`.
  - Gate 1 writes `**Path**: full|light` for both paths.
  - Starting a new feature writes `feature.json`.
  - `next --feature X` rewrites `feature.json` whenever it differs, not only on resume.
  - `run` passes `--feature` to every script and step skill.

**N2. The clean-tree checks can't pass while keel's own `.specify/feature.json` is never committed.** Revision 3 added "finish requires `git status --porcelain` to be empty".
- **Refs**:
  - plan.md §Finish step 4, and §Implement preflight ("the tree is clean");
  - run-state.md §keel-branch, "Untracked files";
  - data-model.md §3 ("never committed");
  - plan.md Constitution Check row VII ("no ignore-file patching").
- **Why it fails**:
  - keel writes `feature.json`, never commits it, and never ignores it.
  - In a fresh repo, and in the keel repo itself (no .gitignore), `git status --porcelain` always shows `?? .specify/feature.json`.
  - So the finish check fails on every run (US2-AS1, "the working tree is clean"). The implement preflight fails too if it uses porcelain.
  - If the host tracks `feature.json`, keel's rewrite leaves it modified, with the same result.
- **Fix**:
  - Use one exemption list (`feature.json`) for `keel-branch`, the implement preflight and finish.
  - Finish requires porcelain to be empty apart from `feature.json`.
  - Say what finish does if the check fails. The finish commit already makes `next` return `done`, so either report it, or run the check before committing, when the Status edit is the only expected change.

**N3. R1 is only half fixed: verify runs after the baseline still deadlock projects with no tests.**
- **Refs**:
  - run-state.md §keel-verify, last bullet: "No test command or test reports: exit 3 with MISSING=test-command";
  - the same section: "No tests yet … It never fires at baseline";
  - "Later labels", which has no `TESTS=none` or `BUILD=none` meaning;
  - plan.md Constitution Check row V: "pass = compiled with reports".
- **The two rules contradict each other.** Implemented literally, the test-setup task's own verify fails:
  - A Maven project with a harness but no test yet produces no surefire reports.
  - So T001 can't be committed, and the deadlock just moves from analyze to the first task.
- **Later labels define pass only as "compiled and NEW=0".** With `BUILD=none` (an empty repo before the setup task creates the build), there is no command to pass after `--`.
- **"Right after the task that sets up the test harness" can't be evaluated.** `keel-verify` only receives `--label T###`, and nothing records which task does the setup.
- **Fix**:
  - Delete that bullet.
  - Later labels: no reports gives `RESULT=pass TESTS=none`; no build gives `RESULT=pass BUILD=none TESTS=none`, with the output shown either way.
  - `MISSING=test-command` fires only at the first behavior task, when no test command can be detected.
  - Analyze records the state in the `**Analyzed**` line, e.g. `(baseline 0 failing; tests none; setup T002)`, so it survives losing `.git/keel/`.
  - Fix the row V wording.

## 2. Missing assumptions

- **PayConductor's current state**: `?? .specify/`, `?? CLAUDE.md`, ` M pom.xml`. `keel-branch` will halt there, which is correct per the edge case. US1-AS5 and the SC-009 trials therefore need Spec Kit's files and CLAUDE.md committed first. Say so in the quickstart.
- **`.claude/settings.local.json` must be git-ignored.** On this machine it is, through `~/.config/git/ignore` (`**/.claude/settings.local.json`). Where it isn't, every run halts at `keel-branch`.
- **Build detection is Maven-only.** A non-Maven repo with no host command gets `BUILD=none` at baseline even when it has sources and tests. It should be reported as `BUILD=undetected`, not "nothing to build".
- **Heredoc permissions are unverified.** Nobody has checked that `Bash(keel-put:*)` matches heredoc calls whose body contains `;`, `&&` or `$(`, which agent reports will. Prompts there would break SC-001. Add it to verification item 6.
- **Starting a second feature, or switching to it**, while the first feature's docs are uncommitted halts, because `specs/<other>/**` isn't exempt. State this.
- **SC-014** ("zero changes to build files") conflicts with a test-setup task that edits `pom.xml`. Record data-model §7's "except through a task" as an Interpretation.
- **Tasks the developer commits after a halt** have no keel RED/GREEN evidence (SC-004). The final report should list them.
- **Debug fixes during finish** (plan.md §Finish step 1) change production code after mutate and review, with no re-mutation and no re-review. That contradicts the SC-012 interpretation, which covers the finish commit.

## 3. Revised plan (deltas only)

**data-model.md §2 and §5; run-state.md §keel-state and §keel-ledger**
- **Review row**: only a step-completion row counts as evidence (`review done <sha>`, or `review ok <sha>` with no unit field), written after the review-fix commit.
  - Unit closures (`review ok <sha> REV-n`) must never count.
  - Otherwise a REV unit closed at the end of its round, before its commit, makes `next` return `finish`, which skips re-mutation and re-review.
- **Recover, cases with no defined outcome**:
  - Clean tree, HEAD past BASE, no matching commit: append `abandoned` and return `RECOVERED=none`. Today this halts on every resume.
  - Clean tree, not on the feature branch: wait until `keel-branch ensure` has run, then check again.
  - Define "matching commit" per unit type: `T###` by its ID, `MUT-n` by `test-quality`, `REV-n` by `review`.
- **Mutation and review-fix rounds**: these rounds don't commit, so HEAD is the same for each one. Record a start tree for each unit (a temp-index `write-tree`) and restore to it, not to BASE. Otherwise interrupting round n reverts round n−1's finished work.
- **Unit attribution**:
  - Count the unit's own `[X]` edit in tasks.md as attributable. Otherwise an interruption between `[X]` and the commit halts or reports drift.
  - Write partial patches with `git diff --binary`.
- **Branch-name exemption**: also cover an untracked `.specify/memory/constitution.md`. This is the fresh-repo case where `.git/keel/` is lost before the docs commit.
- **Exit 5 wording**: the run-state.md exit-5 row and data-model §2's "Exits 5 when the push shim is not active" should list the three functional checks instead.

**run-state.md §keel-verify, and mutation-runner.md**
- **Missing-report clause**: compare commands while ignoring the keel-added `-fae -Dmaven.test.failure.ignore=true`.
  - As written, a green baseline's command never equals finish's, so the clause never applies at finish.
  - Persist `baseline.cmd` in the keel comment in tasks.md.
  - Define what "finish compares against the full suite" means when `ran` is unknown.
- **`keel-mutate`**: exclude tests in `baseline.failing` from the selection and report them. Otherwise a red baseline gives exit 11 on failures unrelated to the feature.
- **`keel:baseline-failing` comment**: a test ID containing `--` ends the HTML comment early. Escape it or use another delimiter.

**push-guard.md**
- **Self-check item 2** passes vacuously in a repo with no remotes. Also require:
  - `git config --show-scope --get-regexp '^url\..*\.pushinsteadof$'` lists only keel's `command`-scope entry;
  - no `remote.*.pushurl` exists.
  - Verified here on 2.54: it prints `command url.keel-blocked-push://.pushinsteadof`.
  - A `-c remote.x.url=…` probe doesn't work as an alternative ("No such remote").
- **B2's PATH clause** says to deny when `$KEEL_SHIMS` is dropped "from the front". That denies the very JDK example it then says passes. Reword it:
  - Deny if the resulting PATH leaves out `$KEEL_SHIMS`, or puts a directory holding one of the seven tools before it.
  - For an entry that can't be expanded at hook time (`$(…)`, or a variable that is neither assigned literally in the same command nor set in the hook's environment), deny only if the same command names one of the tools or runs a script or an unresolved command word.

**plan.md**
- **§Push guard, A0**:
  - Replace the presence-style self-check bullet and "every git process is covered" with the wording from push-guard.md §Self-check and §Pieces.
  - Testing strategy: test the self-check against a pushurl, a longer or tying `pushInsteadOf`, `enabled=false`, and a git without config hooks.
  - "Already verified": add pushurl and plumbing.
- **§Branching, Base**: put the spec's `**Base**` line before merge-base, as data-model.md §1 already does (R6).
- **§Tasks**: `tasks` should add the test-setup task itself when no test command is detected, using the same detection as `keel-verify`. Analyze's CRITICAL finding then becomes a backstop, instead of halting every run in a project with no tests.
- **§Finish**: treat debug fixes there as a unit (`FIN-n`). If they touch production code, re-run `keel-mutate` and one scoped review before the finish commit.
- **Verification items**: add the heredoc permission check.
- **M7 matrix**: add these cases:
  - an interruption in MUT-2 after MUT-1 finished;
  - an interruption between `[X]` and the task commit;
  - resuming 001 from branch 002 while a unit is started;
  - starting a new feature with a stale `feature.json`, both from a plain Spec Kit feature and from a finished keel feature.

## 4. Verdict

**NO_GO.** Revision 3 introduced three contradictions in the contracts, and each would produce wrong code on the main path:
- N1: the keel-feature test halts keel's own runs right after specify.
- N2: the clean-tree checks can't pass with keel's untracked `feature.json`.
- N3: `keel-verify` still deadlocks projects with no tests, now at the setup task.

Each is a one-line text fix with no redesign and no change to the fixed decisions, so round 5 should only need to check the diff.

### Critical Files for Implementation
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/run-state.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/data-model.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/plan.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/push-guard.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/mutation-runner.md

</details>

**Dispositions** (revision 4, 2026-11-25):
- **N1 (feature identity and binding)**: resolved.
  - A feature is a keel feature iff its spec has the `**Base**:` line, which `specify` writes
    together with `spec.md`.
  - Gate 1 writes `**Path**` for both paths.
  - `run` binds a new feature: `next-number`, then `ensure`, then it writes `feature.json`.
  - `run` passes `--feature` everywhere, and `next --feature` rewrites `feature.json` whenever it
    differs.
- **N2 (clean tree vs `feature.json`)**: resolved.
  - One exemption list (`.specify/feature.json`) is shared by `keel-branch`, the implement
    preflight and finish.
  - Finish checks porcelain *before* its commit, against the expected changes, and halts on
    anything else.
- **N3 (no-tests deadlock)**: resolved.
  - The contradictory bullet is deleted.
  - Later labels pass with `TESTS=none` or `BUILD=none`, with the output shown.
  - `MISSING=test-command` fires only at behavior tasks.
  - `tasks` adds the test-setup task itself, and analyze's CRITICAL is the backstop.
  - The `**Analyzed**` line records build, tests and setup state.
  - `BUILD=undetected` halts, asking for host commands.
  - The row V wording is fixed.
- **Deltas adopted**:
  - The review evidence is a step-completion row (`review done <sha>`); unit closures never count.
  - Recover gets defined outcomes: `abandoned` when no commit matches, deferral when off-branch,
    and a matching-commit rule per unit type.
  - Each unit records a `start-tree`, and restore goes to the start tree (MUT/REV rounds).
  - The unit's own `[X]` counts as attributable, and patches use `git diff --binary`.
  - The branch-name exemption also covers an untracked constitution.
  - The exit-5 wording lists the functional checks.
  - The missing-report clause compares commands minus keel's flags. `baseline.cmd` is persisted.
    With `ran` unknown, the clause is skipped.
  - `keel-mutate` excludes baseline-failing tests.
  - The comment uses percent-escaping.
  - The self-check adds the `--show-scope` and `pushurl` checks, so it doesn't pass vacuously
    with no remotes.
  - B2's PATH clause was reworded (result-PATH based, with a rule for unexpanded entries).
  - plan.md A0 wording and testing cases were updated.
  - Base order fixed in §Branching.
  - Finish debug fixes became `FIN-n` units, with re-mutation and one scoped review.
  - Verification item 6 now covers the here-document permission check, with a fallback.
  - The M7 matrix gained the listed cases.
- **Missing assumptions**: resolved.
  - The quickstart covers the pre-run clean tree (PayConductor's pending files) and git-ignored
    `settings.local.json`.
  - Second-feature-while-uncommitted halting is stated.
  - SC-014 and SC-004 (developer commits after a halt) interpretations were added.
  - Undetected builds are reported, not treated as "nothing to build".
- **Rejected**: none. **Deferred**: none.

### Round 5 (2026-11-25)

**Verdict**: NO_GO

<details>
<summary>Reviewer output (verbatim)</summary>

Plan review, round 5: keel v1 (specs/001-spec-to-commit-flow)

I read round 4 and its dispositions, plan.md, data-model.md, the four contracts, quickstart.md, spec.md, constitution v1.3.0 and research.md. I ran two probes on git 2.54, only in `/private/tmp/claude-501/-Users-javiercardozo-dev-projects-payconductor/e517ffa1-998e-4d0f-9be1-7666010ddcae/scratchpad/r5probe/`. Nothing in the keel repo was changed.

## 1. Critical flaws

**Status of the round-4 items**

- **N1 is resolved.** It is consistent across run-state.md §keel-state, data-model §1 and §3, plan.md §Run control and §Specify/clarify, and quickstart.md:
  - the keel-feature test is the `**Base**:` line;
  - Gate 1 writes `**Path**` for both paths;
  - `run` binds the feature with next-number, then `ensure`, then `feature.json`;
  - `--feature` is passed everywhere.
- **N2 is resolved.** One exemption list is used by `keel-branch`, the implement preflight and finish, and finish checks before it commits.
- **N3 is resolved.** The contradictory bullet is gone. Later labels can pass with `TESTS=none` or `BUILD=none`. `MISSING=test-command` fires only at behavior tasks, `tasks` adds the setup task, `BUILD=undetected` halts, and row V is fixed.
- **Round-4 deltas and missing assumptions:** all present. Small leftovers are listed under section 3.

Two contradictions remain. Implementation would follow the contracts and get both of them wrong.

**C1. Resuming after an interruption between rounds, in mutate, review or finish, halts at `keel-branch ensure`.** Revision 4 introduced this: it changed restore to go to the start tree and added the matching M7 test case, but did not update the dirty-tree rule.

- **Refs**:
  - data-model.md §5, Recovery step 2 ("restore … to `start-tree` … keeps round n−1's finished work");
  - data-model.md §5, last paragraph ("`keel-branch ensure` then sees the clean (recovered) tree");
  - run-state.md §keel-branch, Dirty tree ("applies only to paths `recover` didn't handle");
  - plan.md §Build sequence, M7 ("an interruption in MUT-2 after MUT-1 finished");
  - plan.md §Interpretations, SC-005.
- **Why it fails**:
  - Mutation, review-fix and finish rounds don't commit, so round 1's finished work stays uncommitted. After recovering MUT-2, the tree still has MUT-1's changes.
  - The probe confirmed this: after the restore, `git status --porcelain` shows ` M A.java` and `?? T1.java`.
  - Those paths are outside every exemption. `ensure` therefore exits 3 with `MISSING=clean-tree`, and the M7 case fails.
  - A plain stop between rounds also halts, because there is no started unit at all.
- **Second, related bug**:
  - `git diff --binary <start-tree>` compares against the real index. The probe showed that a start tree holding MUT-1's *untracked* test reports that file as **deleted** and omits new untracked files.
  - Recovery's attribution check and its patch would then be wrong. Attribution would halt with `HALT=unattributed-changes`.
- **Fix (text only)**:
  - Add `<end-tree>` to the `ok` row of MUT, REV and FIN units.
  - When HEAD is already the feature branch, `keel-branch ensure` also exempts paths in the HEAD→end-tree diff of the latest closed unit whose BASE is HEAD, as long as their working-tree content matches that end tree. Anything else still halts.
  - Every start-tree comparison diffs two trees: `<start-tree>` against a fresh temp-index `write-tree` of the working tree. Never use `git diff <tree>`.
  - Restore only the paths present in the start tree. `git restore --source=<tree>` on a path missing from that tree exits 1 (probe), so delete the others.
  - Fix data-model §5's last sentence to match.

**C2. Re-running mutation and re-review after review and finish fixes scopes the change from HEAD, but those fixes aren't committed yet.** This was already there before revision 4. Revision 4 extended it to `FIN-n`. It silently violates SC-012 and constitution V.

- **Refs**:
  - mutation-runner.md §Scope ("Changed files/lines: `git diff … <base> HEAD`");
  - mutation-runner.md §Re-runs after review fixes ("runs again before that commit");
  - plan.md §Review step 5 and §Finish step 1;
  - data-model.md §7;
  - the signature at mutation-runner.md line 9 (`--classes` exists only with `--module`);
  - run-state.md §keel-diff (`--base` is HEAD-only; `--task` accepts only `T###`).
- **Why it fails**:
  - The probe confirmed that `git diff -U0 <base> HEAD` is empty for uncommitted fix lines.
  - PIT mutates the working-tree code, but `in_scope` comes from HEAD's line ranges. Lines the fix adds become `in_scope=no`, which never blocks.
  - When a fix inserts lines, every later mutant's line number shifts away from the recorded ranges.
  - New untracked classes and tests from the fix are never selected.
  - The "classes the review fixes touched" restriction can't be expressed through the CLI.
  - The scoped re-review has no diff of the uncommitted fix.
  - `keel-verify`'s "tests whose source file the feature changed or deleted" exclusion has the same HEAD problem before a commit.
- **Fix**:
  - Feature mode diffs `<base>` against the temp-index tree of the working tree (tracked and untracked, ignored files excluded), the same tree `keel-evidence` uses. At the first mutate run this equals HEAD.
  - Allow `--classes` together with `--base`.
  - Generalize `keel-diff --task T###` to `--unit <T###|MUT-n|REV-n|FIN-n>`: the working tree against the unit's start tree. Use it for the scoped re-reviews.
  - Apply the same working-tree rule to `keel-verify`'s changed-test exclusion.

## 2. Missing assumptions

- **A test command is not the same as a test framework.** In a Maven repo with no JUnit dependency, `mvn verify` is detected, so `tasks` adds no setup task and analyze's CRITICAL backstop doesn't fire. The first behavior task then needs an unnamed `pom.xml` edit, which the brief forbids, so it ends `BLOCKED` and halts. That outcome is safe but shouldn't be the design. Treat "no test-scoped JUnit/TestNG dependency in the effective POM" as "needs a setup task that names `pom.xml`".
- **"Nothing to build"** is defined as "no files outside `specs/`, `.specify/`, `.claude/` and top-level `*.md`" (run-state.md §keel-verify). A fresh sample repo with `.gitignore` or `LICENSE` fails that test, gets `BUILD=undetected` and halts at analyze. This can trip the M3 trial. Exclude dotfiles and license or notice files, or define "sources" by extension.
- **`feature.json` format is unspecified.** Spec Kit's `common.sh` reads `{"feature_directory": "specs/<NNN-name>"}`, and the SC-006 check runs `check-prerequisites.sh`. keel should write and read that exact key.
- **Non-Maven builds defined by host instructions** (allowed by VII) can't be recorded, because the `**Analyzed**` grammar allows only `build <maven|none>`. analyze's evidence would never match, and the run would loop on analyze.

## 3. Revised plan (deltas only)

**plan.md**
- §Run control: "Review evidence is the ledger row or the review-fix commits" contradicts data-model §2, where only `review done <sha>` counts. Align the two.
- §Branching: add the branch-name exemption (the spec dir and an untracked constitution, with no ledger needed), as run-state.md §keel-branch has it.
- §Finish:
  - Put the porcelain check (step 4) before the commit (step 3).
  - The expected set must include `test-quality.md` and any tests or fixes from the `FIN-n` re-mutation and the scoped review.
  - Define the scoped review's outcome: an in-design finding becomes another `FIN-n` unit; `changes-design` halts.
  - `FIN-n` edits are made by `implementer` (agent-handoffs: "only the implementer edits files").
- §Run control, order: for a new feature, `recover` runs with the new name (a no-op), never with the stale `feature.json`. It is recover, then `ensure`, then recover again when it deferred.

**data-model.md**
- §2, analyze row: `keel:baseline-failing` becomes `keel:baseline`, and `build <maven|none>` becomes `build <maven|host|none>`.
- §5:
  - The unit row text should include `<start-tree>`, as run-state.md has it.
  - Add `FIN-n` to the list of work-unit IDs.
- §3: Gate 1 writes Status and Path in a single edit. An `Approved` Status with no Path is drift, never silently `full`, which would ask Gate 2 on a light run.

**run-state.md**
- `recover` output: add `RECOVERED=deferred`.
- `keel-verify`:
  - Add `--kind behavior|non-behavior`, which `MISSING=test-command` depends on.
  - Add `keel-verify detect`, printing `BUILD=maven|host|none|undetected` and `TESTCMD=…`, so `tasks` really uses "the same detection".
  - Strip keel's flags from both sides before comparing commands, and store `baseline.cmd` without them.

**M7 matrix**
- Add "stopped between MUT-1 ok and MUT-2 start" and "stopped after REV-1 ok, before the review commit".

## 4. Verdict

**NO_GO.** N1–N3 and every round-4 delta are fixed consistently. Two contract contradictions remain, and each fix is one or two sentences with no design change:
- C1: resuming between rounds halts at `keel-branch`, contradicting the plan's own M7 case and data-model §5.
- C2: re-mutation after review or finish fixes is scoped from HEAD and silently misses the uncommitted fix lines (SC-012, constitution V).

Round 6 only needs to check these two.

### Critical Files for Implementation
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/run-state.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/data-model.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/mutation-runner.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/plan.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/push-guard.md

</details>

**Dispositions** (revision 5, 2026-11-25):
- **C1 (resume between rounds) and C2 (re-mutation scoped from HEAD) share one root cause**:
  rounds left uncommitted state behind. Both are resolved **structurally**:
  - **Every work unit commits.** That covers `T###`, `MUT-n`, `REV-n` and `FIN-n`, each after its
    own `keel-verify`, and after `keel-evidence check` when behavior changed. It extends the fixed
    "per-task commits" decision to every unit.
  - **For C1**: the tree is clean between units, so a stop there needs no recovery. Recovery
    restores only to BASE, which is HEAD. `start-tree` and `end-tree` are gone.
  - **For C2**: `keel-mutate --base` reads committed history, so fix lines are in scope.
    Re-mutation moved from review to finish, which covers every production change since the
    test-quality commit.
  - Scoped re-reviews use `keel-diff --unit` on the committed range of the unit.
  - Every comparison is tree-to-tree (a temp-index `write-tree`), never against the real index.
  - Restore covers only paths present in HEAD; new paths are deleted.
  - Triage decisions are committed (`specs/<NNN>/test-quality.triage.tsv`).
- **Missing assumptions**: resolved.
  - `keel-verify detect` covers test framework, build type (`maven`, `host`, `none`,
    `undetected`) and test command.
  - In Maven, `TESTFW=none` requires a setup task that names `pom.xml`.
  - "Nothing to build" is defined by build files and source extensions (dotfiles, LICENSE and
    NOTICE are ignored).
  - `feature.json` uses Spec Kit's exact format.
  - The `**Analyzed**` grammar allows `build <maven|host|none>`.
- **Deltas adopted**:
  - plan.md: review evidence wording aligned; the branch-name exemption added to §Branching.
  - §Finish reordered: re-mutation, then verify with `FIN-n` units by `implementer`, then the
    porcelain check *before* the commit. The scoped review's outcomes are defined.
  - `recover` runs with the new feature name and returns `RECOVERED=deferred`.
  - data-model: Status and Path are written in one edit, and `Approved` without `Path` is drift.
  - `FIN-n` was added to the unit list, and unit IDs appear in commit subjects (portable
    matching).
  - run-state: `--kind`; `detect`; keel's flags stripped from both sides of the command
    comparison; tree-to-tree changed-test exclusion.
  - M7 matrix: added the cases between MUT rounds, after REV-1's commit and inside FIN-1.
- **Rejected**: none. **Deferred**: none.

### Round 6 (2026-11-25)

**Verdict**: NO_GO

<details>
<summary>Reviewer output (verbatim)</summary>

Plan review, round 6: keel v1 (specs/001-spec-to-commit-flow)

I read round 5 and its dispositions, plan.md, data-model.md, the four contracts, quickstart.md, spec.md, constitution v1.3.0 and research.md. I ran two git 2.54 probes, only under `/private/tmp/claude-501/-Users-javiercardozo-dev-projects-payconductor/e517ffa1-998e-4d0f-9be1-7666010ddcae/scratchpad/r6probe/`. Nothing in the keel repo was changed.

## 1. Critical flaws

**Status of the round-5 items**

- **C1 is resolved.** Every unit commits, so the tree is clean between units and recovery only restores to BASE = HEAD.
  - The checks agree across data-model §5, plan §Run control (286–291) and plan §Branching (330–332), and run-state §keel-branch (73–75).
  - No start-tree or end-tree text is left anywhere.
- **C2 is resolved.**
  - `--base` reads committed history.
  - `--classes` now works with `--base` (mutation-runner line 210).
  - `keel-diff --unit` exists.
  - The changed-test exclusion is computed tree-to-tree (run-state 221–223).
  - Re-mutation has moved to finish in plan §Review 5, plan §Finish 1, mutation-runner 211–213 and data-model §7.
- **Round-5 deltas and missing assumptions:** all present, with two leftovers listed in section 3.
- **The triage file is acceptable.** `specs/<NNN>/test-quality.triage.tsv` holds keel's own decisions (`key reason`), not raw tool output, so it is fine under FR-034. It is one file next to `test-quality.md`, not a parallel tree, so it is fine under Principle II, and plain Spec Kit ignores it.
- **The docs-commit staging set is consistent** across plan 295 and 406 and data-model §3.
- **State derivation after FIN commits works.** The review row (data-model §2) holds when every later commit carries a `FIN-n` ID, and the finish row is checked first.
- **The mutate row works after MUT commits.** `test-quality.md` is not in HEAD until its own commit, so `next` stays at `mutate`.

Spreading "every unit commits" through the documents left three contradictions. Implementation would follow the contracts and get all three wrong.

**N1. Only `keel-diff` and the ledger accept unit IDs. The scripts every unit must pass through still accept only `T###`, and no evidence rule exists for non-task units.**
- **Refs**:
  - plan §Run control 286–288 (every unit commit needs `keel-verify`, plus `keel-evidence check` "when the unit changed behavior");
  - plan §Review 465–470;
  - plan §Finish 483–487;
  - run-state §keel-evidence 139–140 (`T###` only), §keel-brief 117 and 124 (`T###` only; an unknown task exits 3), §keel-verify 159 (labels are `baseline|T###|test-quality|review|finish`, with no `MUT-n`, `REV-n` or `FIN-n`);
  - data-model §4 201–206 (`briefs/`, `reports/`, `reviews/`, `evidence/` and `partial/` are all `T###`);
  - agent-handoffs 31–77 and 114.
- **Why it fails**:
  - The brief tells the implementer to run every test through `keel-evidence run` or `keel-verify`, and verification item 5's rule 1 restricts its Bash to exactly those two. A MUT, REV or FIN implementer therefore can't run a test under the contract.
  - "Behavior" is defined only by `keel-diff --kind` (any production path). So a REV unit that only refactors (simplicity lens), a trivial Minor fix (plan 470), or a FIN fix for an existing test that fails at finish needs `keel-evidence check`. That check requires a RED tree that adds a test (rule 3). Refactors can't produce one, so the unit halts after its re-dispatch.
  - The other possible reading lets the model decide what counts as a behavior change. That silently drops RED for correctness fixes, which violates constitution V.
- **Fix (text only)**:
  - Use `<unit>` everywhere: `keel-evidence run|check <f> <unit>`, `keel-verify --label <baseline|T###|MUT-n|REV-n|FIN-n|test-quality|finish>`, the scratch paths, and the brief, report and review templates.
  - Add a non-task brief source: either `keel-brief <f> <unit> --from <findings|gaps|verify-log path>`, or the orchestrator writes `briefs/<unit>.md` with `keel-put`.
  - Add a per-unit evidence table:
    - **`T###`**: unchanged.
    - **`MUT-n` and FIN gap units**: test paths and the triage file only (a production change halts). The evidence is the computed kill. No `check`.
    - **REV and FIN fix units**: record `intent=fix|refactor` in the `started` row, taken from the verified finding (correctness or a failing verify means fix; simplicity, conventions or Minor means refactor).
      - fix: `check` is required. For a FIN unit opened on a failing verify, RED may be a test that already existed and fails, recorded through `keel-evidence`.
      - refactor: no RED. `keel-verify` must pass, the reviewer confirms behavior didn't change, and finish's re-mutation covers the lines.

**N2. `.specify/feature.json` gets committed in the first unit commit.**
- **Refs**:
  - run-state §keel-diff 129 (temp-index tree: tracked plus untracked, only ignored files excluded);
  - plan §Implement 8 ("stage exactly the unit's diff files");
  - data-model §3 118 ("never committed").
- **Why it fails**:
  - The keel repo itself has `?? .specify/feature.json`, and `git check-ignore` returns 1, so it isn't ignored.
  - Probe: BASE's tree against a temp-index `write-tree` lists `A .specify/feature.json`.
  - keel doesn't patch ignore files (VII), so this happens on the main path, including the M3 trial.
- **Fix**:
  - Build every temp index with `git add -A -- . ':(exclude).specify/feature.json'`. The probe showed this removes it.
  - Apply that to `keel-diff`, the `keel-evidence` trees, `keel-verify`'s exclusion, and recovery's attribution, patch and deletion.
  - Exclude only `feature.json`. If `specs/<f>/**` were excluded too, MUT units would lose the triage file.

**N3. When finish re-mutates and finds no gaps, the `test-quality.md` update has no commit.**
- **Refs**:
  - plan §Finish 1 ("updated in the last `FIN-n` commit") and 3 (the porcelain check allows only `feature.json`);
  - mutation-runner 211–213 ("before its commit … updates this file");
  - run-state 77–80 (the check runs "when the only expected changes are the spec's Status edit and the finish unit's files").
- **Why it fails**: review fixes that are already covered by tests produce no FIN unit, and that is the main path. The three texts then disagree: halt at step 3, put the update in the finish commit, or drop it and leave a stale summary.
- **Fix**:
  - Step 3 checks for `feature.json` only.
  - Step 4 then writes the re-mutation section into `test-quality.md` together with the Status line.
  - Step 5 commits both as the finish commit. Step 2's verify comes before it, the same pattern as analyze's docs commit.
  - On resume, if `spec.md` and `test-quality.md` differ from HEAD only by those edits, restore them first.
  - Align run-state 77–80 with this.

## 2. Missing assumptions

- **Build output must be git-ignored.** The temp-index trees include untracked files that aren't ignored. A repo that doesn't ignore `target/` will stage build output in a unit commit, or halt every porcelain check after the baseline. Analyze should check `git status --porcelain` after the baseline verify and halt with "ignore your build output". It must not patch ignore files.
- **Unit numbering on resume.** `n` should be 1 plus the highest `n` for that prefix in the `<base>..HEAD` subjects and the ledger. The round caps (3 for mutate, 3 for review, 3 for finish) should be counted from commits, so a resume doesn't reset them or reuse `MUT-1`.
- **Triage keys aren't stable under line shifts.** The key includes `line` (mutation-runner 119–120). REV and FIN fixes shift lines in exactly the classes finish re-mutates, so triaged mutants come back as blocking. They then get triaged again in FIN units, and no reviewer checks those reasons. Drop `line` from the key (`class|method|desc|mutator|indexes` is unique within a method), or show FIN triage rows in a scoped correctness pass.
- **Recovery leaves staged new paths in the index.** Probe: a new file that was `git add`ed and then deleted only from the working tree shows `AD`, and the next commit would include its stale blob. This happens when the run is interrupted between step 8's `git add` and `git commit`. Recovery step 3 must also remove these paths from the index. `git restore --source=HEAD --staged --worktree -- <path>` works on a staged new path (rc 0), but on an untracked one it fails with "pathspec did not match".
- **Finding the test-quality commit.** A FIN subject such as "FIN-2 update test-quality.md" matches the `test-quality` pattern and would shorten finish's re-mutation range. Define the commit as the one that added `specs/<f>/test-quality.md` (`git log -1 --diff-filter=A -- <path>`).
- **The exemption list has two scopes.** `ensure` exempts `feature.json`, plus `specs/<f>/**` and an untracked constitution on the feature branch. Unit start, implement preflight, recovery attribution and finish exempt `feature.json` only. Without this, "the same single list" (run-state 67–68) makes the `[X]` attribution clause dead, and finish accepts dirty spec files.
- **A halted `test-quality.md` is never committed.** A FIN commit with `Result: halted` makes the review row hold while the mutate row is missing, which shows up as drift. Put the halt content in the report or in scratch.
- **Exit codes outside the main flow.** In finish, `keel-mutate` exit 10 (or a mutate result of `not-run`) means skip and report, not halt. A `debug` fix during mutate after exit 11 is a `MUT-n` unit.
- **MUT tests are committed before their kill is confirmed.** If a test's target key doesn't turn KILLED, the test stays committed and the next round fixes it or reports it as kills-nothing. Say so.

## 3. Revised plan (deltas only)

**plan.md**
- M6 (753–754): remove "re-mutate on fixes" from `review`. That work is in `finish`.
- §Interpretations, SC-005 (169–172): add `FIN-n`.
- §Constitution Check II (136): name `test-quality.triage.tsv`.
- §Tasks and analyze (383): the setup-task trigger also covers `TESTFW=none` (Maven).
- §Implement 8: stage from a fresh `keel-diff --unit` taken at commit time, after the fix rounds.
- §Run control 284: a lost `.git/keel/` during an open unit leads to `MISSING=clean-tree`, not only to a re-run of analyze or review.
- §Docs commit: also stage an untracked constitution under the branch-name rule, for the case where the ledger was lost.

**data-model.md**
- §5: add a case "dirty tree, HEAD past BASE → `HALT=unattributed-changes`".
- §5: name the paths for non-task units, for example the `src/test/**` of the affected modules plus the triage file for MUT units, and the finding files plus their tests for REV and FIN. That way an interruption before the first `keel-evidence` run still recovers.
- §7: replace "behavior-task commit" with the per-unit evidence table from N1.

**run-state.md**
- 176–177: replace the old definition of "nothing to build" with the definition from `detect` (210–214). The two currently contradict each other.
- 159: fix the label enum as in N1.

**mutation-runner.md**
- 146–147: say who writes triage rows. The implementer proposes them in its report, and the orchestrator writes them through the unit.

**M7 matrix**
- State the expected outcome of "resume 001 from 002 with a unit started and a dirty tree" (a halt).
- Add "interrupted between the finish Status edit and the finish commit".

**keel-state tests**
- A `review done` row followed by FIN commits (holds).
- A `review done` row followed by a commit without an ID (review re-runs).

## 4. Verdict

**NO_GO.** C1, C2 and the round-5 items are resolved. Moving to per-unit commits left three contract contradictions that implementation would follow:
- N1: the scripts accept only `T###`, and no evidence rule exists for MUT, REV and FIN units.
- N2: `feature.json` is committed through the temp-index trees.
- N3: finish's `test-quality.md` update has no commit.

Each fix is text-only, with no design change. Round 7 needs to check only N1 to N3.

### Critical Files for Implementation
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/run-state.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/data-model.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/plan.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/agent-handoffs.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/mutation-runner.md

</details>

**Dispositions** (revision 6, 2026-11-25):
- **N1 (unit IDs and evidence for non-task units)**: resolved.
  - `keel-evidence run|check <f> <unit>` and `keel-verify --label
    <baseline|T###|MUT-n|REV-n|FIN-n|test-quality|finish>`.
  - `keel-brief <f> <unit> --from <path>` covers non-task units.
  - Scratch paths and the brief, report and review templates use `<unit>`.
  - A per-unit evidence table lives in data-model §7:
    - `MUT-n` and FIN gap units: tests and the triage file only; evidence is the computed kill.
    - REV and FIN units carry `intent=fix|refactor`, set by the orchestrator from the verified
      finding. `fix` requires `check`; a FIN unit on a failing verify may use the already-failing
      test as RED. `refactor` has no RED; verify plus the reviewer's no-behavior-change
      confirmation plus finish's re-mutation.
  - `keel-evidence` rule 3 was updated to match.
- **N2 (`feature.json` committed through temp-index trees)**: resolved. Every temp index is filled
  with `git add -A -- . ':(exclude).specify/feature.json'`, and only that file is excluded.
- **N3 (finish `test-quality.md` update with no commit)**: resolved.
  - The porcelain check runs first and allows `feature.json` only.
  - Then a `FINISH` unit, with named paths `spec.md` and `test-quality.md` and a ledger row,
    writes the Status line and the re-mutation section.
  - The finish commit stages both, with step 2's verify as its evidence.
  - An interrupted `FINISH` is recovered like any other unit.
- **Missing assumptions**: resolved.
  - Analyze halts on build output that isn't ignored, and never patches ignore files.
  - Unit numbering and round caps are counted from commits and the ledger.
  - Mutant keys drop `line`, and FIN triage rows get a scoped correctness pass.
  - Recovery removes staged new paths from the index (`git rm --cached`).
  - The test-quality commit is the one that added the file (`--diff-filter=A`).
  - There are two exemption scopes: ensure versus unit.
  - A halted summary is never committed.
  - Finish exit codes are defined: 10/not-run → skip and report, 11 → `FIN-n` debug, 12 → halt.
  - Exit 11 during mutate is handled in a `MUT-n` unit.
  - Unconfirmed MUT tests stay committed, and the next round handles them.
- **Deltas adopted**:
  - M6 contents fixed.
  - SC-005 includes `FIN-n` and `FINISH`.
  - Constitution Check II names the triage file.
  - The setup-task trigger includes `TESTFW=none`.
  - Implement step 8 stages from a fresh unit diff.
  - The lost-scratch-in-an-open-unit halt is stated.
  - The docs commit covers an untracked constitution under the branch-name rule.
  - data-model §5 adds the "dirty tree, HEAD past BASE" halt and named paths for every unit type.
  - run-state's "nothing to build" defers to `detect`.
  - Mutation triage writer defined.
  - M7 and keel-state test cases added.
- **Rejected**: none. **Deferred**: none.

### Round 7 (2026-11-25)

**Verdict**: GO

<details>
<summary>Reviewer output (verbatim)</summary>

Plan review, round 7: keel v1 (specs/001-spec-to-commit-flow)

I read round 6 and its dispositions, plan.md, data-model.md, the four contracts, quickstart.md, spec.md, constitution v1.3.0 and research.md. I ran git 2.54 probes only under `/private/tmp/claude-501/-Users-javiercardozo-dev-projects-payconductor/e517ffa1-998e-4d0f-9be1-7666010ddcae/scratchpad/r7probe/`. In PayConductor I ran one read-only `git ls-files -ci --exclude-standard`. Nothing in the keel repo was changed.

## 1. Critical flaws

None that block.

**Status of the round-6 items**
- **N1 is resolved.** Every script that a unit passes through now takes `<unit>`: `keel-brief … --from` (run-state 124–139), `keel-evidence run|check` (154–170) and the `keel-verify` label enum (175). The scratch paths take it too (data-model §4 200–206), and so does the brief template (agent-handoffs 35–39). The per-unit evidence table is in data-model §7 (317–328), and the orchestrator sets `intent`. Leftover wording is listed as deltas D1–D4.
- **N2 is resolved.** One rule (run-state 85–89) covers every temp index: `keel-diff`, the `keel-evidence` trees, `keel-verify`'s exclusion, and recovery's attribution, patch and deletion. Plan §Implement 8 matches. The probes found three implementation traps in the same mechanism (D5). Each one either halts or adds noise; none commits wrong content.
- **N3 is resolved.** These all agree: plan §Finish 3–5 (porcelain check first, then the `FINISH` unit, then a commit of `spec.md` and `test-quality.md`), run-state 82–84, mutation-runner 214–216 and the data-model §7 `FINISH` row.
- **Round-6 deltas and missing assumptions:** all present. One half-leftover: mutation-runner 188 still lists `**Result**: … | halted (<n> unresolved)` (D8).
- **No new contradiction on the main path** that would send an implementation the wrong way. The items in §3 are one-line alignments. Where they misfire, the run halts.

## 2. Missing assumptions

- **Tracked-but-ignored files.** A temp index filled from empty leaves out tracked files that match an ignore pattern.
  - Probe: a force-added `.mvn/wrapper/maven-wrapper.jar` under a `*.jar` ignore rule shows as `D` against HEAD.
  - Consequences: every unit diff gets a spurious deletion, and recovery attribution halts if it runs before the first `keel-evidence` run.
  - Staging through the real index stays correct (`git add` on that path: rc 0, no change).
  - Running `git read-tree HEAD` into the temp index first removes the problem.
  - PayConductor has no such files today. Many Maven repos do.
- **cwd is persistent** (plan 77), and the pathspecs `.` and `':(exclude).specify/feature.json'` are relative to cwd.
  - From a module directory with an empty index, everything outside cwd shows as `D`. That fails closed.
  - With a seeded index, changes outside cwd would be silently missed, including by `check`'s rule 3. So D5's two fixes must ship together.
- **Mixed-intent rounds.** A `REV-n` round can hold both correctness and simplicity findings, but a unit has only one `intent`. A Minor or Critical correctness finding also fits both rows of §7. A precedence rule is needed.
- **A fix-intent unit whose diff touches only tests** fails `check` rule 4 and halts. Examples: a correctness finding about a test, or an existing integration test that asserts the old behavior when the host defines a faster per-task verify command. The run halts safely, but it's the wrong outcome.
- **Restart ID.** After `recover`, does the unit restart under the same ID, or does the numbering rule (data-model 231–233) give it a new one? Both readings fit the text.
- **The "3 for finish" cap.** It isn't defined against the three kinds of `FIN-n` unit (gap, verify fix, scoped-review finding), and nothing bounds the step 1 → 2 → scoped review → step 1 loop.
- **Untracked files created by new tests** (logs, H2 files outside `target/`) end up in `keel-diff --unit`, so they get staged. Analyze's porcelain check catches only the ones the baseline already produced.
- **recover with no ledger and a dirty tree.** run-state 80–81 says `recover` halts here, but this case isn't in data-model §5's case list. Today `ensure` or the unit-start check halts instead. The outcome is the same; only the reported code differs.

## 3. Revised plan (deltas only)

**Fix before tasks.md**
- **D1** run-state 109: the started row becomes `… started <BASE> <unit> <intent> <path,…>`, matching data-model 241 and plan 511. `keel-evidence check` and `keel-brief` read `intent` from this row. As written, run-state gives intent nowhere to live.
- **D2** The refactor confirmation has no slot.
  - data-model §7 (319, 325) lists "the reviewer confirms behavior didn't change" as evidence *before* the commit. Plan §Review 4 (478–481) runs only a post-commit scoped re-review, and no review template has a field for the confirmation.
  - Fix: REV and FIN fix units get `task-reviewer` before verify and commit, as agent-handoffs 116 already implies. Add `**Behavior unchanged**: yes | no` for `intent=refactor`. A `no` re-opens the unit as `intent=fix`.
  - Rename §7's column to "Evidence" and mark the MUT computed kill as post-commit, which plan §Mutate and mutation-runner 180–182 already say.

**plan.md**
- **D3** §Run control 288–290 ("when the unit changed behavior"), §Review 4 ("when behavior changes") and Constitution Check V ("every behavior task") should all defer to the per-unit rule in data-model §7.
- §Mutate: before a MUT or FIN gap commit, `keel-diff --kind <unit>` must return `non-behavior`. That is where "a production change halts" is enforced.
- §Finish:
  - Steps 2 and 4: `FINISH` starts only when the `finish` verify ran on the current HEAD. After any FIN commit, go back to step 1 and then step 2.
  - Define the finish cap: count each kind separately, plus an overall bound.

**data-model.md**
- §5: add `FINISH` to the ID list (223–227). Its matching commit is "HEAD's `spec.md` has `Implemented`", because the finish subject carries `NNN`, not `FINISH`. On `done`, `run` re-does the idempotent `mem_save` and the final report.
- §5: a recovered unit keeps its ID, and the numbering rule applies only to new units.
- §5: REV and FIN named paths also include the affected modules' `src/test/**`. A new test file then stays attributable before the first evidence run.
- §5: add the "no ledger, dirty tree (unit scope)" case.
- §7 intent precedence:
  - a correctness-lens finding or a Critical finding (which by definition is wrong behavior) means `fix`;
  - a round with any `fix` finding is `fix`;
  - a fix-intent unit whose `--kind` is `non-behavior` needs only verify plus review.
- §7: name the row for exit-11 debug units (`MUT-n` in mutate, `FIN-n` in finish). Use `intent=fix` on a failing verify, test paths only for MUT.

**run-state.md**
- **D5** Temp indexes (13, 85–89, 149, 158–159; data-model 274–275):
  - Seed every one with `git read-tree <HEAD|BASE>`, then run `git add -A -- ':/' ':(top,exclude).specify/feature.json'`, or `cd` to the toplevel first.
  - Don't point `GIT_INDEX_FILE` at a fresh `mktemp` file. Probe: a 0-byte index makes `git add` fail with "index file smaller than expected" (rc 128), while `read-tree` into the same file works.
  - Optionally copy the real index for its stat cache.
- 160–166: `check` can't tell from the ledger that a FIN unit was opened on a failing verify. Either record that origin, or allow the already-failing-test RED for any `FIN-n` with `intent=fix`, with `task-reviewer` judging the reason.

**agent-handoffs.md**
- **D4** Brief Rules (44–49):
  - add a MUT/FIN gap rule: tests only, run through `… green`, propose triage rows;
  - add a refactor rule: no RED, run through `… refactor`.
- Report template (57–64): add `**Triage proposals**: <key> <reason>` lines (plan 457–459 and mutation-runner 121–123 depend on it). For MUT and refactor units, Evidence is "GREEN seq".
- Status table (116): read "per-unit rule (data-model §7)".
- Brief "Allowed paths" (38–39) for `T###`: make it advisory, except for build files. As written, ordinary ripple edits can end in `BLOCKED` on the main path.

**mutation-runner.md**
- **D8** 188: drop `halted` from `**Result**`. A halted mutate summary goes to scratch and the final report, never to `specs/`. This also protects the `--diff-filter=A` reference point.

**Tests**
- Script suites:
  - run every script from a module subdirectory;
  - use a fixture with a tracked-but-ignored file;
  - write the ledger with the skill's row format and read it with `recover` and `check`.
- M7:
  - interruption between the finish commit and the ledger `ok`;
  - a mixed-intent REV round.

## 4. Verdict

**GO.** N1–N3 and the round-6 items are resolved across plan.md, data-model.md and the three contracts. What remains is one-line alignments and implementation traps that either halt or add noise; none commits wrong content. D1, D2 and D5 should be folded in before tasks.md is generated.

### Critical Files for Implementation
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/run-state.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/data-model.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/plan.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/agent-handoffs.md
- /Users/javiercardozo/dev/projects/keel/specs/001-spec-to-commit-flow/contracts/mutation-runner.md

</details>

**Dispositions** (revision 7, 2026-11-25, folded in before task generation as the reviewer
asked):
- **D1**: the started row carries `intent`, which `check` and `keel-brief` read.
- **D2**: REV and FIN units get `task-reviewer` before verify and commit, with
  `**Behavior unchanged**` for refactors (`no` re-opens the unit as `fix`). The §7 column is now
  "Evidence", with MUT's computed kill marked as after the commit.
- **D3**: plan run control, review and Constitution Check V now defer to the per-unit rule. MUT and
  FIN gap commits require `--kind` = `non-behavior`. `FINISH` needs a finish verify on the current
  HEAD. Finish caps: 3 per kind and 6 passes overall.
- **D4**: the brief has rules for MUT/gap and refactor units. Allowed paths are advisory for
  `T###` except build files. The report gains `Triage proposals`, and the status table follows the
  per-unit rule.
- **D5**: temp indexes are seeded with `read-tree` (the file must not exist beforehand) and filled
  with top-anchored pathspecs. Suites run from a module directory and against a
  tracked-but-ignored fixture.
- **D8**: a halted mutate never writes `test-quality.md`.
- **data-model §5 and §7**:
  - `FINISH` is in the ID list, and its matching commit is the `Implemented` spec.
  - A restart keeps the unit ID.
  - REV and FIN named paths include the module's `src/test/**`.
  - The case "no ledger, dirty tree" halts.
  - `intent` precedence rules are added, as are the exit-11 debug units.
  - `check` allows an already-failing-test RED for any `FIN-n` with `intent=fix`, and
    `task-reviewer` judges whether its reason is valid.
- **Missing assumptions not folded in**, left to implementation and covered by M7 tests:
  - untracked files created by new tests;
  - an interruption between the finish commit and the ledger `ok`;
  - a mixed-intent REV round. The precedence rule covers it, and a test is added.

**Plan review closed: GO (round 7).**
