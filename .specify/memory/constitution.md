<!--
Sync Impact Report
- Version change: 1.2.0 → 1.3.0
  MINOR (spec 001 plan, Gate 2 decisions):
  - Principle I: local-only git operations are not publishing and must not be blocked; forge API
    writes that create pull requests or remote commits count as equivalents.
  - Principle II: post-implement sequence is test-quality → review → verify → commit.
  - Plugin Constraints: exceptions for the host build tool's own caches when downloading keel's
    pinned test-quality tools, and for session-state files the host agent provides to plugins
    (CLAUDE_ENV_FILE, used to put keel's push shims first on PATH); run scratch lives inside the
    repository's git directory.
- Templates: no changes needed (plan-template Constitution Check reads this file).

Previous report (1.2.0)
- Version change: 1.1.0 → 1.2.0
  MINOR: Principle V expanded: tests must be shown to catch defects through mutation analysis of
  changed code, with uncaught changes resolved or triaged (spec 001, FR-030 to FR-035).
  Plugin Constraints: network exception for keel's pinned test-quality tools.
- Templates: no changes needed; tasks-template already requires test-first tasks, and the
  mutation step runs after implementation, outside the task list.

Previous report (1.1.0)
- Version change: 1.0.0 → 1.1.0
  MINOR: Principle IV expanded with the light-path exception (spec 001, FR-028): a change accepted
  as small at spec approval has one gate instead of two. Qualifying criteria added to the principle.
- Templates: no further changes needed; plan-template's Constitution Check reads this file.

Previous report (1.0.0)
- Version change: template → 1.0.0 (initial ratification)
- Principles defined:
  I. Never Push
  II. Spec Kit Flow Is the Backbone
  III. Self-Contained, Attributed Vendoring
  IV. Human Gates Only Where Judgment Is Irreplaceable
  V. Evidence Before Claims
  VI. Optional Integrations Degrade Gracefully
  VII. Host Instructions Win
- Added sections: Plugin Constraints, Development Workflow, Governance
- Removed sections: none
- Templates:
  ✅ .specify/templates/tasks-template.md: test tasks changed from OPTIONAL to REQUIRED (Principle V)
  ✅ .specify/templates/plan-template.md: no change; Constitution Check gates derive from this file
  ✅ .specify/templates/spec-template.md: no change; no new mandatory spec sections
  ⚠ .claude/skills/speckit-tasks/SKILL.md: still says tests are optional "unless the user requests
    TDD"; Principle V is that request. Left unedited so `specify` upgrades don't conflict.
- Deferred TODOs: none
-->

# keel Constitution

## Core Principles

### I. Never Push

Every keel flow MUST end with a local commit on a feature branch, ready to push. keel MUST NOT
run any command that publishes commits or opens a pull request (`git push`, `gh pr create`,
`gh repo sync`, and equivalents, including forge API writes that create pull requests or remote
commits). This MUST be enforced by a hook that blocks the command, not by instructions alone.
Local-only git operations (commit, stash, rebase, reset, cherry-pick and the like) do not publish
and MUST NOT be blocked.

Rationale: publishing is outward-facing and hard to reverse; it stays a human action.

### II. Spec Kit Flow Is the Backbone

Feature delivery MUST follow Spec Kit's sequence (constitution → specify → clarify → plan →
tasks → analyze → implement), followed by keel's test-quality → review → verify → commit.
Artifacts MUST stay compatible with Spec Kit: the `specs/NNN-feature/` layout, its file names (`spec.md`, `plan.md`,
`research.md`, `data-model.md`, `contracts/`, `quickstart.md`, `tasks.md`) and template formats,
so a repository can return to plain Spec Kit without migration. Capabilities taken from other
tools MUST plug into a step of this flow and MUST NOT create a parallel artifact tree
(e.g. `docs/superpowers/`).

### III. Self-Contained, Attributed Vendoring

keel MUST work with only keel installed: no runtime dependency on superpowers, feature-dev or the
Spec Kit CLI. Upstream files copied verbatim or with light edits (templates, scripts) MUST live in
a single vendor area that records, per source, the upstream repository, version or commit, and
license. keel-authored skills and agents that adapt upstream content MUST name their source in a
header comment. The repository MUST ship a NOTICE file attributing Spec Kit (MIT, GitHub, Inc.),
superpowers (MIT, Jesse Vincent) and feature-dev (Apache-2.0), and modified Apache-2.0 files MUST
carry a change notice.

Rationale: one install, behavior that doesn't shift with upstream releases, and upstream updates
that stay diffable.

### IV. Human Gates Only Where Judgment Is Irreplaceable

keel MUST stop for human approval at exactly two points: approving the spec, and choosing among
competing designs during plan. The one exception is a change the developer accepts as small when
approving the spec: it has no competing designs, so spec approval is its only gate. A change
qualifies as small only if it touches no external contract, changes no persisted data or its
structure, and is easy to reverse. Clarification questions during specify and clarify are inputs to
the spec, not additional gates. All other steps MUST run without asking. Automated checks
(cross-artifact analysis, plan review, code review, verification) MUST halt the run and report
when they find a blocking issue; keel MUST NOT continue past a blocking finding on its own
judgment. When speed and correctness conflict, correctness wins.

### V. Evidence Before Claims

Implementation MUST be test-first: a failing test precedes each behavior change. Before any
commit, keel MUST run the target project's build and tests and show their output; a step is
complete only when that output shows it. Saying "done", "passing" or "fixed" without that
evidence is a violation. Tests MUST also be shown to catch defects: changed code goes through
mutation analysis, and every change the tests don't catch is either caught by a behavior-level test
or triaged with a recorded reason. Where keel can't run mutation analysis, it says so explicitly.
The same rules apply to keel's own development: scripts and hooks have automated tests, and skill
and agent behavior has scenario checks.

### VI. Optional Integrations Degrade Gracefully

Integrations outside the core flow (engram first) MUST be optional: used when present, skipped
silently when absent, and never the cause of a failed run. keel MUST NOT duplicate an
integration's own functions. For engram, keel MUST NOT call `mem_session_summary` or other
session-lifecycle tools, and MUST save per-feature memories under a stable topic key so later
saves update earlier ones. Recall (search) before specify and plan is read-only and always allowed.

### VII. Host Instructions Win

When keel runs in a target repository, the user's and the repository's instructions (global and
project CLAUDE.md, or equivalents) override keel defaults: build and test commands, branch and
commit message style, code style, and attribution rules, including not adding AI co-author
trailers where forbidden. keel defaults apply only where those instructions are silent.

## Plugin Constraints

- keel ships as a Claude Code plugin; its manifest, skills, agents and hooks follow the Claude Code
  plugin format. Beyond Claude Code, it MUST require only bash and git.
- Hooks that enforce a principle MUST fail closed: if the hook cannot decide, it blocks.
- keel MUST NOT modify files outside the target repository, except through an optional
  integration's own API, except the host build tool's own caches (e.g. `~/.m2`) when that tool
  downloads keel's pinned test-quality tools, and except files the host agent provides to plugins
  for session state (e.g. Claude Code's `CLAUDE_ENV_FILE`). keel's run scratch lives inside the
  repository's git directory (e.g. `.git/keel/`), never in system temp directories.
- The core flow MUST NOT require network access beyond what the host project's own build needs,
  except to download keel's own pinned test-quality tools (e.g. the mutation-testing tool) from the
  package repositories that build already uses.

## Development Workflow

- Every keel feature goes through the Spec Kit flow in this repository, with its artifacts under
  `specs/NNN-feature/`.
- Until keel can run its own flow, development uses the Spec Kit install in this repository; once
  it can, keel features are built with keel.
- Vendored files MUST NOT be edited in place without an entry in the vendor area's change log.
- Commits are local; pushing is the maintainer's action.

## Governance

This constitution supersedes other keel practices. An amendment requires a written change with
its rationale, a version bump under semantic versioning (MAJOR: a principle removed or redefined;
MINOR: a principle or section added or materially expanded; PATCH: wording only), and the
corresponding updates to dependent templates in the same change. Every plan's Constitution Check
MUST evaluate all seven principles; a violation MUST be justified in the plan's Complexity
Tracking table, or the plan is blocked. Runtime guidance for agents lives in `CLAUDE.md`.

**Version**: 1.3.0 | **Ratified**: 2026-11-24 | **Last Amended**: 2026-11-25
