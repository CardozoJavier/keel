---
name: constitution
description: Create or update the repository's keel/Spec Kit constitution (.specify/memory/constitution.md) from the host's existing instructions (CLAUDE.md and similar), referring to them rather than copying them. Runs once per repository, or when those instructions change.
argument-hint: "[--feature NNN-name]"
---

<!-- Adapted from speckit 0.8.4.dev0 commands/constitution.md (MIT): keel derives principles from
     host instructions (FR-002) and refers to them; no extension hooks; no interactive principle
     prompts (proposals are accepted at Gate 1). -->

# keel: constitution

`<feature>` is the feature name, `NNN-short-name` (e.g. `001-refund-limit`). Take it from the
`--feature` argument; otherwise run `keel-state next` and use its `FEATURE=` value. Never pass a
placeholder literally.

## 0. Preconditions

- **Inside a run** (a `--feature` was given): run `keel-state require constitution --feature <feature>`.
  On a non-zero exit, stop and report its `MISSING=` or `WHY=` line.
- **Standalone**: run `keel-state guard`. On a non-zero exit, stop and report it.

## 1. Gather the host's instructions

Read every instruction file that exists:
- `CLAUDE.md` and `.claude/CLAUDE.md` at the repository root;
- `AGENTS.md`;
- `~/.claude/CLAUDE.md`, the user's global instructions (they apply to every repository);
- any existing `.specify/memory/constitution.md`.

From these, extract the durable principles: non-negotiable rules about correctness, data, security,
testing, architecture boundaries, and commit and attribution rules. Leave out one-off commands.

## 2. Decide

- **The constitution exists with no `[ALL_CAPS]` placeholders, and the host instructions add no
  principle it lacks**: nothing to do. Report "constitution up to date" and stop.
- **There are no host instructions at all**: propose 4–6 principles suited to the repository's
  language and build (test-first, verification before claims, and so on). Mark the file
  "proposed by keel; accepted at Gate 1". The developer accepts it together with the spec at
  Gate 1. Don't ask a separate question.

## 3. Write `.specify/memory/constitution.md`

1. Start from `$KEEL_ROOT/vendor/speckit/templates/constitution-template.md`, or update the
   existing file. Keep its heading structure.
2. Write each principle as a short name, a declarative rule (MUST or SHOULD) and, where useful, a
   one-line rationale.
3. **Refer, don't copy.** Name the source of each principle ("see CLAUDE.md, Principles"). Don't
   paste whole sections.
4. **Governance**: the host's instructions win over keel defaults. Amendments use semantic
   versioning.
5. **Versioning**: a new file is version 1.0.0. An update bumps MINOR when a principle is added or
   expanded, and PATCH for wording. Prepend a short Sync Impact Report as an HTML comment.
6. No `[ALL_CAPS]` placeholders may remain. Dates are ISO `YYYY-MM-DD`.

## 4. Record and hand back

- **Inside a run**: run `keel-ledger append <feature> files done - .specify/memory/constitution.md`. That
  ledger row lets `keel-branch` treat the file as keel's own. Then return to the run loop.
- **Standalone on the default branch**: leave the file uncommitted. Tell the developer to commit it
  (keel never commits on the default branch, FR-013). Inside a run, the file is committed with the
  docs commit at the end of `analyze`.
