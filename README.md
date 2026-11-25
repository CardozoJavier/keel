# keel

keel is a Claude Code plugin for spec-driven feature delivery. A developer describes a feature in
plain language; keel takes it through Spec Kit's flow to **local commits on a feature branch, ready
to push**. It never pushes, never opens a pull request, and blocks the paths an agent could use to
publish.

It combines three sources into one self-contained plugin:

- **Spec Kit** (MIT): the flow and its artifacts.
- **superpowers** (MIT): execution discipline.
- **feature-dev** (Apache-2.0): exploration, competing designs and multi-lens review.

There is no runtime dependency on any of them. The copied material lives in `plugin/vendor/`, with
its provenance and every edit recorded.

## The flow

```text
constitution → specify → clarify ─▶ GATE 1 (approve the spec) → plan ─▶ GATE 2 (pick a design)
  → plan review (fresh reviewer, GO/NO_GO) → tasks → analyze → implement → mutate → review → finish
```

| Step | What it does |
|---|---|
| constitution | Builds `.specify/memory/constitution.md` from the host's `CLAUDE.md` rules, referring to them instead of copying them. |
| specify, clarify | Asks about intent, goals, non-goals, anti-goals and missing requirements, one question at a time. Writes a Spec Kit spec with a change classification. **Gate 1** approves it. |
| plan | Explorers map the code; 2–3 architects design through competing lenses (smallest change, clean architecture, pragmatic balance); keel recommends one. **Gate 2** picks it. The plan records the chosen and rejected designs. Fresh plan reviewers return GO or NO_GO; a blocker that survives 3 rounds escalates. |
| tasks, analyze | Test-first tasks, each behavior task naming its test. Cross-artifact analysis halts on CRITICAL findings, then records the baseline build and tests and makes the docs commit. |
| implement | One work unit per task. A fresh implementer works test-first through `keel-evidence`, which records RED before GREEN. A fresh task reviewer checks the unit. `keel-verify` runs the build and tests, and the unit is committed with its task ID. |
| mutate | Mutation analysis (PIT) on the lines the feature changed. Every gap is closed by a test or by a committed triage reason. The result is computed, never judged. |
| review | Three parallel reviewers (simplicity, correctness, conventions), keeping findings at confidence ≥ 80. Each finding is verified before it's fixed in a `REV-n` unit. A finding that needs a different design halts the run. |
| finish | Re-mutates late fixes, runs the full build and tests, sets the spec to `Implemented`, commits in the host's style, and reports. Nothing is pushed. |

- **Human input**: the only prompts in a run are clarification questions and the two gates.
- **Light path**: a small change (no external contract, no persisted data, easy to reverse) can be
  approved for the light path at Gate 1. It then has one gate and no competing designs or plan
  review.
- **Resume**: every step's state is derived from the artifacts and commits, so `/keel:run`
  resumes an interrupted run. No gate is asked twice and no committed work is redone.

## Install and enable (per repository)

```text
claude plugin marketplace add ~/dev/projects/keel             # once
cd <repo> && claude plugin install keel@keel --scope local    # per repository
```

Then start a new session in that repository. Install at local scope only: keel's push guard should
be active only where keel runs. The recommended repository settings are in
`specs/001-spec-to-commit-flow/quickstart.md`:
- enable keel;
- disable superpowers and feature-dev;
- add the allow list for keel's own commands.

| Command | Use |
|---|---|
| `/keel:run <feature description>` | Start a feature. |
| `/keel:run` | Resume the current feature. |
| `/keel:run NNN` | Resume a specific feature. |
| `/keel:debug <symptom>` | Root-cause debugging, outside a feature run. |
| `/keel:verify` | Run the host's build and tests and report with evidence. |
| `/keel:respond-review <comments>` | Verify review comments against the code; apply them or push back. |
| `/keel:test-audit <module>` | Mutation audit of a Maven module's tests; read-only, report under `.git/keel/audit/`. |

## The push guard

keel blocks publishing in three layers:

- **A0, git configuration**: environment-only git config entries. A pre-push hook denies every
  push, and every push URL is rewritten to an unroutable transport.
- **A, shims**: wrappers for `git`, `gh`, `jj`, `sl`, `gt`, `glab` and `hub`, first on `PATH`.
  - They deny push-like and forge-write subcommands.
  - Local git (stash, rebase, reset, cherry-pick) is never blocked.
- **B, a PreToolUse hook**: checks every shell command, including the ways around A0 and A
  (`--no-verify`, `PATH` changes, `zsh -lc`, `env -i`). It also covers forge MCP tools.

keel runs refuse to start when a layer is missing. **Escape hatch**: to push from a keel-enabled
repository, run `git push` yourself in a shell outside Claude Code, or start a session with
`claude --settings '{"disableAllHooks": true}'`. The known limits are listed in
`specs/001-spec-to-commit-flow/contracts/push-guard.md`.

## Memory (optional)

If engram is installed, keel recalls related decisions before specify and plan. It saves exactly two
entries per feature, after the plan and after finish, under the key `keel/<feature>`. Without
engram it does the same work and says nothing about memory. It never calls engram's
session-lifecycle tools.

## Developing keel

```text
tests/run.sh                    # fast suites: guard, scripts, classifier, parsers (bash 3.2, BSD tools)
tests/run.sh --slow             # adds real Maven + PIT (needs a JDK and Maven)
tests/run.sh --scenarios        # skill and agent checks: real `claude -p --plugin-dir plugin` sessions (model cost)
tests/run.sh --eval             # `claude plugin eval` smoke case
tests/mutation-self-check.sh    # sed mutants of keel's critical scripts must fail their suites
claude plugin validate plugin/
```

- The design, contracts and decisions live in `specs/001-spec-to-commit-flow/` (spec, plan,
  research, data model, contracts, tasks).
- Trial runs are recorded in `tests/trials/RESULTS.md`.
- The repository's own working rules are in `CLAUDE.md`.

## Licenses

keel is MIT-licensed. Vendored material keeps its upstream license; see `NOTICE` and
`plugin/vendor/PROVENANCE.md`.
