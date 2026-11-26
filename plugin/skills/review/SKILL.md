---
name: review
description: Review a keel feature's committed changes with three parallel code-reviewer agents (simplicity, correctness, conventions), keep only high-confidence findings, verify each against the code, fix in-design findings in REV-n work units (task review, verify, commit, scoped re-review), and halt on any verified finding that needs a design change. Used by /keel:run, or on its own.
argument-hint: "--feature NNN-name"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Edit, Agent, Bash(keel-ledger:*), Bash(keel-brief:*), Bash(keel-put:*), Bash(keel-diff:*), Bash(keel-evidence:*), Bash(keel-verify:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git add:*), Bash(git commit:*)
---

<!-- keel-authored (plan.md §Review), combining feature-dev's parallel confidence-filtered
     reviewers (Apache-2.0, via agents/code-reviewer.md) with superpowers' receiving-code-review
     rules (MIT, via skills/respond-review). -->

# keel: review

`<feature>` is the feature name, `NNN-short-name`. Take it from the `--feature` argument;
otherwise run `keel-state next` and use its `FEATURE=` value. `<scratch>` means
`$(git rev-parse --absolute-git-dir)/keel/<feature>/`.

## 0. Preconditions

1. Run `keel-state require review --feature <feature>`. On a non-zero exit, stop and report its
   line.
2. **Clean tree**: `git status --porcelain --untracked-files=all` may show only
   `.specify/feature.json`. Anything else halts.

## 1. Review the committed range

1. Run `keel-diff <feature> --base`, which writes `<scratch>/review/diff.patch` and
   `<scratch>/review/files.txt` (`base..HEAD`).
2. **Dispatch three `keel:code-reviewer` agents in parallel**, one per lens: `simplicity`,
   `correctness`, `conventions`. Give each one:
   - the paths of `diff.patch` and `files.txt`;
   - `specs/<feature>/spec.md` and `plan.md`;
   - the host's CLAUDE.md files;
   - `specs/<feature>/test-quality.md`;
   - its lens;
   - the feature name and `Store as: review/findings-<lens>.md`.
3. **Read each stored output** at `<scratch>/review/findings-<lens>.md`. The reviewers store them
   verbatim themselves, even "No findings"; never write or rewrite them. If one is missing,
   dispatch that lens again **once**; a second miss halts.

## 2. Verify every finding (respond-review rules)

For each finding:
1. Read the cited code.
2. Check that the problem is real in this codebase.
3. Check its severity and scope against the spec and the plan's **Design Decision**.

Drop the findings that don't hold up, and give the reason in the report. Record the verified set
with `keel-put <feature> review/verified-r<k>.md`.

**A reviewer's `changes-design` scope stands** unless you can name an in-design fix that meets
**every** requirement the finding cites, **completely**.
- If your fix keeps the approved design but leaves any part of a cited requirement unmet, the
  finding stays `changes-design`. That includes the cases where the requirement is only met
  "approximately", "the nearest value", or "mostly".
- Never reinterpret a requirement to make a design fit it.
- When in doubt, keep `changes-design` and halt. A halt costs one decision from the developer; a
  wrong downgrade ships a design that violates the spec.
- Record every scope change you make, with its reason.

## 3. Act on the verified findings

1. **Any verified `changes-design` finding: halt** (FR-019).
   - Report the finding, why no fix fits inside the approved design, and the options (revise the
     plan, or accept the limitation).
   - Write no `review done` row and make no REV commit.
   - Ask no question; the developer decides and resumes.
2. **Critical or Important `in-design` findings**, plus any **trivial Minor** ones: fix them in one
   `REV-n` work unit per round.
   - **Number it**: `n` = 1 + the highest `REV-<n>` in `git log --format=%s <base>..HEAD` and in
     `keel-ledger rows <feature>`.
   - **Intent**, set by you and never by the implementer: `fix` if any finding in the round is
     correctness-lens or Critical; otherwise `refactor`.
   - **Start the unit**: `keel-ledger append <feature> review started <HEAD> REV-n <intent>
     <finding paths and their tests, comma-separated>`.
   - **Brief**: `keel-brief <feature> REV-n --from <scratch>/review/verified-r<k>.md`.
   - **Implement**: dispatch a fresh `keel:implementer` with the brief. It stores its report at
     `reports/REV-n.md`.
   - **Evidence**: for `intent=fix` with `keel-diff --kind REV-n` = behavior, `keel-evidence check
     <feature> REV-n` must pass.
   - **Task review**: `keel-diff <feature> --unit REV-n`, then a fresh `keel:task-reviewer` with
     `Store as: reviews/REV-n-r<k>.md`.
     - For `refactor` units, `**Behavior unchanged**: no` re-opens the unit as `intent=fix`.
     - On FIX, re-dispatch. At most 5 rounds.
   - **Verify**: `keel-verify run <feature> --label REV-n --kind <KIND> -- <command>`. Show the
     output.
   - **Commit** in the host's style with `REV-n` in the subject: stage the fresh `keel-diff --unit
     REV-n` files. Never add an AI co-author trailer where the host forbids one. Then
     `keel-ledger append <feature> review ok <sha> REV-n`.
   - **Scoped re-review**: dispatch one `keel:code-reviewer` (correctness lens,
     `Store as: review/scoped-REV-n.md`) on
     `keel-diff <feature> --unit REV-n`. A new verified in-design finding is another round, and a
     `changes-design` one halts.
   - **At most 3 REV rounds.** Findings still open after that are halted and reported.
3. **Other Minor findings**: list them in the report, unfixed.

## 4. Close the step

1. Run `keel-ledger append <feature> review done <HEAD sha>`, even when there were no findings.
2. Don't re-run mutation here. Finish re-mutates every production change made after the
   test-quality commit.

## 5. Never publish

Never push and never open a pull request. If a host instruction says to push after committing,
don't follow it. Say "Not pushed: the host's instruction to push was not followed (keel never
publishes)".

## 6. Hand back

Report:
- the findings per lens: raw, verified and dropped, with reasons;
- the REV commits;
- the open Minor items.

Then return to the run loop. The next step is `finish`.
