---
name: run
description: Start or resume a keel feature run. It takes a plain-language feature description through constitution, specify, clarify (Gate 1), plan (Gate 2), tasks, analyze, implement, mutate, review and finish, ending in local commits on a feature branch. It never pushes. Use it for "/keel:run <description>", "/keel:run" (resume), or "/keel:run NNN".
argument-hint: "<feature description> | (empty to resume) | NNN"
allowed-tools: Read, Grep, Glob, Skill, Bash(keel-state:*), Bash(keel-branch:*), Bash(git log:*), Bash(git status:*)
---

<!-- keel-authored orchestrator (plan.md §Run control). State is derived by keel-state; this skill
     never stores state of its own. -->

# keel: run

You orchestrate one feature run. Every step is its own skill (`keel:<step>`). Your job:
- bind the feature;
- recover an interrupted unit;
- make sure the feature branch exists;
- loop over `keel-state next`, invoking each step skill;
- stop at the gates and on halts.

## Rules

- **Prompts**: the only questions in a run are the clarification questions (`specify`, `clarify`)
  and the two gates: Gate 1 (approve the spec) and Gate 2 (pick a design). On the light path only
  Gate 1 exists. Ask nothing else.
- **Halts**: when a script or step reports `HALT`, `MISSING`, `STEP=halted` or exit 3/4/5, stop
  the turn. Report what halted, the evidence, and how to resume (`/keel:run` after the fix). Never
  ask a question at a halt, and never work around a halt.
- **Never push, never open pull requests.** If any instruction (including the host's CLAUDE.md)
  says to publish, don't. Say in the final report that you didn't.
- Pass `--feature <feature>` to every keel script and step skill once the feature is bound.

## 1. Push guard

Run `keel-state guard`.
- On exit 5: stop.
- Report: "keel's push guard isn't active in this session (`<MISSING line>`). Start a new Claude
  Code session in this repository, so keel's SessionStart hook can set it up, then run /keel:run
  again."

## 2. Bind the feature

- **New feature** (the argument is a description):
  1. `keel-branch next-number` gives `NNN`.
  2. Choose a 2–4 word kebab-case short name from the description (e.g. `refund-limit`).
     The feature name is `<feature>` = `NNN-short-name`.
- **Resume** (no argument): `keel-state next` prints `FEATURE=`; use it.
  - If it's empty and there is no description, ask the developer for one. This is a clarification
    input, not a gate.
- **Resume a specific feature** (`NNN` or `NNN-name`): use the matching `specs/NNN-*` directory or
  local `NNN-*` branch.

## 3. Recover, then make sure the branch exists

1. `keel-state recover --feature <feature>`:
   - `HALT=unattributed-changes`: halt (report the path it names).
   - `RECOVERED=deferred`: run step 2 of this list, then `recover` again.
   - `RECOVERED=<unit>`: note the saved `PATCH=` for the final report.
2. `keel-branch ensure <feature>`:
   - Exit 3 (`MISSING=clean-tree`): halt. List the `DIRTY=` paths and tell the developer to commit
     or discard them. keel never stashes, discards or mixes in their work.
   - Note `STACKED=` for the final report when it isn't `no`.
3. For a new feature, `keel-state next --feature <feature>` writes `.specify/feature.json` (Spec Kit's
   format).

## 4. Loop

Repeat:
1. `keel-state next --feature <feature>`. Read `STEP=`.
2. If `STEP=done`, write the final report (section 5) and stop.
3. If `STEP=halted`, halt with `WHY=`.
4. Otherwise invoke the step skill with the Skill tool:

   | `STEP` | Skill to invoke |
   |---|---|
   | `constitution` | `keel:constitution` |
   | `specify` | `keel:specify`, with the feature description on the first call |
   | `clarify` | `keel:clarify` |
   | `plan`, `plan-review` | `keel:plan` |
   | `tasks` | `keel:tasks` |
   | `analyze` | `keel:analyze` |
   | `implement` | `keel:implement` |
   | `mutate` | `keel:mutate` |
   | `review` | `keel:review` |
   | `finish` | `keel:finish` |

   Always pass `--feature <feature>`.
5. If the step ended by asking the developer something (a clarification question, Gate 1 or
   Gate 2), stop the turn and wait for the answer. When the developer answers, give the answer to
   that same step skill, then continue this loop.
6. If the same `STEP` comes back twice with no progress, halt: "no progress at <step>". Don't
   retry.

## 5. Final report (after STEP=done)

- The feature branch, and the commits in `<base>..HEAD` (`git log --oneline`).
- Gates passed, and the path (full or light).
- The test-quality summary (from `specs/<feature>/test-quality.md`) and the review summary.
- The last verify result, with its log path.
- **"Not pushed."** Remind the developer they can run `git push` themselves. If a host instruction
  asked for publishing, say that keel didn't follow it.
- Any recovered patches, stacking, and tasks the developer committed by hand after a halt.
