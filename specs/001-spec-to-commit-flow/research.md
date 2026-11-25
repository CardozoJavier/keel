# Research: Spec-to-Commit Feature Delivery (keel v1)

**Feature**: [spec.md](./spec.md) | **Date**: 2026-11-25 | **Phase**: 0 (input to design options)

Sources were read on 2026-11-25: Spec Kit 0.8.4.dev0 as installed in this repo, superpowers 7.0.2 and
feature-dev 1.0.1 from the local plugin cache, and the Claude Code docs at code.claude.com.
Installed Claude Code version: 2.1.331 (2.1.332 at plan time). Machine has bash, git, jq and python3;
keel may rely only on bash and git (constitution, Plugin Constraints). The only bash on macOS is
`/bin/bash` 3.2.57 and awk is BSD awk 20200816, so scripts target bash 3.2 and POSIX awk.

## R1. Spec Kit: what keel must carry

- **Decision**: Vendor the scripts `common.sh`, `check-prerequisites.sh` and `setup-plan.sh`, plus
  the templates `spec`, `plan`, `tasks`, `checklist` and `constitution`. Rewrite the step skills
  from Spec Kit's, dropping the extension-hook boilerplate (`.specify/extensions.yml`
  pre/post blocks in every skill), the presets/extensions/overrides template-resolution layers, and
  the CLI-only workflow engine and manifests.
- **Rationale**: These are the only parts the step skills use at runtime. No skill calls the
  `specify` CLI. Python and jq are optional: `common.sh` falls back from jq to python3 to grep/sed
  for JSON, so bash and git suffice.
- **Minimal target-repo footprint**: `.specify/` (it marks the repo root),
  `.specify/memory/constitution.md`, `.specify/feature.json` (written at runtime), and
  `specs/NNN-feature/`. The templates and scripts can be served from the plugin itself, so they
  need not be copied into each repo.
- **Constraints found**:
  - `check-prerequisites.sh` always enforces an `NNN-`/timestamp-prefixed branch when git is
    present (common.sh:128-154). keel's branch name must follow that format.
  - `create-new-feature.sh` runs `git fetch --all` and `ls-remote` (:155-168), which breaks the
    no-network rule. keel needs a local-only branch step. No step skill calls this script.
  - `speckit-plan` rewrites a marker block in the host's `CLAUDE.md` (agent context update) and
    `speckit-implement` creates or patches `.gitignore`, `.dockerignore` and others. Both modify
    host files. **Resolved (plan)**: both dropped; keel's scratch lives in `.git/keel/`.
  - `speckit-implement`'s only interactive gate is the checklist gate (incomplete checklist means
    ask). Under Principle IV it must become a halt condition or be resolved automatically.
    **Resolved (plan)**: incomplete checklists become `analyze` findings; never a prompt.
- **Worth keeping from implement**: the task format `- [ ] T### [P?] [US#?] description + path`,
  `[X]` completion marking, the context load list, halt on sequential failure, and completion
  validation.

## R2. superpowers: what to adapt (MIT)

- **Keep, close to verbatim**:
  - test-driven-development: Iron Law, verify RED/GREEN, rationalizations, `writing-good-tests.md`.
  - systematic-debugging: four phases; stop after 3 failed fixes.
  - verification-before-completion: 5-step gate, claim-vs-evidence table.
  - receiving-code-review: 6-step response pattern, YAGNI check, push-back rules.
  - requesting-code-review: reviewer severity calibration and the "Do Not Trust the Report" stance.
  - dispatching-parallel-agents: independence test.
  - using-git-worktrees: baseline tests before starting, `git check-ignore` before creating a
    project-local directory.
- **Strip**:
  - Cross-skill handoffs and `docs/superpowers/` paths.
  - Every push, PR and merge path: finishing-a-development-branch keeps only "full suite green"
    plus "branch left as-is"; drop the `gh api` reply section in receiving-code-review.
  - "Your human partner" phrasing.
  - TypeScript examples; replace with Java/JUnit.
- **subagent-driven-development (SDD) is the execution engine to adapt**:
  - A fresh implementer per task, then a task review (spec compliance plus quality), then a fix
    loop of at most 5 rounds with scoped re-reviews, then one whole-branch review.
  - Handoffs go through files (brief, report, review package), never pasted text.
  - Implementer statuses are DONE, DONE_WITH_CONCERNS, BLOCKED and NEEDS_CONTEXT.
  - Record BASE before each dispatch; never use `HEAD~1`.
  - Never run parallel implementers.
  - A ledger file makes resume possible.
- **Adapting SDD to Spec Kit**:
  - `task-brief` parses `# Task N` headings and needs replacing with a Tnnn-aware brief builder
    that pulls the task line plus the relevant spec and plan excerpts.
  - The ledger moves from `.superpowers/sdd/<plan>/` to an ignored per-feature location, and
    resume cross-checks the ledger, `tasks.md` checkboxes and `git log`.
  - `[P]` conflicts with "no parallel implementers": the safe default is serial.
  - `[US#]` labels allow per-story checkpoint reviews.
  - TDD evidence has to come from keel's implementer prompt, because tasks.md has no TDD steps.

## R3. feature-dev: what to adapt (Apache-2.0, attribution and change notices required)

- `code-explorer`: method and output (entry points with file:line, flow, components, essential
  files) kept nearly verbatim.
- `code-architect`: blueprint output (patterns, decision, components, implementation map, data
  flow, build sequence). Its "commit to one approach" line conflicts with the 2–3 options model;
  this is resolved by giving each agent one lens (minimal, clean, pragmatic). Its build sequence
  should feed tasks.md.
- `code-reviewer`:
  - The model scores itself 0–100 per issue and reports only issues scoring 80 or more.
  - The agent has no Bash, yet defaults to reviewing `git diff`, so keel must hand it the diff
    as a file.
  - Its scale isn't calibrated against SDD's Critical/Important/Minor; keel needs one severity
    model.
- All three default to model `sonnet` with read-only tools.

## R4. Claude Code plugin mechanics (docs fetched 2026-11-25)

- **Layout**: `.claude-plugin/plugin.json` (only `name` required); `skills/<name>/SKILL.md`,
  `agents/*.md` and `hooks/hooks.json` at the plugin root; `bin/` is added to Bash's PATH. Skills
  supersede commands for new work.
- **Naming**: skills run as `/keel:<name>`; agents are `keel:<name>`.
- **Paths**: `${CLAUDE_PLUGIN_ROOT}` is substituted in skills, agents and hook commands, so bundled
  templates and scripts can be referenced without copying them into the repo.
  `${CLAUDE_PLUGIN_DATA}` persists across updates.
- **Enforcement hook**:
  - A PreToolUse hook with matcher `Bash` blocks by exiting with code 2 (or returning a JSON
    `permissionDecision: deny`).
  - `onFailure: "block"` makes crashes and timeouts fail closed (needs v2.1.295 or later;
    2.1.331 is installed).
  - The `if` filter takes one rule and can't be relied on for unparseable commands, so the hook
    script should inspect every Bash command itself.
- **Scope**: plugin hooks fire inside subagents too, so the push block covers implementers. It is
  undocumented whether they fire for user `!` commands; verify empirically.
- **Plugin agents**: frontmatter supports `tools`, `disallowedTools`, `model`, `skills`,
  `isolation: worktree`, `maxTurns`. `hooks` and `permissionMode` are ignored in plugin agents.
  Dispatching an agent by name from a skill is done in natural language.
- **Testing**:
  - `claude plugin eval` runs scenario cases with graders (regex, tool_used, tool_order,
    file_exists, llm), giving scenario checks for skills (Principle V).
  - No documented approach for hook scripts; test them by piping sample JSON.
  - `claude plugin validate` checks structure only.
- **Personal install**: a local marketplace with a relative-path source loads in place, so
  `/reload-plugins` picks up edits. `claude --plugin-dir` works for single sessions.
  `enabledPlugins` in `.claude/settings.local.json` disables other plugins for one user, per repo.

## R5. Mutation analysis on Java/Maven (PIT)

- **Spike** (2026-11-25, payconductor/payment-service): PIT 1.30.2, pitest-junit5-plugin 1.2.3,
  JDK 21.0.6, with a throwaway class and tests (one solid test, one with a missing assertion, one
  duplicate) added only in the copies. Logs:
  `/private/tmp/claude-501/-Users-javiercardozo-dev-projects-payconductor/e517ffa1-998e-4d0f-9be1-7666010ddcae/scratchpad/pit-spike/`.

  | Approach | Works | Wall time | Caveat |
  |---|---|---|---|
  | A: worktree, PIT declared in the copy's POM | yes | 4.5s | needs a second checkout, compile and POM edit |
  | B: Maven plugin from the command line, no JUnit 5 plugin | **no: silent** | 5.8s | exit 0, BUILD SUCCESS, 0 tests ran, every mutant NO_COVERAGE |
  | B': B plus `-DadditionalClasspathElements=<junit5-plugin jar>,<junit-platform-launcher jar>` | yes | 2.8s | jar paths must be resolved first (`dependency:get`) |
  | C: PIT command-line runner on the resolved classpath | yes | ~4s total | keel assembles the classpath itself |

  A, B' and C produced byte-identical `mutations.xml`.
- **Decision**: B' is the v1 runner. It needs no POM edit and no worktree, runs on the clean
  feature-branch checkout, and is the fastest. C is the documented fallback; A is not needed.
  - The maintainer's worktree suggestion works, but B' gets the same result without the extra
    checkout and compile.
- **Findings that shape the runner**:
  - **Silent false negative**: without the JUnit 5 plugin, PIT reports success with zero tests
    run. The runner MUST treat "no tests ran" or "every mutant NO_COVERAGE although covering
    tests exist" as a tool failure, never as coverage gaps (fail closed, FR-035).
  - **Full matrix needed**:
    - `fullMutationMatrix=true` requires XML output. Each mutation then lists *all* killing tests
      (`<killingTests>`, `|`-separated) plus `<succeedingTests>` and `<coveringTests>`.
    - Without the matrix, only the first killer is recorded and redundancy can't be computed.
    - In the spike's data, the duplicate test's kills were a strict subset of the solid test's,
      and the missing-assertion test covered code but killed nothing.
  - **Test launcher**: pitest-maven does not add `junit-platform-launcher`; without it the coverage
    minion crashes. The runner adds the launcher jar matching the project's JUnit platform version.
  - **Multi-module**: run per module with `-f <module>/pom.xml`. A broken sibling module breaks
    `-pl` from the root.
  - **Scope `targetTests` to unit tests**: Spring, Testcontainers and Quarkus tests would run once
    per mutant. Quarkus classloading is unverified.
  - **Java 25 works**: class major 69, ASM 9.11. JVM and Maven startup dominate the runtime, at
    about 1s of PIT analysis for 7 mutants.
  - **Raw output stays out of version control**: reports go under the ignored scratch area (e.g.
    `-DreportsDirectory`), not tracked paths.
- **Interface designs can assume**: input is the changed classes and the relevant unit tests;
  output is a per-mutant table (status plus all killing tests), classified by a script into
  coverage gaps, assertion gaps, redundancy and overlap.
- **Constitution impact**: tool caches (`~/.m2`, `${CLAUDE_PLUGIN_DATA}`) and any worktree outside
  the repo are writes outside the target repository; the plan's Constitution Check must address
  them. **Resolved (plan)**: constitution v1.3.0 carves out the build tool's own caches; B′ needs
  no worktree; `${CLAUDE_PLUGIN_DATA}` is unused.
- **Fail-closed signals found in the spike logs**: the silent run logs `JUnit 5 is on the classpath
  but the pitest junit 5 plugin is not installed` and has no `Largest test (` line although test
  classes were sent to the minion; working runs log `Largest test (...) covered N blocks`. PIT
  writes one `<mutation>` element per line in `mutations.xml`.

## R6. engram

- **Verified**: `mem_save` with the same `topic_key` updates the existing observation; the second
  save kept the same id. That confirms the per-feature-key behavior FR-025 relies on.
- The project is detected from the working directory (git remote). Saves made from a target repo
  are filed under that repo's project, which is what keel wants.
- Memory tools may be absent; FR-025 requires silent skip.

## R7. Empirical checks during implementation

- **R7.1 `claude plugin eval`** (T008, 2026-11-25, Claude Code 2.1.332):
  - **Cases**: they must live below the plugin root (`plugin/evals/<case>/`, with `prompt.md` and
    `graders/*.md`, or `case.yaml`). `context.scaffold_script` and `context.history_file` exist only
    in `case.yaml`.
  - **Grader types**: regex, tool_used (`max: 0` for "not used"), tool_order, file_exists, llm and
    baseline.
  - **The plugin is enabled automatically**: a smoke case passed, with the plugin under test loaded
    by the runner.
  - **Finding**: a manifest with `defaultEnabled: false` makes the runner run **without** the
    plugin ("nothing in the eval sandbox enables it"). Decision: drop `defaultEnabled`; keel is
    installed per repository with `claude plugin install keel@keel --scope local`, which keeps its
    hooks out of other sessions just as well. The plan, quickstart and push-guard contract were
    updated.
  - **Still open, for T031**: the `history_file` `.jsonl` format, and whether a call blocked by a
    PreToolUse hook counts in `tool_used`.
- **R7.2 Live push-guard verification** (T021, 2026-11-25):
  - **Setup**: `tests/tools/live_guard_probe.sh`, run as `claude -p --plugin-dir plugin` with haiku
    in a throwaway repo whose only remote is a local bare repo. The **remote had 0 refs
    afterwards**.
  - **Blocked**: zsh alias `gp` (shim A1); a post-commit hook running `git push` (A0, via the
    rewrite helper); `zsh -lc 'git push'` (layer B, B4); `git push --no-verify` (layer B, B3).
  - **Allowed**: `git stash push -m wip`, `git rebase -x true HEAD~1`.
  - **Item 5** (session env in subagents and skill-injected commands): **yes, both**. A
    general-purpose subagent's Bash and a skill's injected command both saw `KEEL_ROOT` and `git`
    resolving to the shim. Decision rule 5 is not needed: no `tools` restriction and no
    `updatedInput` fallback.
  - **Item 7** (`PreSkillShellCommand`): skill-injected commands don't reach PreToolUse, and no
    payload was logged for them. They run with the session env, so A0 and A cover them. keel
    doesn't register that event; layer B is not applied to commands written inside skills.
  - **Item 3** (Monitor): the tool name is `Monitor`, and its payload carries
    `tool_input.command` (plus `description` and `timeout_ms`). It is covered by the shell matcher
    and logged by `KEEL_GUARD_LOG`.
  - **Item 8** (env lifetime): the env persists across `cd`, and after `claude -p --continue`
    (resume) `KEEL_ROOT`, the shim and all 5 A0 entries were present. `/clear`, compaction and
    fork are interactive-only; they are checked in the interactive trials (T058/T080).
- **R7.3 Skill checks can't run under `claude plugin eval`** (T031, 2026-11-25):
  - **Finding**: the eval sandbox refuses to **execute** files from the plugin directory. A skill's
    `keel-state require …` failed with `operation not permitted: keel-state` (exit 127), and every
    US1 case scored 0 for that reason, not because of skill behavior. `bash "$KEEL_ROOT/bin/…"`
    works, but the git shim is executed directly by every `git` call, so the guard and every keel
    script would have to be special-cased for the sandbox.
  - **Decision**: keep `plugin/evals/smoke` (plugin loading). Check skill and agent behavior with
    `tests/scenarios/*_scenario.sh`: real `claude -p --plugin-dir plugin` sessions in scaffolded
    repos, with superpowers, feature-dev, pr-review-toolkit and engram disabled via `--settings`,
    and deterministic asserts on files, branches and `keel-state`.
  - **Mechanics**: a multi-turn gate is `claude -p --continue` in the same repo, which replaces
    `history_file`. Agent dispatches are asserted on `--output-format stream-json` output.
  - **Cost**: about one model session per turn. Scenarios run only with `tests/run.sh --scenarios`,
    never in the default suite.
  - **Discrimination** (T044/T045/T053): the base model already debugs a planted bug and handles a
    review comment well without keel's skill, so outcome-only asserts passed RED. Each scenario
    therefore also asserts something only the skill causes (for example the guard precondition,
    a dispatched keel agent, or a keel script's record), and is confirmed RED against a plugin
    copy without the skill (`KEEL_SCN_PLUGIN`).
- **R7.4 Agent preloads and permissions in subagents** (T042, 2026-11-25, verification items 2, 6
  and 11):
  - **Setup**: `tests/tools/t042_probe.sh`, with a probe plugin next to keel. Each case is a
    `claude -p` session using haiku, `--setting-sources project` (no user rules) and
    `--permission-mode default`, so only the rules named per case can allow a call.
  - **Item 2**: a `skills:` preload works in plugin agents. A Read-only agent answered with the
    preloaded skill's token and read no files.
  - **Item 6, allow rules**: with only `Agent` allowed, a subagent's `keel-put` here-document was
    denied (the control). With `Bash(keel-put:*)` also allowed, the same call ran. The rule matched
    a body containing `;`, `&&` and `$(`. Quickstart allow rules therefore cover subagents, and
    `keel-put` keeps its here-document form.
  - **Item 6, skill `allowed-tools`**: these apply in a subagent only when it invokes the skill
    with the Skill tool. Preloading the same skill with `skills:` granted nothing; the call was
    denied.
  - **Item 11**: Bash patterns in an agent's `tools` don't restrict it. `tools: Bash(echo:*)` still
    ran `ls /`, so decision rule 5.1 would not have been available. Item 5 was already yes
    (R7.2), so rule 5 isn't applied at all.
  - **Decision for the implementer (T047)**:
    - `tools: Read, Write, Edit, Grep, Glob, Bash`.
    - `skills: [tdd, debug]` carries content only.
    - Its commands are permitted by the quickstart allow list. T056 extends that list with what an
      implementer runs: `keel-evidence`, `keel-verify` and the read-only git commands.
    - Step skills keep `allowed-tools`, which apply because the run invokes them with the Skill
      tool in the main session.
- **R7.5 IDE build output can make surefire run 0 tests** (T052 scenario, 2026-11-25):
  - **Finding**: in a nested session, the user-level `jdtls-lsp` plugin compiled
    `PriceTest.java` with ECJ but **without the Maven classpath** ("Test cannot be resolved to a
    type"). It wrote stub classes into `target/test-classes` that carry no `@Test` annotations, and
    created `.project`, `.classpath` and `.settings/`.
    - Maven treated the stubs as up to date, so `mvn verify` exited 0 with "Tests run: 0".
    - `mvn clean test` ran all 4 tests.
  - **What keel did**: it failed closed for that behavior unit (`MISSING=test-command`). But a
    baseline or a non-behavior unit would have passed as "no tests yet" (`TESTS=none`), a silent
    false green.
  - **Decision**: when a Maven run has test sources (`src/test/**` with a JVM extension) but
    produces no fresh reports, `keel-verify` now returns `RESULT=fail MISSING=test-reports` for
    every label, with a "clean the build output (mvn clean)" hint. `MISSING=test-command` remains
    only for a behavior unit in a repository with no test sources.
  - **Environment**: scenarios disable `jdtls-lsp` (and the GitHub plugin). The quickstart says to
    ignore IDE metadata (`.project`, `.classpath`, `.settings/`).
  - **The same run also exposed an orchestrator downgrade**: review re-scoped a reviewer's
    `changes-design` finding to in-design while admitting the fix only met "exact to the cent"
    approximately. The review skill now keeps a reviewer's `changes-design` scope unless an
    in-design fix fully meets every cited requirement.
- **R7.6 Module arguments for mutation analysis** (T068, 2026-11-25, verification item 10):
  - **Setup**: a two-module reactor where `app` depends on `lib`. The feature changes `app` only,
    and nothing is installed in `~/.m2`.
  - **`-f app/pom.xml`** (the planned default) **fails**: "Could not resolve dependencies …
    example.multi:lib:jar:1.0.0-SNAPSHOT". A clean multi-module checkout can't use it.
  - **`-pl app -am`** with `-DfailWhenNoMutations=false` **works**.
    - `lib` logs "No mutations found" and passes.
    - `app` runs last, and its `mutations.xml` is the final one (2 mutants, both from
      `app.Checkout`).
    - A goal-only call (`dependency:list`) needs `test-compile` in the same run, or the reactor
      has no classes for `lib`.
  - **PayConductor**: the root reactor can't load, because `projection-service/pom.xml` has a
    dependency with no version (`quarkus-smallrye-reactive-messaging-kafka`). This is R5's "broken
    sibling".
  - **Decision**: keel-mutate probes reactor mode per submodule (`-pl <m> -am` with the pinned help
    plugin) and falls back to `-f <m>/pom.xml`. Both paths are tested:
    - the fast tier, against a fake reactor and a fake failure;
    - the slow tier, on a real two-module reactor with nothing installed;
    - the PayConductor audit, which uses the fallback.
  - **PayConductor audit** (`payment-service`, read-only):
    - 22 classes, all NO_TEST: the module has no tests yet, so PIT wasn't run.
    - Report under `.git/keel/audit/`. The tree is unchanged and nothing was committed.
    - The run exposed two clarity fixes, now made:
      - the summary now says `coverage gaps 22 (22 with no test)` instead of reading as "0
        mutants";
      - `command.txt` says why PIT wasn't run.
  - **Item 1** (user `!` commands): interactive-only, checked in T058/T080. It isn't required by
    FR-022, which covers the assistant's actions.
  - **Item 9** (minimum git for config hooks): the exact version is not determinable offline.
    It doesn't need to be: the functional self-check (`git hook list pre-push` must list keel's
    hook) refuses any git that lacks config hooks, so keel needs no version constant. Verified
    working on 2.54.
