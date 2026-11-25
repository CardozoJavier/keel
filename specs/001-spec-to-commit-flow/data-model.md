# Data Model: Spec-to-Commit Feature Delivery (keel v1)

keel has no database. Its "data" is:
- markers in Spec Kit artifacts;
- git history;
- untracked run scratch, written only by keel's scripts.

This file defines each one and how run state is derived from them.

## 1. Feature run (derived, never stored)

**Fields**:
- `feature`: `NNN-short-name`, from `--feature`, `.specify/feature.json` or the branch name.
- `step`: the next step to run, from §2.
- `path`: `full` or `light`, from the spec's Path line.
- `base`: the first available of:
  1. the ledger;
  2. the spec's `**Base**` line;
  3. `git merge-base HEAD <default-branch>`;
  4. the empty tree (unborn repo).
- `branch`: equals `feature`.

**Steps** (in order): `constitution`, `specify`, `clarify`, `plan`, `plan-review`, `tasks`,
`analyze`, `implement`, `mutate`, `review`, `finish`, `done`. Plus the terminal `halted(<reason>)`,
reported and never prompted.

- The light path removes `plan-review`. `plan` then writes a single-design decision without
  Gate 2.
- `plan` and `plan-review` are both served by the `plan` skill.

## 2. State derivation (latest-first)

`keel-state next` computes two candidates and returns the **earlier** of them:
- **Progress candidate**: evaluate the evidence rows **from finish (the top row) downward**. The
  first row whose evidence holds is the furthest row, and the candidate is the step after it. If
  no row holds, the candidate is `constitution`.
- **Gate candidate**: the first missing **gate prerequisite**, in this order:
  1. constitution;
  2. Gate 1 (clarify row);
  3. plan-review GO (full path), or the plan row (light path).
  Gates are hard prerequisites: holding a later row can't skip a missing gate. For example, a
  hand-made `tasks.md` without a plan-review GO still sends the run to `plan-review`.
- Rows below the furthest one are then checked for drift.
- Once the finish evidence holds, the result is `done`, whatever else is true.

| Row | Evidence (holds when…) | Next step if this is the furthest row |
|---|---|---|
| finish | `spec.md` has `**Status**: Implemented (YYYY-MM-DD)` **in HEAD's tree** | `done` |
| review | the ledger has the step-completion row `review done <sha>` (written after the last `REV-n` commit, or after a review with no fixes), and `<sha>` is HEAD or an ancestor of HEAD whose later commits all carry `FIN-n` IDs. Unit closures (`ok <sha> REV-n`) never count. Without a ledger, review re-runs | `finish` |
| mutate | `test-quality.md` is in HEAD's tree with `**Result**: resolved` or `**Result**: not-run (<reason>)` | `review` |
| implement | every `T###` in `tasks.md` (HEAD's tree) is `[X]`, and each has a matching task commit (§3) | `mutate` |
| analyze | `tasks.md` **in HEAD's tree** has the header line `**Analyzed**: YYYY-MM-DD (baseline <n> failing; build <maven\|host\|none>; tests <present\|none>; setup <T###\|none>)`. Analyze's last action is: checks pass, then `keel-verify --label baseline`, then it writes that line plus the `keel:baseline` comment (§3), then the docs commit. Evidence lives in a file, so it doesn't depend on subject style, survives `[X]` edits, and works when `tasks.md` was committed earlier | `implement` |
| tasks | `specs/NNN-*/tasks.md` exists with ≥ 1 `T###` line (working tree) | `analyze` |
| plan-review | `plan.md` `## Plan Review` whose last `### Round N` has `**Verdict**: GO` or `**Verdict**: GO (developer decision)`; or Path is `light` and the plan row holds | `tasks` |
| plan | `plan.md` has `## Design Decision` with a `**Chosen**:` line **and** the header line `**Plan status**: complete` (Phase 0/1 artifacts written) | `plan-review` (full) or `tasks` (light) |
| clarify (Gate 1) | `spec.md` has `**Status**:` `Approved (Gate 1, …)` or `Implemented (…)` | `plan` |
| specify | `specs/NNN-*/spec.md` exists | `clarify` |
| constitution | `.specify/memory/constitution.md` exists with no `[ALL_CAPS]` placeholders | `specify` |

**Notes**:
- Before the docs commit, Gate 1, Gate 2 and plan-review evidence live in working-tree files.
  `keel-branch` exempts the feature's own spec directory and keel-written constitution, so resume
  works from uncommitted documents.
- After the docs commit, everything is in git, so state survives losing `.git/keel/`.
- **Analyze's evidence is the committed `**Analyzed**` line**, which analyze writes and commits
  itself. If its checks passed but the baseline verify halted, a resume re-runs analyze. That is
  idempotent and cheap. `implement`'s preflight only confirms the line is in HEAD and the tree is
  clean.
- **Losing `.git/keel/`**:
  - Before the docs commit: the branch-name exemption still covers `specs/<feature>/**`, and the
    run resumes.
  - After it: `baseline.failing` and `baseline.cmd` are restored from `tasks.md`'s
    `keel:baseline` comment, and `baseline.ran` becomes "unknown". With `ran` unknown, the
    missing-report clause is skipped, including at finish, and `NEW` counts only failures not in
    the baseline failing set.
- **Review with no findings and a lost ledger re-runs review.** Also idempotent: the cost is
  tokens, never correctness.
- **Halted plan review**: a NO_GO escalation that the developer resolves is recorded as
  `**Verdict**: GO (developer decision)` with their words. This is the only way a halted plan
  review turns into GO without a reviewer.

**Drift rules** (checked for rows below the furthest one; any hit gives
`halted(drift: <detail>)` with exit 4):
- A `[X]` task with no matching commit.
- A task commit whose task is unchecked.
- A ledger row that contradicts git. Git wins, and a `DRIFT:` note is printed.
- A step marker present while a lower row's evidence is missing, e.g. a Design Decision without
  Gate 1.

**`keel-state require <step>`**:
- Exits 0 when every gate prerequisite before `<step>` holds and `next` would not return an earlier
  step. `require clarify` passes when the spec exists but is unapproved, because approving it is
  clarify's job.
- Otherwise exits 3 and prints the first missing evidence.
- Exits 5 when a functional guard self-check fails (contracts/push-guard.md §Self-check): the keel
  hook is listed and enabled, every push URL is rewritten, there is no foreign `pushInsteadOf` and
  no `pushurl`, and `git` resolves into the shims.

## 3. Artifact markers (in Spec Kit files)

### spec.md header lines (keel adds Path; Status values extend Spec Kit's)

```markdown
**Status**: Draft | Approved (Gate 1, 2026-11-25) | Implemented (2026-11-30)
**Path**: full | light (accepted at Gate 1)      ← written at Gate 1 for both paths, in the same edit as Status
**Base**: <sha> (<branch the feature was created from>)
```

`Base` is written by `specify` from `keel-branch`'s output. It keeps the base derivable
if the ledger is lost. If the feature was created from another feature branch (stacked), the final
report says so.

An `Approved` Status with no `Path` line is drift (`halted(drift: …)`), never silently `full`,
which would ask Gate 2 on a light run.

`.specify/feature.json` has exactly Spec Kit's format, `{"feature_directory": "specs/<NNN-name>"}`,
so the vendored `common.sh` and `check-prerequisites.sh` read it unchanged. It is a local pointer
only. It is **never committed** (always exempt from the
dirty check), so switching between interleaved feature branches isn't blocked. Without it,
resolution falls back to the branch name.

**`## Change Classification`** is required in keel specs (FR-028):

```markdown
## Change Classification
| Criterion | Answer | Reason |
|---|---|---|
| Touches an external contract (API, webhook, schema)? | no | … |
| Changes persisted data or its structure? | no | … |
| Easy to reverse? | yes | … |
**Qualifies as small**: yes | no: <reason>
```

`light` may be written only when the answers are clearly "no", "no", "yes" **and** the developer
accepts it at Gate 1.

### plan.md

```markdown
**Plan status**: draft | complete          ← header line; complete once Phase 0/1 artifacts exist

## Design Decision
**Chosen**: <name> (Gate 2, YYYY-MM-DD) | single design (light path)
<summary>
### Rejected designs
| Design | What it offered | Why rejected |

## Plan Review
### Round 1 (YYYY-MM-DD)
**Verdict**: GO | NO_GO | GO (developer decision)
<reviewer output, verbatim>
**Dispositions**: <blocker>: resolved | rejected (<reason>) | deferred (<reason>)
```

### tasks.md

- Spec Kit's format, unchanged: `- [ ] T001 [P] [US1] Description with path`. keel marks `- [X]`.
- Header lines added by analyze, which SC-006 at M4 checks Spec Kit tolerates:

  ```markdown
  **Analyzed**: 2026-11-26 (baseline 2 failing; build maven; tests present; setup none)
  <!-- keel:baseline
  cmd: ./mvnw verify
  failing: com.x.FooTest#should_a
  failing: com.x.BarTest#should_b
  -->
  ```

- **Escaping in the `keel:baseline` comment**: every `-` in a value is written as `%2D` and `%` as
  `%25`, and decoded on read, so a test ID can't end the comment early.
- **Test setup task**: when no test command is detected, `tasks` itself adds a non-behavior task
  that sets one up, before the first behavior task. Analyze records it as `setup T###`. If none
  exists, analyze reports CRITICAL, as a backstop.
- **Behavior tasks** name both the production path and the test path, e.g. `T012 [US1] Add
  RefundPolicy.limit in src/main/java/…/RefundPolicy.java (test:
  src/test/java/…/RefundPolicyTest.java)`. `analyze` flags a behavior task without a test path.
- **Non-behavior tasks**: setup, config, docs.

### Commit subjects

Commits follow the host's style, and each carries the keel ID so that state is derivable.

| Commit | Subject must contain |
|---|---|
| docs (end of analyze) | anything in the host's style. Staging: `specs/<NNN>/**` (including `checklists/`) plus a keel-written constitution. Identified through the `**Analyzed**` line (§2) |
| work unit (`T###`, `MUT-n`, `REV-n`, `FIN-n`) | the unit ID |
| test-quality | `test-quality` |
| finish | `NNN` |

**Portable matching**:
- The pattern is `(^|[^A-Za-z0-9])<ID>([^A-Za-z0-9-]|$)` under `LC_ALL=C`, with no `\b`, e.g.
  `T[0-9]{3}` or `REV-[0-9]+`.
- It searches `git log --format=%s <base>..HEAD`.
- Example in Conventional Commits style: `feat(payment): T003 add refund limit`.

## 4. Run scratch (`$(git rev-parse --git-dir)/keel/<NNN-feature>/`, never tracked)

```text
ledger.tsv              # ts<TAB>step<TAB>status<TAB>ref<TAB>detail (append-only)
briefs/<unit>.md        # keel-brief (unit = T###, MUT-n, REV-n, FIN-n, FINISH)
reports/<unit>.md       # implementer report (stored by the orchestrator via keel-put)
reviews/<unit>-r<n>.md  # task-reviewer output per round (keel-put)
evidence/<unit>/NN-<phase>.log, evidence/<unit>/index.tsv   # keel-evidence
verify/<label>.log, verify/<label>.failing              # keel-verify (baseline, units, test-quality, finish)
diffs/<unit>.patch      # keel-diff --unit (T###, MUT-n, REV-n, FIN-n)
partial/<unit>.patch    # saved partial work of an interrupted unit (§5)
review/diff.patch, review/files.txt, review/findings-<lens>.md
plan-review/round-<n>.md
mut/<module>/pit/mutations.xml, mut/mutants.tsv, mut/changed-lines.tsv,
mut/classification.tsv, mut/run.log   (triage decisions are committed: specs/<NNN>/test-quality.triage.tsv)
```

**Ledger statuses**:
- Units: `started`, `ok`, `halted`, `abandoned`.
- Steps: `done`.
- Other: `drift`.
- `ref` is the BASE sha for task rows and the HEAD sha for review rows.

## 5. Work units and interrupted-unit recovery (SC-005)

**Work units**:
- Every implementer dispatch is a work unit with an ID, a BASE and named paths.
- IDs:
  - `T###` for tasks;
  - `MUT-<n>` for mutation gap-resolution rounds;
  - `REV-<n>` for review-fix rounds;
  - `FIN-<n>` for finish fixes and finish re-mutation rounds;
  - `FINISH` for the finish edit. Its matching commit is the one that makes HEAD's `spec.md` say
    `Implemented`. On `done`, `run` repeats the idempotent `mem_save` and the final report.
- A unit starts on a clean tree (apart from the exemption list), so BASE = HEAD.
- Every unit ends in its own commit, whose subject contains the unit ID. Nothing uncommitted
  carries over between units or rounds.
- **Numbering**: `n` is 1 plus the highest `n` for that prefix in the `<base>..HEAD` subjects and
  in the ledger. Round caps (3 for mutate, 3 for review, 3 for finish) are counted from commits, so
  a resume neither resets them nor reuses an ID.
- **Named paths**, recorded at start, which make attribution possible even before the first
  `keel-evidence` run:
  - `T###`: the task's paths.
  - `MUT-n`: the affected modules' `src/test/**` and the triage file.
  - `REV-n` and `FIN-n`: the files of their findings or failing tests, plus the affected
    modules' `src/test/**`.
  - `FINISH`: `spec.md` and `test-quality.md`.
- **Restart keeps the ID**: a recovered unit restarts under the same ID. The numbering rule applies
  only to new units.
- Ledger rows:
  - `<step> started <BASE> <unit> <intent> <paths>` when the unit starts. `intent` is `n/a` (tasks),
    `fix`, `refactor` or `gap` (MUT-n and FIN gap units) (§7);
  - `ok <sha> <unit>`, `halted <ref> <unit> <reason>` or `abandoned <ref> <unit>` to close it.
- Test runs go through `keel-evidence`, which records working-tree ids.

**Order**: `run` calls `recover`, then `keel-branch ensure`, then `recover` again if the first call
returned `RECOVERED=deferred`.

**Matching commit**: a commit in `BASE..HEAD` whose subject contains the unit ID (portable
boundary, §3).

**Cases for a unit whose last row is `started`**:
- **Clean tree, HEAD past BASE, matching commit**: append `ok`, return `RECOVERED=closed:<unit>`.
  This covers an interruption between the commit and the ledger write.
- **Clean tree, HEAD past BASE, no matching commit**: append `abandoned`, return
  `RECOVERED=none`. The unit restarts.
- **Clean tree, HEAD equal to BASE**: append `abandoned`, return `RECOVERED=none`.
- **Not on the feature branch**: return `RECOVERED=deferred`. `run` calls `keel-branch ensure`, then
  `recover` again.
- **Dirty tree, HEAD equal to BASE, on the feature branch**: try to recover (below).
- **Dirty tree, HEAD past BASE**: `HALT=unattributed-changes`.
- **No open unit (or no ledger) and a dirty tree**: `recover` reports `RECOVERED=none` and touches
  nothing. `keel-branch ensure`, which runs next, halts on anything outside the ensure-scope
  exemptions. This keeps an uncommitted spec or plan before the docs commit resumable.

**After a halt**: halts append `halted` to the unit, and `recover` never acts on a halted unit.
Changes the developer made after a halt are theirs. To continue, the developer either:
- commits them (with the unit ID; for a task, also `[X]` in `tasks.md`) and resumes;
- or discards them and resumes, and the unit restarts.

**Attribution**: recovery happens only if **every** changed or untracked path relative to HEAD
(outside the exemption list) is one of these:
- a named path of the unit;
- a path in the diff between BASE's tree and some `keel-evidence` tree recorded for the unit;
- the unit's own `[X]` line in `tasks.md`.

All comparisons are tree-to-tree: BASE's tree against a temp-index `write-tree` of the working tree
(tracked and untracked, ignored files excluded). Nothing compares against the real index.

**Recovery**:
1. Save the tree-to-tree diff to `partial/<unit>.patch` (`git diff --binary <BASE-tree>
   <worktree-tree>`).
2. Restore tracked changed paths with `git restore --source=HEAD --worktree --staged -- <paths
   present in HEAD>`.
3. For the unit's new paths, i.e. those absent from HEAD: remove them from the index
   (`git rm --cached -q --ignore-unmatch -- <path>`, which also covers paths staged by an
   interrupted `git add`), then delete them from the working tree.
4. Restart the unit with a fresh implementer.

**Reporting**: the patch path goes in the final report.

**Otherwise**: if any changed path can't be attributed to the unit, it may be the developer's
work. `recover` halts with `HALT=unattributed-changes` and touches nothing.

## 6. Records

- **Design option**: name, lens (`smallest`, `clean`, `pragmatic`), summary, trade-offs, chosen
  flag. These are rows in `## Design Decision`.
- **Review verdict**:
  - Plan: round, verdict, blockers and dispositions.
  - Code: findings (contracts/agent-handoffs.md) in `review/findings-<lens>.md`, with a summary in
    the final report.
- **Implementer report**: status, files changed, evidence references, concerns.
- **Evidence entry**: seq, phase, exit, ts, tree, cmd (contracts/run-state.md, `keel-evidence`).
- **Verify record**: label, result, failing set, and new failures vs. the baseline.
- **Mutation result**: one TSV row per mutant: `key class method line mutator status in_scope
  killing succeeding` (contracts/mutation-runner.md).
- **Triage entry**: `key reason`.
- **Test-quality summary**: `test-quality.md`.
- **Memory entry** (engram, optional):
  - `topic_key: keel/<NNN-feature>`, type `decision`.
  - After Gate 2 (or after the light-path plan): the chosen and rejected designs and key
    constraints.
  - After finish: the outcome, branch and commit range.
- **Provenance record**: a row in `plugin/vendor/PROVENANCE.md`. In-place edits are logged in
  `plugin/vendor/CHANGELOG.md`.

## 7. Validation rules (from requirements)

- **Per-unit evidence rule** (`keel-evidence check` and the orchestrator):

  | Unit | Allowed changes | Evidence |
  |---|---|---|
  | `T###` behavior | the task's paths | `check` (RED before GREEN) + `keel-verify` |
  | `T###` non-behavior | the task's paths | `keel-verify` |
  | `MUT-n`, and `FIN-n` opened for mutation gaps | test paths and the triage file only; `keel-diff --kind <unit>` must return `non-behavior` before the commit, otherwise halt | before the commit: `keel-verify` + `task-reviewer`. After the commit: the computed kill (each targeted key turns KILLED on the re-run); no `check` |
  | `REV-n` / `FIN-n` with `intent=fix` (correctness finding or failing verify) | finding paths and their tests | `check`. For a `FIN-n` on a failing verify, RED may be the already-failing test, recorded through `keel-evidence`. Plus `keel-verify` |
  | `REV-n` / `FIN-n` with `intent=refactor` (simplicity, conventions or Minor finding) | finding paths | no RED. Before the commit: `task-reviewer` with `**Behavior unchanged**: yes` (a `no` re-opens the unit as `intent=fix`), then `keel-verify`. Afterwards, finish's re-mutation covers the lines |
  | `FINISH` | `spec.md` Status line, `test-quality.md` re-mutation section | the full `keel-verify --label finish` |

  **`intent` precedence**: the orchestrator sets `intent` from the verified findings. It is never
  the implementer's choice.
  - `fix`: any correctness-lens finding, any Critical finding (wrong behavior by definition), or a
    failing verify.
  - A round with any `fix` finding is `fix` as a whole.
  - `refactor`: everything else.
  - A `fix` unit whose `keel-diff --kind` is `non-behavior` (e.g. it corrects a test) needs only
    `task-reviewer` and `keel-verify`.
  - Exit-11 debug units are `MUT-n` in mutate (test paths only, `intent=fix`) and `FIN-n` in finish
    (`intent=fix`).
  - REV and FIN units always get `task-reviewer` before `keel-verify` and the commit.
- **Gates and order**:
  - `plan` requires Gate 1 evidence (FR-006).
  - `implement` requires plan-review GO, or the light path (FR-010, FR-028).
- **Every commit** is preceded in the same step by a passing `keel-verify` whose output was shown
  (FR-020, SC-003, Constitution V). Each unit commit also meets the per-unit evidence rule above
  (FR-014, SC-004, which counts behavior tasks).
- **Mutation**:
  - Every in-scope coverage and assertion gap is killed by a test or triaged before the
    test-quality commit (FR-032).
  - Production changes made after the test-quality commit (review and finish fixes) are
    re-mutated in finish before the finish commit (SC-012).
- **Build files**: no change to `pom.xml`, `mvnw*`, `.mvn/` or other build files, except changes
  the feature itself requires through a task (FR-034, SC-014).
