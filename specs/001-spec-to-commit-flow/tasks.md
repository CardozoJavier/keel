---
description: "Task list for keel v1, spec-to-commit feature delivery"
---

# Tasks: Spec-to-Commit Feature Delivery (keel v1)

**Input**: Design documents from `specs/001-spec-to-commit-flow/` (plan.md, spec.md, research.md,
data-model.md, contracts/, quickstart.md)

**Tests**: REQUIRED by the constitution (Principle V, test-first).

**What counts as a test, by kind of change**:

| Kind of change | Test |
|---|---|
| Script | A `tests/**/*_test.sh` suite that `tests/run.sh` runs. |
| Skill or agent | An eval scenario under `plugin/evals/` (run by `tests/eval/evals_test.sh` through `tests/run.sh --eval`). |
| Behavior task | One task covers RED, GREEN and refactor, and names both the test path and the production path (plan §Tasks and analyze). Write the test first and confirm it fails. |
| Non-behavior task (setup, vendoring, docs, empirical checks) | Named as such in the task. |

**Paths**:
- The plugin root is `plugin/`.
- keel's own tests live under `tests/`.
- The local marketplace is `.claude-plugin/marketplace.json` at the repository root.
- All scripts run on bash 3.2 and BSD awk/sed (plan §Technical Context).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on incomplete tasks). keel's own
  development runs serially anyway; `[P]` is kept for Spec Kit compatibility.
- **[Story]**: US1–US6 from spec.md.

---

## Phase 1: Setup (Shared Infrastructure, plan M0)

**Purpose**: plugin skeleton, test harness, shared library, vendored upstreams, provenance.

- [X] T001 Create the plugin skeleton (non-behavior; check: `claude plugin validate plugin/` passes):
  - `plugin/.claude-plugin/plugin.json`: name `keel`, version `0.1.0`, description. `defaultEnabled: false` was dropped in T008: eval can't enable such a plugin, and installing with `--scope local` gives the same isolation (research R7).
  - `.claude-plugin/marketplace.json` at the repository root: marketplace `keel`, one plugin with source `./plugin`.
  - Empty dirs `plugin/{skills,agents,hooks,shims,bin,lib,templates,vendor}` with `.gitkeep`.
- [X] T002 Write the plain-bash test harness, bash 3.2 compatible.
  - Test first: `tests/harness_test.sh`.
  - `tests/run.sh`: discovers `tests/**/*_test.sh`; `--slow` adds `tests/slow/`; prints pass/fail counts; exits non-zero on any failure.
  - `tests/lib.sh` helpers:
    - `assert_eq`, `assert_exit`, `assert_contains`;
    - `mk_repo` (temp git repo under `$TMPDIR` with user config);
    - `mk_bare_remote`;
    - `in_subdir` (run from a module subdirectory);
    - `fixture_tracked_ignored` (a force-added file under an ignore rule).
- [X] T003 Write the shared library in `plugin/lib/common.sh`, with tests in `tests/scripts/common_test.sh`, run from the repo root and from a module subdir.
  - Root discovery: `$KEEL_ROOT`, else the script's own path through a `readlink` loop without `-f`.
  - `repo_root`, `scratch_dir <feature>` (`$(git rev-parse --git-dir)/keel/<feature>`), `die`/`emit KEY=value`.
  - Portable helpers: `tail -r` versus `tac`, no `timeout`/`date -d`/`stat -c`/`find -printf`/`xargs -r`, and a guarded empty-array expansion.
  - Unit-ID boundary matcher `(^|[^A-Za-z0-9])<ID>([^A-Za-z0-9-]|$)` under `LC_ALL=C`.
  - The temp-index builder from contracts/run-state.md: seed with `git read-tree <ref>` into a new file under scratch, then fill with `git add -A -- ':/' ':(top,exclude).specify/feature.json'`, then `write-tree`.
  - The tests also cover the tracked-but-ignored fixture.
- [X] T004 [P] Vendor Spec Kit 0.8.4.dev0 verbatim into `plugin/vendor/speckit/` (non-behavior).
  - Copy `scripts/bash/common.sh`, `scripts/bash/check-prerequisites.sh` and `templates/{spec,plan,tasks,checklist,constitution}-template.md` from this repo's `.specify/`.
  - Add `plugin/vendor/speckit/LICENSE` with the MIT text, taken from the installed `specify` package (find it under the uv/pipx tool directory).
  - Apply keel's template edits:
    - spec-template gains `**Path**` and `**Base**` lines plus a `## Change Classification` section;
    - plan-template gains `**Plan status**` and the `## Design Decision`/`## Plan Review` sections;
    - tasks-template gains the behavior-task-carries-its-test rule and the `**Analyzed**` line note.
  - Log each edit in `plugin/vendor/CHANGELOG.md`.
  - Test first: `tests/scripts/speckit_compat_test.sh` (SC-006). The vendored
    `check-prerequisites.sh --json --require-tasks --include-tasks` must accept a keel-produced
    fixture feature dir under `tests/fixtures/repos/keel-feature/`. That dir has the `**Base**`,
    `**Path**`, `**Plan status**` and `**Analyzed**` lines, the `keel:baseline` comment, a
    `## Design Decision` and a `## Plan Review`. The check must report the same FEATURE_DIR and
    AVAILABLE_DOCS as for a plain Spec Kit fixture.
- [X] T005 [P] Vendor superpowers 7.0.2 pristine sources into `plugin/vendor/superpowers/` (non-behavior).
  - `skills/test-driven-development/` (all files), `skills/systematic-debugging/` (all files), `skills/verification-before-completion/SKILL.md`, `skills/receiving-code-review/SKILL.md`.
  - `skills/requesting-code-review/` (all files) and `skills/subagent-driven-development/` (all files).
  - `LICENSE`.
  - Source: `~/.claude/plugins/cache/claude-plugins-official/superpowers/7.0.2/`.
- [X] T006 [P] Vendor feature-dev 1.0.1 pristine sources into `plugin/vendor/feature-dev/` (non-behavior).
  - `agents/{code-explorer,code-architect,code-reviewer}.md`, plus `LICENSE` (Apache-2.0) and any upstream `NOTICE`.
  - Source: `~/.claude/plugins/cache/claude-plugins-official/feature-dev/1.0.1/`.
- [X] T007 Write the provenance check, with tests in `tests/scripts/provenance_test.sh` (test first).
  - Every file under `plugin/vendor/*/` (except `PROVENANCE.md`/`CHANGELOG.md`) appears in `plugin/vendor/PROVENANCE.md` with upstream, version, license and local changes.
  - `NOTICE` and `plugin/NOTICE` attribute Spec Kit (MIT, GitHub, Inc.), superpowers (MIT, Jesse Vincent) and feature-dev (Apache-2.0).
  - Every file under `plugin/{skills,agents}` that names an upstream in an `Adapted from` header refers to a vendored file.
  - Apache derivatives carry a §4(b) change notice.
  - Write `plugin/vendor/PROVENANCE.md`, `NOTICE` and `plugin/NOTICE`.
- [X] T008 Verify `claude plugin eval` in 2.1.332, verification item 4 (non-behavior).
  - Probe the case format, graders, `context.history_file` chaining, `--allow-tools`, `--no-publish` and `--eval-dir`, using a smoke case `plugin/evals/smoke/` against `plugin/`.
  - Record the findings in `tests/eval/README.md` and research.md (R7).
  - Add an eval runner `tests/eval/evals_test.sh`, run by `tests/run.sh --eval`. Cases live in `plugin/evals/` because the eval dir must sit below the plugin root.

**Checkpoint**: `claude plugin validate plugin/` passes, `tests/run.sh` is green, the eval smoke
case passes.

---

## Phase 2: Foundational (Blocking Prerequisites, plan M1 + M2)

**Purpose**: the three-layer push guard and the run-state scripts that every step skill depends on
(`keel-state require` checks the guard).

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

### Push guard (M1, contracts/push-guard.md)

- [X] T009 Write the JSON string extractor in `plugin/lib/json.sh` (pure bash/awk), with tests in `tests/scripts/json_test.sh` (test first).
  - Extracts `tool_name`, `tool_input.command`, `tool_input.sandbox`, `tool_input.config` and `cwd`.
  - Decodes `\" \\ \/ \b \f \n \r \t` and ASCII `\u00XX`, and leaves non-ASCII escapes as they are.
  - Fails on invalid JSON, duplicate keys or a missing key.
- [X] T010 Write real-binary discovery for shims in `plugin/lib/shim-common.sh`, with tests in `tests/guard/shims/discovery_test.sh` (test first).
  - Use `$KEEL_REAL_<TOOL>`, else a PATH search that skips:
    - empty and relative entries;
    - the shim's own resolved directory;
    - entries carrying the keel shim marker line.
  - Require `-f` and `-x`.
  - Recursion guard: `KEEL_SHIM_DEPTH` above 3 exits 2 with rule `AF`.
  - Test cases: two shim directories on PATH, and a directory named `git`.
- [X] T011 Generate and check the embedded git builtin list `plugin/lib/git-builtins.sh`, using the generator `tests/tools/gen-git-builtins.sh` (`git --list-cmds=main`). Test first: `tests/guard/shims/builtins_test.sh`, which fails when the list drifts from the installed git.
- [X] T012 Write the git shim `plugin/shims/git`, with tests in `tests/guard/shims/git_test.sh` and the corpora `tests/guard/shims/cases/git-{allow,deny}.tsv` (test first).
  - Global-option skipping and alias resolution through the real git with the same options, at most 5 levels.
  - Rules A1, A2 (git parts), A3 and A8; the exit-2 message format; `AF` on internal error.
  - Allow cases include `stash push`, `rebase -x 'mvn -q test'`, `reset --hard`, `cherry-pick`, `commit -m "push …"` and `lfs pull`.
  - Deny cases include `-c alias.p=push p`, an alias configured through `GIT_CONFIG_COUNT`, `config url.x.pushInsteadOf`, `remote set-url --push` and `-c core.hooksPath=…`.
  - Shell-alias cases (`gp`, `gpsup`, `ggpush`, `ggp`) run through `zsh -c` with the snapshot fixture `tests/fixtures/snapshot/aliases.zsh`.
- [X] T013 Write the gh shim `plugin/shims/gh`, with tests in `tests/guard/shims/gh_test.sh` and the corpora `tests/guard/shims/cases/gh-{allow,deny}.tsv` (test first).
  - Rules A4, A5 and A6: write-method parsing (`-XPOST`, `--method=`, field flags), the endpoint regex, `PATCH pulls/N state=open`, GraphQL mutation names (inline and `query=@file`; an unreadable file means deny), and alias resolution through `gh alias list`.
  - Core subcommands pass, extensions and unknown subcommands are denied, and `--version`/`version`/`help` pass.
  - Allow cases include `pr view`, `pr edit` and comment POSTs.
- [X] T014 [P] Write the thin shims `plugin/shims/{jj,sl,gt,glab,hub}` with rule A7, with tests in `tests/guard/shims/others_test.sh` (test first; a fake real binary on PATH records its argv).
- [X] T015 Write layer A0 and the session environment, with tests in `tests/guard/a0_test.sh` against a local bare-remote fixture (test first).
  - Write `plugin/hooks/deny-push`, `plugin/shims/git-remote-keel-blocked-push` and `plugin/hooks/session-env.sh`.
  - `session-env.sh` appends to `$CLAUDE_ENV_FILE`:
    - `GIT_CONFIG_COUNT/KEY/VALUE` with 5 entries (the 5th, `protocol.keel-blocked-push.allow`, lets the helper report inside `submodule foreach`), appending after existing ones and idempotent when keel's keys are already present;
    - `PATH` with the shims first, plus `KEEL_SHIMS`, `KEEL_ROOT`, `KEEL_REAL_GIT` and `KEEL_REAL_GH`.
  - Every push form is blocked with only the A0 environment and no shims:
    - plain push, `/usr/bin/git push`, `xcrun git push`, `env -P /usr/bin git push`, `zsh -lc`, `bash -lc`;
    - a `!` alias, and post-commit, pre-commit and reference-transaction hooks;
    - `rebase -x`, `submodule foreach`, `bisect run`;
    - `--no-verify` (blocked by the URL rewrite), and a file-config `hook.keel-nopush.enabled=false` (the environment wins).
  - Fetch, ls-remote and clone still work, and the remote is unchanged after every case.
- [X] T016 Write the functional guard self-check in `plugin/lib/guard-check.sh`, with tests in `tests/guard/selfcheck_test.sh` (test first).
  - Passes only when all of these hold:
    - `git hook list pre-push` lists `keel-nopush` as enabled;
    - every `git remote get-url --push --all` URL starts with `keel-blocked-push://`;
    - `--show-scope` lists only keel's command-scope `pushInsteadOf`;
    - no `remote.*.pushurl` exists;
    - `command -v git` resolves into `$KEEL_SHIMS`.
  - Failing cases: a pushurl, a longer and a tying `pushInsteadOf`, no remotes plus a file-config rule, a simulated git without config hooks, and a shim that isn't first on PATH.
  - Each failure prints `MISSING=push-guard:<what>`.
- [X] T017 Write layer B's shell mode in `plugin/hooks/guard-push.sh`, with tests in `tests/guard/hook/shell_test.sh` and the cases `tests/guard/hook/cases/{allow,deny,failclosed}/*.json` (test first).
  - Tokenizer: one awk pass, reserved words, redirections, assignments, zsh precommand modifiers, recursive `$( )`, backticks and here-document data.
  - Command-word normalization and wrapper unwrapping.
  - Rules B1–B5, W1, W2, F1 and F2, with the V1 explicit-boundary vocabulary.
  - The B2 PATH rule uses `-x` checks of prepended directories. `export PATH=$JAVA_HOME/bin:$PATH` passes, and `GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL` pass.
  - Exit 2 with the reason on stderr.
- [X] T018 Add layer B's `--github-mcp` and `--codex` modes to `plugin/hooks/guard-push.sh`, with tests in `tests/guard/hook/mcp_test.sh` (test first).
  - GitHub MCP: allow `get_`/`list_`/`search_` and the named non-publishing writes; deny the rest.
  - Codex:
    - deny `danger-full-access`, a `config` that sets `sandbox_mode` or turns on network, and the same in a fixture `CODEX_HOME/config.toml`;
    - deny when that file is unreadable;
    - always allow `codex-reply`.
- [X] T019 Write `plugin/hooks/hooks.json`, with tests in `tests/guard/hooks_json_test.sh` (test first).
  - It registers `SessionStart` → `session-env.sh`, and PreToolUse matchers `^(Bash|Monitor|PowerShell)$`, `^mcp__.*github.*__.*$`, `^mcp__codex__codex$` and `^mcp__codex__codex-reply$` → `guard-push.sh` in the right mode.
  - Every entry has `onFailure: "block"` and a 10 s timeout.
  - The test asserts the structure, the anchored matchers and that every referenced script is executable.
- [X] T020 Add guard performance checks in `tests/guard/perf_test.sh`, measured with `TIMEFORMAT=%3R`: layer B p95 under 50 ms on the allow corpus, and shim overhead under 15 ms per git/gh call (test first).
- [X] T021 Run the empirical guard verification, items 1, 3, 5, 7, 8 and 9 (non-behavior).
  - Use `claude -p --plugin-dir plugin` probe sessions with a local bare remote in the scratchpad.
  - Check that:
    - `gp`, a pushing post-commit hook and `zsh -lc 'git push'` are blocked live;
    - `git stash push` and `git rebase -x 'mvn -q test'` are allowed;
    - the Monitor tool's name and payload match;
    - the env file reaches subagents and skill-injected commands;
    - the env file survives `/clear`, compaction, resume, fork and CwdChanged;
    - the `PreSkillShellCommand` payload is as expected;
    - the git version that introduced config hooks is known.
  - Record the results in research.md (R7) and the quickstart's verified-facts table. Apply the plan's decision rule for item 5.

### Run-state scripts (M2, contracts/run-state.md, data-model.md)

- [X] T022 [P] Write `plugin/bin/keel-ledger`: append-only TSV with unit rows (`started <BASE> <unit> <intent> <paths>`; `ok`/`halted`/`abandoned`), step `done` rows, and `last`. Tests in `tests/scripts/keel-ledger_test.sh` (test first).
- [X] T023 [P] Write `plugin/bin/keel-put`: reads stdin, writes `<scratch>/<relpath>`, rejects `..` and absolute paths. Tests in `tests/scripts/keel-put_test.sh`, including here-document bodies with `;`, `&&` and `$(` (test first).
- [X] T024 Write `plugin/bin/keel-branch` (`ensure`, `next-number`), with tests in `tests/scripts/keel-branch_test.sh` (test first).
  - Ensure-scope exemptions: the ledger and the branch-name rule.
  - Halts on a dirty tree and on untracked files.
  - Handles an unborn HEAD (`symbolic-ref`), stacking from another feature branch, and default-branch detection without network.
  - The no-network test uses an unroutable remote URL.
- [X] T025 Write `plugin/bin/keel-diff` (`--unit` while open and after its commit, `--base` two-dot, `--kind` with `src/main/resources` counted as production), using the seeded temp index from `plugin/lib/common.sh`. Tests in `tests/scripts/keel-diff_test.sh`: `feature.json` never appears, a tracked-but-ignored file isn't shown as deleted, and runs from a module subdir work (test first).
- [X] T026 Write `plugin/bin/keel-evidence` (`run`/`check <unit>`), with tests in `tests/scripts/keel-evidence_test.sh` (test first).
  - `run` tees the log and records the working-tree id in `index.tsv`.
  - `check` implements the per-unit rule from data-model.md §7, reading `intent` from the ledger row:
    - the tree conditions for rules 3–4;
    - the already-failing-test RED for `FIN-n` with `intent=fix`;
    - non-behavior and refactor units skip RED.
  - It also exports the guard environment to the commands it spawns.
- [X] T027 Write `plugin/bin/keel-verify` (`run --label --kind -- <cmd>` and `detect`), with tests in `tests/scripts/keel-verify_test.sh` using a fake build command that writes surefire XML fixtures under `tests/fixtures/surefire/` (test first).
  - Baseline semantics: always `-fae -Dmaven.test.failure.ignore=true`, compiled-only pass, `TESTS=none`, `BUILD=none`, `BUILD=undetected`.
  - Later-label `NEW` rules: commands compared with keel's flags stripped, and the missing-report clause.
  - Report handling: a fresh-report start marker, and changed-test exclusion computed tree-to-tree.
  - `MISSING=test-command` only for behavior units.
  - `detect` reports `BUILD`/`TESTCMD`/`TESTFW` by build files, source extensions and test-scoped JUnit/TestNG dependencies.
  - It also exports the guard environment to the commands it spawns.
- [ ] T028 Write `plugin/bin/keel-brief` (`<unit> [--from <path>]`) and `plugin/templates/brief.md`, following the brief format in contracts/agent-handoffs.md. Tests in `tests/scripts/keel-brief_test.sh` (test first).
  - For tasks: the tasks.md line, `[US#]`, the FR and acceptance-scenario excerpts, and plan/data-model/contracts excerpts by path.
  - For MUT, REV and FIN units: the `--from` content, the touched FRs, `intent` and allowed paths.
- [ ] T029 Write `plugin/bin/keel-state` (`next`/`require`/`facts`), with tests in `tests/scripts/keel-state_test.sh` using fixture feature directories under `tests/fixtures/repos/` (test first).
  - Progress and gate candidates, read from finish downward (data-model.md §2).
  - Drift rules and the `not-a-keel-feature` test (no `**Base**` line).
  - Feature binding and `feature.json` rewriting in Spec Kit's exact format.
  - Base order: ledger, `**Base**` line, merge-base, empty tree.
  - The guard self-check, with exit 5.
  - Test cases cover:
    - every row;
    - `review done` followed by FIN commits (holds), and by a commit without an ID (re-runs);
    - `Approved` without `Path` (drift);
    - a stale `feature.json`.
- [ ] T030 Add `keel-state recover` to `plugin/bin/keel-state`, with tests in `tests/scripts/keel-recover_test.sh` (test first).
  - Every case in data-model.md §5:
    - closed and abandoned units;
    - deferred recovery;
    - recovery by attribution: named paths, evidence trees and the unit's own `[X]` line;
    - recovery that removes paths staged by an interrupted `git add` from the index;
    - a halted unit, which is never touched;
    - an unattributed change, which halts;
    - no ledger with a dirty tree, which halts.
  - A recovered unit restarts under the same ID, and new units are numbered from commits plus the ledger.

**Checkpoint**: guard suites and script suites are green. A live session blocks publishing and
allows local git. `keel-state` derives every state in the fixtures.

---

## Phase 3: User Story 1 - From feature description to an approved, reviewed plan (Priority: P1) 🎯 MVP

**Goal**: describe a feature, then a constitution and a spec, Gate 1, explorations, competing
designs, Gate 2, `plan.md` with Design Decision, and an independent plan review returning GO.
The light path uses a single design and needs only Gate 1.

**Independent Test**: in a sample repository (`tests/fixtures/sample-maven/`), describe a small
feature, answer the questions, and approve the spec and a design. Expected result: a Spec
Kit-compatible spec and plan under `specs/NNN-*/`, with a Design Decision, a GO verdict, and
exactly two approvals (one on the light path).

### Tests for User Story 1 (REQUIRED - write first, confirm they fail) ⚠️

- [ ] T031 [P] [US1] Write eval scenarios for planning, in the format from T008, and confirm they fail before the skills exist:
  - `plugin/evals/plan-before-gate1/`: plan is refused before Gate 1.
  - `plugin/evals/no-light-for-contract/`: a contract change isn't offered the light path.
  - `plugin/evals/two-gates/`: exactly two approval prompts through plan GO (a `history_file` chain).
  - `plugin/evals/light-one-gate/`: one approval on the light path.
- [ ] T032 [P] [US1] Create the sample Maven fixture `tests/fixtures/sample-maven/`: a minimal JDK 21 project with JUnit 5, one class and one test, plus a CLAUDE.md giving build/test commands and a commit style. Write `tests/fixtures/mk-sample.sh` to copy it into a fresh git repo for evals and trials.

### Implementation for User Story 1

- [ ] T033 [US1] Write the orchestrator skill `plugin/skills/run/SKILL.md`.
  - Bind the feature: next-number, then `keel-branch ensure`, then `feature.json`; pass `--feature` everywhere.
  - Order: `recover`, then `ensure`, then `recover` again when it deferred.
  - Loop over `keel-state next` → Skill tool, and stop on `done`, a halt or a gate.
  - Halt reporting, with no question.
  - Arguments: `/keel:run "<desc>"`, `/keel:run`, `/keel:run NNN`.
  - Evals: `plugin/evals/run-*/`.
- [ ] T034 [P] [US1] Write the skill `plugin/skills/constitution/SKILL.md`. It runs `keel-state require constitution`, builds the constitution from the host CLAUDE.md files by reference (FR-002), proposes principles when there are none (accepted at Gate 1), and records keel-written files in the ledger. It is adapted from Spec Kit's constitution command and carries an `Adapted from` header. Eval: `plugin/evals/constitution/`.
- [ ] T035 [US1] Write the skill `plugin/skills/specify/SKILL.md`, with an `Adapted from` header. Eval: `plugin/evals/specify/`.
  - `require`, then `mem_search` when available, citing hits (FR-004).
  - Questions one at a time on intent, goals, non-goals and anti-goals (FR-005).
  - Writes `spec.md` from the vendored template, with the `**Base**` line in the same write.
  - Writes `## Change Classification` (FR-028).
  - Records the files in the ledger.
- [ ] T036 [US1] Write the skill `plugin/skills/clarify/SKILL.md`, with an `Adapted from` header. Evals: from T031.
  - Spec Kit's ambiguity scan, up to 5 questions.
  - **Gate 1**: present the spec and its classification.
  - On approval, write `**Status**: Approved (Gate 1, date)` and `**Path**: full|light` in a single edit.
  - Light is offered only when the criteria are clear (SC-010).
- [ ] T037 [P] [US1] Write the agent `plugin/agents/explorer.md`, adapted from the vendored feature-dev code-explorer. It has the Apache §4(b) change notice, read-only tools and model sonnet, and returns its findings as its final message.
- [ ] T038 [P] [US1] Write the agent `plugin/agents/architect.md`, adapted from the vendored code-architect. It takes one lens per call from the brief (smallest, clean, pragmatic) and doesn't commit to a single design. It has the Apache change notice, read-only tools and model inherit.
- [ ] T039 [P] [US1] Write the agent `plugin/agents/plan-reviewer.md` and the template `plugin/templates/plan-review.md`. The agent is read-only and works in a fresh context. It returns four sections: critical flaws, missing assumptions, deltas and a verdict, GO or NO_GO.
- [ ] T040 [US1] Write the skill `plugin/skills/plan/SKILL.md`. Evals: `two-gates` and `light-one-gate` from T031, plus `plugin/evals/plan-reentry/`.
  - **Full path**:
    - `mem_search`, then 2–3 explorers in parallel, then architects (one lens each), then a recommendation, then **Gate 2**.
    - Write `## Design Decision` as soon as Gate 2 is answered. If the developer rejects all proposals, their own design is recorded as the chosen one, with its trade-offs against the proposals (spec edge case). Then the Phase 0/1 artifacts, then `**Plan status**: complete`.
    - Plan-review loop: a fresh reviewer each round, with the prior output and a disposition log; after 3 rounds on the same blocker, escalate. Rounds are stored with `keel-put` and appended under `## Plan Review`.
  - **Light path**: a single design. Plan review is skipped.
  - **Re-entry**: skip anything already done.

**Checkpoint**: US1 evals pass. In the sample repo, keel reaches plan GO (or a single-design plan
on the light path), and `keel-state next` returns `tasks`.

---

## Phase 4: User Story 2 - From approved plan to a verified local commit (Priority: P1)

**Goal**: tasks, then analyze (baseline verify and the docs commit), then implement (a fresh
implementer per task, evidence, task review, verify and a commit per unit), then review (3 lenses,
REV units), then finish (re-mutation, verify, FINISH). Nothing is published.

**Independent Test**: starting from a US1 plan in the sample repo, run keel to completion. The
expected result:
- commits per unit on the feature branch;
- every behavior task shows RED before GREEN;
- the build and test output is shown and passing before each commit;
- the tree is clean;
- no publish occurred.

The full end-to-end run needs US3's mutate step (T066), so it runs in Polish (T080). This phase's
own trial goes through implement (T058).

### Tests for User Story 2 (REQUIRED - write first, confirm they fail) ⚠️

- [ ] T041 [P] [US2] Write eval scenarios for implementation and review, and confirm they fail first:
  - `plugin/evals/tasks-test-setup/`: a repo with no test framework gets a setup task that names `pom.xml`.
  - `plugin/evals/analyze-critical-halts/`.
  - `plugin/evals/implement-red-green/`: the evidence check rejects a GREEN-only report.
  - `plugin/evals/review-changes-design-halts/`.
  - `plugin/evals/finish-host-commit-style/`: no AI co-author trailer when the host forbids it.
  - `plugin/evals/publish-blocked/`: a host instruction to push is not followed, and the run reports that.

### Implementation for User Story 2

- [ ] T042 [US2] Run verification items 2, 6 and 11 (non-behavior):
  - `skills:` preload in plugin agents;
  - allow rules and skill `allowed-tools` inside plugin subagents, including here-document `keel-put`;
  - agent `tools` with Bash patterns.

  Use `claude -p --plugin-dir plugin` probes, and record the results in research.md (R7) and the quickstart. Then apply decision rule 5.1 or 5.2 to the implementer's tools.
- [ ] T043 [P] [US2] Write the internal discipline skill `plugin/skills/tdd/SKILL.md` (`user-invocable: false`).
  - Adapted from vendored superpowers TDD: the Iron Law, verify RED/GREEN, rationalizations, writing good tests.
  - Java/JUnit examples replace the TypeScript ones.
  - All runs go through `keel-evidence`.
  - It carries an `Adapted from` header, and the edits are logged in `plugin/vendor/CHANGELOG.md`.
  - Eval: `plugin/evals/tdd-preload/`.
- [ ] T044 [P] [US2] Write the discipline skill `plugin/skills/debug/SKILL.md`, user-invocable.
  - Adapted from systematic-debugging: four phases, root cause first, stop after 3 failed fixes.
  - The superpowers handoffs and "human partner" wording are stripped.
  - It carries an `Adapted from` header.
  - Eval: `plugin/evals/debug-standalone/`.
- [ ] T045 [P] [US2] Write the discipline skill `plugin/skills/verify/SKILL.md`, user-invocable.
  - Adapted from verification-before-completion: the 5-step gate and the claim-versus-evidence table.
  - It runs `keel-verify detect` and `keel-verify run`, and shows the output.
  - It never claims done without evidence.
  - Eval: `plugin/evals/verify-standalone/`.
- [ ] T046 [P] [US2] Write the templates `plugin/templates/report.md` and `plugin/templates/finding.md`, following the formats in contracts/agent-handoffs.md (status, evidence, triage proposals; severity, confidence, scope). The test is `tests/scripts/templates_test.sh`, which checks that the required fields are present.
- [ ] T047 [US2] Write the agent `plugin/agents/implementer.md`.
  - Adapted from the superpowers SDD implementer prompt.
  - Frontmatter: `skills: [tdd, debug]`, tools per T042's decision, model inherit.
  - Brief rules: per-unit, no tree/index/ref-changing git, tests only through `keel-evidence` or `keel-verify`, never push.
  - It returns the report template as its final message.
- [ ] T048 [P] [US2] Write the agent `plugin/agents/task-reviewer.md`.
  - Adapted from the SDD task reviewer.
  - Read-only.
  - Its verdict is PASS or FIX, covering spec compliance, RED validity, test quality, and `**Behavior unchanged**` for refactor units.
- [ ] T049 [P] [US2] Write the agent `plugin/agents/code-reviewer.md`.
  - Adapted from the feature-dev code-reviewer, with superpowers severity calibration.
  - It carries the Apache change notice.
  - The lens comes from the brief: simplicity, correctness or conventions.
  - It returns only findings with confidence ≥ 80, each with a scope tag.
  - Read-only.
- [ ] T050 [US2] Write the skill `plugin/skills/tasks/SKILL.md`, adapted from Spec Kit's tasks command. Eval: `tasks-test-setup` from T041.
  - `require`, then `keel-verify detect`.
  - A setup task that names `pom.xml` when `TESTCMD` or `TESTFW` is none.
  - Behavior tasks name both test and production paths.
  - `[P]` markers are kept.
- [ ] T051 [US2] Write the skill `plugin/skills/analyze/SKILL.md`, adapted from Spec Kit's analyze command. Eval: `analyze-critical-halts` from T041.
  - Spec Kit's checks plus keel's checks:
    - behavior tasks without a test path;
    - light-path contract or migration tasks are CRITICAL;
    - incomplete checklists are findings;
    - a missing setup task is CRITICAL.
  - CRITICAL halts the run.
  - Closing sequence:
    1. `keel-verify --label baseline`;
    2. the porcelain check (unignored build output halts);
    3. write the `**Analyzed**` line and the `keel:baseline` comment, percent-escaped;
    4. the docs commit, staging `specs/<NNN>/**` plus a keel-written constitution.
- [ ] T052 [US2] Write the skill `plugin/skills/implement/SKILL.md`. Eval: `implement-red-green` from T041.
  - **Preflight**: the `**Analyzed**` line is in HEAD and the tree is clean.
  - **Per task, serially**:
    1. Ledger started row.
    2. `keel-brief`.
    3. Implementer.
    4. `keel-put` of the report.
    5. Status handling.
    6. The evidence rule.
    7. `keel-diff --unit`, then task-reviewer, with at most 5 fix rounds and the 3-failure debug stop.
    8. `keel-verify --label T###`.
    9. `[X]`, then a fresh unit diff staged, then the commit with the task ID, then the ledger `ok`.
- [ ] T053 [P] [US2] Write the skill `plugin/skills/respond-review/SKILL.md`, user-invocable.
  - Adapted from receiving-code-review: the 6-step pattern, a YAGNI check and push-back rules.
  - The `gh api` reply section is stripped.
  - Every comment is checked against the code, then applied or answered with a reason.
  - Eval: `plugin/evals/respond-review-standalone/`.
- [ ] T054 [US2] Write the skill `plugin/skills/review/SKILL.md`. Eval: `review-changes-design-halts` from T041.
  - `keel-diff --base`, then 3 parallel code-reviewers, then findings stored with `keel-put`.
  - Each finding is verified with the respond-review rules.
  - `intent` follows the precedence rules.
  - Fixes are made in `REV-n` units: task-reviewer, then verify, then the commit, then a scoped re-review, at most 3 rounds.
  - `changes-design` halts.
  - At the end, the ledger gets `review done <HEAD>`.
- [ ] T055 [US2] Write the skill `plugin/skills/finish/SKILL.md`. Eval: `finish-host-commit-style` from T041.
  1. Re-mutate production changes made since the test-quality commit (the commit that added `test-quality.md`), with FIN gap units.
  2. `keel-verify --label finish`, with FIN fix units and a scoped review.
  3. Apply the caps: 3 per kind, 6 passes overall.
  4. The porcelain check.
  5. The `FINISH` unit: Status `Implemented` plus the re-mutation section.
  6. The finish commit in host style.
  7. `mem_save`.
  8. The final report, which includes "not pushed" and any publish instruction that was ignored.
- [ ] T056 [US2] Add `allowed-tools` to every step skill under `plugin/skills/*/SKILL.md`, with explicit `Bash(keel-…:*)` and git/mvn rules per T042. Add the permission block to `specs/001-spec-to-commit-flow/quickstart.md`. Test: `tests/scripts/skills_frontmatter_test.sh` checks that every step skill starts with `keel-state require` and declares `allowed-tools`.
- [ ] T057 [US2] Prove the push guard end to end with eval `publish-blocked` from T041. In a sample-repo session, a host CLAUDE.md that says "push after commit" leads to no push, and the final report says the instruction was not followed.
- [ ] T058 [US2] Run the light-path trial through implement in a fresh sample repo, using `tests/fixtures/mk-sample.sh` and `claude -p --plugin-dir plugin` (non-behavior; plan M3 check). Disable superpowers and feature-dev with `--settings '{"enabledPlugins":{"superpowers@claude-plugins-official":false,"feature-dev@claude-plugins-official":false}}'`, and leave no `speckit-*` skills in the trial repo. The run stops at `mutate`, which is not built yet. Record the results in `tests/trials/RESULTS.md`.
  - Expect one approval, no other prompts, task commits with RED/GREEN evidence and verify output, and `keel-state next` = `mutate`.

**Checkpoint**: US1 and US2 evals pass. The light-path trial reaches mutate with every task
committed and evidenced.

---

## Phase 5: User Story 3 - Test quality is measured, not assumed (Priority: P2)

**Goal**: mutation analysis of changed lines with PIT (B′):
- a computed classification;
- gap resolution in MUT units, with a committed triage file;
- `test-quality.md`;
- no edits to build files.

**Independent Test**: on the seeded weak fixture, the analysis reports all three seeded weaknesses
(a missing assertion, an untested branch, duplicate tests). The gaps get resolved or triaged, and
the POM stays byte-identical (SC-013, SC-014).

### Tests for User Story 3 (REQUIRED - write first, confirm they fail) ⚠️

- [ ] T059 [P] [US3] Create the seeded fixture `tests/fixtures/maven-weak/`: a JDK 21 and JUnit 5 Maven project whose class has a missing-assertion test, an untested branch and two duplicate tests. Add the expected classification in `tests/fixtures/maven-weak/expected.tsv`.
- [ ] T060 [P] [US3] Write the slow-tier test `tests/slow/mutation_test.sh` and confirm it fails before T064. It runs the real `keel-mutate` and `keel-classify` on a git copy of maven-weak and checks that:
  - all three seeded weaknesses are reported;
  - the POM and `.mvn/` are byte-identical before and after;
  - raw output exists only under `.git/keel/`.

### Implementation for User Story 3

- [ ] T061 [P] [US3] Write the PIT XML → TSV parser `plugin/lib/pit-xml.sh`, with tests in `tests/scripts/pit-xml_test.sh` using `tests/fixtures/pit/` (a copy of the spike's `mutations.xml`, plus cases for XML entities, `test-factory`/`dynamic-test` IDs and nested classes) (test first).
  - It expects one `<mutation>` per line.
  - It writes the stable key `class|method|desc|mutator|indexes` and normalized test IDs.
  - A malformed line is exit 12.
- [ ] T062 [P] [US3] Write `plugin/bin/keel-classify`, with tests in `tests/scripts/keel-classify_test.sh` using seeded TSVs (test first).
  - Pure POSIX awk under `LC_ALL=C`.
  - Classes: coverage-gap, assertion-gap, triaged (from `--triage`), out-of-scope, redundant, kills-nothing, overlap, excluded.
  - Exit codes: 0, 1 when anything blocks, 2 for malformed input.
- [ ] T063 [P] [US3] Pin the tool versions in `plugin/lib/versions.sh`: PIT 1.30.2, pitest-junit5-plugin 1.2.3, maven-dependency-plugin 3.8.1 and maven-help-plugin 3.5.1. The test, `tests/scripts/versions_test.sh`, asserts that every Maven invocation in `plugin/bin/keel-mutate` uses only pinned coordinates.
- [ ] T064 [US3] Write `plugin/bin/keel-mutate` (`--base`/`--module`, `--classes`, `--tests`, `--budget`, `--maven`), with fast tests in `tests/scripts/keel-mutate_test.sh` against a fake mvn and `tests/slow/mutation_test.sh` against real Maven (test first).
  - Scope: changed lines from `git diff -U0 <base> HEAD`.
  - Unit-test selection: excludes integration-test names and annotations, and tests failing at baseline.
  - Exit-10 preconditions: no Java change, no POM, no JUnit Platform, or a host-configured pitest.
  - Red/flaky check: exit 11.
  - Launcher resolution through the pinned dependency/help plugins.
  - The B′ invocation runs per module with `-f`.
  - Fail-closed checks 1–5 give exit 12.
  - A budget watchdog, since there is no GNU `timeout`.
  - Output: `mutants.tsv` with `in_scope`.
- [ ] T065 [US3] Write the template `plugin/templates/test-quality.md`, following the format in contracts/mutation-runner.md. The test, `tests/scripts/templates_test.sh` (extended), checks the required fields. `Result` allows only `resolved` or `not-run`.
- [ ] T066 [US3] Write the skill `plugin/skills/mutate/SKILL.md`. Evals: `plugin/evals/mutate-not-run/` (an unsupported project gives `not-run`, with the reason) and `plugin/evals/mutate-gaps/`.
  - `require`, then `keel-mutate` in the background, then `keel-classify --triage specs/<NNN>/test-quality.triage.tsv`.
  - Up to 3 `MUT-n` units, each with:
    - an implementer working on tests only;
    - triage proposals;
    - `--kind` = `non-behavior`;
    - a task-reviewer pass;
    - `keel-verify`, then the commit;
    - a re-run on the affected classes.
  - Exit codes: 10 → `not-run`; 11 → `debug` in a `MUT-n`; 12 → halt.
  - Ends with `test-quality.md`, `keel-verify --label test-quality` and the commit.
- [ ] T067 [US3] Write the skill `plugin/skills/test-audit/SKILL.md`, user-invocable. It runs `keel-mutate --module` and `keel-classify`, writes its report to `.git/keel/audit/<ts>/report.md` through the script, never edits build files, and needs no feature run. Eval: `plugin/evals/test-audit-standalone/`.
- [ ] T068 [US3] Run verification item 10 and the PayConductor audit (non-behavior).
  - Probe `-pl <module> -am` with `mutationCoverage` on a copy of maven-weak turned multi-module. Record the result in research.md (R7) and switch the default only if it is verified.
  - Run `/keel:test-audit payment-service` read-only against PayConductor and record the report summary in `tests/trials/RESULTS.md`.

**Checkpoint**: `tests/run.sh --slow` is green (SC-013, SC-014). The mutate evals pass. The light-path
trial now reaches review.

---

## Phase 6: User Story 4 - Resume an interrupted run (Priority: P2)

**Goal**: resume from any interruption point without redoing work or re-asking approvals (SC-005).

**Independent Test**: interrupt after each step, and at every unit boundary, then resume. The run
completes with no task redone and no gate asked twice.

- [ ] T069 [US4] Write the resume-matrix test `tests/scripts/resume_matrix_test.sh`. It drives `keel-state next/recover` and `keel-branch` against fixture repos built at each interruption point:
  - every §2 row;
  - between Gate 2 and `Plan status: complete`;
  - mid-task;
  - between `[X]` and the task commit;
  - between a commit and its ledger `ok`;
  - in MUT-2 after MUT-1 was committed;
  - between the MUT-1 commit and the start of MUT-2;
  - after the REV-1 commit;
  - in FIN-1;
  - between the FINISH edit and the finish commit;
  - between the finish commit and its ledger `ok`;
  - a mixed-intent REV round;
  - interleaved features with a stale `feature.json`;
  - resuming 001 from 002 with a started unit and a dirty tree (expect a halt);
  - lost `.git/keel/` before and after the docs commit;
  - done after finish.

  This test only exercises the existing scripts. It passes once T029–T030 are correct; fix any failure there.
- [ ] T070 [US4] Write eval `plugin/evals/resume-no-regate/`: resuming after Gate 2 doesn't re-ask the design, and resuming mid-implementation runs only the remaining tasks (US4 acceptance scenarios 1 and 2).

**Checkpoint**: the resume matrix and the resume eval pass.

---

## Phase 7: User Story 5 - Decisions carry across features (Priority: P3)

**Goal**: optional engram use:
- recall before specify and plan;
- one keyed entry per feature, saved after Gate 2 (or the light-path plan) and after finish;
- silent skip when engram is absent;
- no session-lifecycle calls.

**Independent Test**: with memory present, two related features produce one entry each, and the
second feature cites the first. With memory absent, the outcome is the same and there are no
errors (SC-008).

- [ ] T071 [US5] Write the eval scenarios `plugin/evals/memory-absent/` and `plugin/evals/memory-keyed/` (test first; they fail until T072).
  - The run completes without engram.
  - `mem_save` uses `topic_key: keel/<NNN-feature>` exactly twice.
  - No `mem_session_*` call happens.
  - `judgment_required` is resolved without a prompt.
- [ ] T072 [US5] Add the keyed engram saves to `plugin/skills/plan/SKILL.md` and `plugin/skills/finish/SKILL.md`, and the recall to `plugin/skills/plan/SKILL.md`. Check that T035's recall in `plugin/skills/specify/SKILL.md` follows the same rules. Each call is conditional on the tool existing, errors are swallowed and noted in the final report, there are no other saves during a run, and `judgment_required` is resolved silently.

**Checkpoint**: the memory evals pass with engram both present and absent.

---

## Phase 8: User Story 6 - Debug, verify, audit tests and handle review feedback outside a feature run (Priority: P3)

**Goal**: four standalone capabilities that behave like their in-run steps (FR-027, SC-011).

**Independent Test**: with no feature run, each of `/keel:debug`, `/keel:verify`,
`/keel:respond-review` and `/keel:test-audit` completes a trial task.

- [ ] T073 [US6] Make the standalone mode work for `plugin/skills/{debug,verify,respond-review,test-audit}/SKILL.md`.
  - With no feature, `keel-state require` runs only the guard self-check.
  - These skills write no feature state.
  - The standalone evals from T044, T045, T053 and T067 pass.
- [ ] T074 [US6] Run the standalone trials in the sample repo and PayConductor, one per capability, and record them in `tests/trials/RESULTS.md` (non-behavior; SC-011).

**Checkpoint**: the four standalone evals and trials pass.

---

## Phase 9: Polish & Cross-Cutting Concerns (plan M8)

- [ ] T075 [P] Write the mutation self-check `tests/mutation-self-check.sh`.
  - It applies listed sed mutants to temp copies of:
    - `plugin/shims/git`, `plugin/shims/gh` and `plugin/hooks/guard-push.sh`;
    - `plugin/bin/keel-classify`, `plugin/bin/keel-state` and `plugin/bin/keel-evidence`.
  - It asserts that each mutant fails its suite.
  - Survivors are listed, then triaged in `specs/001-spec-to-commit-flow/test-quality.md`, the feature's own test-quality summary under Principle V.
- [ ] T076 [P] Add the eval scenarios `plugin/evals/unsupported-not-run/` and `plugin/evals/full-path-trial/`, and run the full suite with `tests/run.sh --eval`. Results go in `tests/trials/RESULTS.md`.
- [ ] T077 [P] Write `README.md` at the repository root: what keel is, install, enable per repository, flow, gates, guard layers and escape hatch, standalone skills, and how to develop keel. Update `specs/001-spec-to-commit-flow/quickstart.md` with the final verified-facts table.
- [ ] T078 Write keel's own `CLAUDE.md` guidance. Keep the SPECKIT marker block and add:
  - bash 3.2 and BSD rules;
  - test commands;
  - the vendoring change-log rule;
  - never push.
- [ ] T079 Check provenance and validation end to end (non-behavior).
  - `claude plugin validate plugin/` and `tests/scripts/provenance_test.sh` pass.
  - Every adapted skill and agent has its header.
  - `plugin/vendor/CHANGELOG.md` lists every in-place edit.
- [ ] T080 Run the full-path trial in a fresh sample repo, end to end (description to finish), with `claude -p --plugin-dir plugin` and `history_file` chaining for the two gates (non-behavior). Disable superpowers and feature-dev through `--settings` `enabledPlugins`, as in T058, and check that no Spec Kit CLI or `speckit-*` skill is reachable (SC-007). Also run Spec Kit's analyze on the result, from a separate checkout that has the Spec Kit install, to confirm SC-006.
  - Check SC-001 to SC-008 and SC-010 to SC-014 against the run.
  - Count permission prompts (SC-001).
  - Record the results in `tests/trials/RESULTS.md`.
- [ ] T081 Write `specs/001-spec-to-commit-flow/test-quality.md` for keel itself (Principle V).
  - Include the mutation self-check results, with triaged survivors and their reasons.
  - State that PIT doesn't apply to bash, and that the sed mutants are its equivalent.
- [ ] T082 Run the full suite (`tests/run.sh` and `tests/run.sh --slow`) and show the output before the final commit (Principle V). Commit on `001-spec-to-commit-flow` (never push).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. It blocks every user story, because every step skill
  runs `keel-state require`, which needs the guard self-check and the state scripts.
- **US1 (Phase 3)**: depends on Foundational.
- **US2 (Phase 4)**: depends on Foundational. Its trial (T058) needs US1's skills (T033–T040). Its
  full end-to-end run needs US3's mutate step (T066), so that run is in Polish (T080).
- **US3 (Phase 5)**: depends on Foundational. `finish`'s re-mutation (T055) calls `keel-mutate`
  (T064) at run time, not at authoring time.
- **US4 (Phase 6)**: depends on T029–T030 and on the unit flow in T052, T054 and T055.
- **US5 (Phase 7)**: depends on T035, T040 and T055 (it edits those skills).
- **US6 (Phase 8)**: depends on T044, T045, T053 and T067.
- **Polish (Phase 9)**: depends on everything before it.

### Within Each Phase

- Test or eval tasks come first and must fail before implementation.
- `plugin/lib/common.sh` (T003) comes before every script. `json.sh` (T009) comes before
  `guard-push.sh`. `shim-common.sh` (T010) comes before the shims.
- `keel-ledger`, `keel-put`, `keel-diff`, `keel-evidence` and `keel-verify` come before
  `keel-state` (T029), which reads their outputs.
- Agents come before the skills that dispatch them (T037–T039 before T040; T047–T049 before
  T052–T055).

### Parallel Opportunities

Tasks marked [P] touch different files and have no dependency on an incomplete task:
- T004–T006: vendoring.
- T014: thin shims.
- T022–T023.
- T031–T032.
- T034, T037–T039.
- T043–T046, T048–T049, T053.
- T059–T063.
- T075–T077.

keel's own development runs them serially anyway (serial `[P]`, plan §Implement).

---

## Parallel Example: User Story 1

```bash
# Agents and the constitution skill touch different files:
Task: "T037 [P] [US1] Agent plugin/agents/explorer.md"
Task: "T038 [P] [US1] Agent plugin/agents/architect.md"
Task: "T039 [P] [US1] Agent plugin/agents/plan-reviewer.md + plugin/templates/plan-review.md"
Task: "T034 [P] [US1] Skill plugin/skills/constitution/SKILL.md"
```

---

## Implementation Strategy

### MVP First (Setup + Foundational + User Story 1)

1. Phase 1, then Phase 2. The guard and state scripts are the riskiest code and gate everything.
2. Phase 3 (US1): keel can take a description to an approved, reviewed plan.
3. **Stop and validate**: run the US1 evals and the sample-repo planning run.

### Incremental Delivery

1. Add US2 through implement: the light-path trial reaches mutate (plan M3).
2. Add US3: mutation, then the trial reaches review. Then complete US2's review and finish.
3. Add US4 (resume matrix), US5 (memory) and US6 (standalone).
4. Polish: the self-check, the full-path trial, docs and the final verify.

---

## Notes

- **Before every commit**, run `tests/run.sh` and show its output. From T060 on, also run
  `tests/run.sh --slow` when mutation code changed. Never commit on red (constitution V, which
  applies to keel's own development). Docs-only commits made before the harness exists (T002) show
  "no test suite yet".
- Commit after each task or logical group on `001-spec-to-commit-flow`. Never push.
- Host rules (global CLAUDE.md) apply to keel's own commits: no AI co-author trailer.
- Vendored files are never edited in place without a `plugin/vendor/CHANGELOG.md` entry
  (constitution Development Workflow).
