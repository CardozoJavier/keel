---
name: specify
description: Write a keel feature specification (specs/NNN-name/spec.md, Spec Kit format) from a plain-language description. It first recalls related past decisions when memory is available, and asks about intent, goals, non-goals, anti-goals and missing requirements one question at a time. Used by /keel:run, or on its own.
argument-hint: "--feature NNN-name <feature description>"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Write, Edit, Bash(keel-ledger:*), Bash(git rev-parse:*), Bash(git log:*)
---

<!-- Adapted from speckit 0.8.4.dev0 commands/specify.md (MIT): no extension hooks; no
     create-new-feature script (keel-branch has already made the branch, locally, before any
     write); intent/goals/anti-goals questioning (FR-005); keel's Base line and Change
     Classification (FR-028); engram recall (FR-004). -->

# keel: specify

`<feature>` is the feature name, `NNN-short-name` (e.g. `001-refund-limit`). Take it from the
`--feature` argument; otherwise run `keel-state next` and use its `FEATURE=` value. Never pass a
placeholder literally.

## 0. Preconditions

1. Run `keel-state require specify --feature <feature>`. On a non-zero exit, stop and report its line.
2. You need the feature description. If it is missing, ask for it. That is an input, not a gate.

## 1. Recall (optional, FR-004)

- **If engram's `mem_search` tool is available**: search for decisions related to the description
  (2–3 short queries on its key nouns). Read only what is relevant.
- **If it isn't available, or fails**: skip silently. Never call `mem_session_*` tools.

## 2. Understand before writing (FR-005)

Cover this ground:
1. Intent and why.
2. Goals.
3. Non-goals.
4. Anti-goals: what would make the feature a failure even if it technically works.
5. Missing requirements: who uses it, the main flows, the edge cases.

How to ask:
- **One question at a time**, each specific to this feature. Build each question on the previous
  answer, or on what you found in the code.
- Don't ask what the description, the repository or recalled decisions already answer. When the
  request already gives these answers, ask nothing.
- At most 5 questions. For anything still open after that, write a reasonable default into the
  spec's Assumptions.

## 3. Write `specs/<feature>/spec.md`

1. Copy `$KEEL_ROOT/vendor/speckit/templates/spec-template.md` and fill every mandatory section,
   keeping the heading order. Spec Kit's quality rules apply:
   - User stories have priorities (P1, P2, …), and each can be tested on its own, with
     Given/When/Then acceptance scenarios.
   - Functional requirements are numbered (`**FR-001**`), testable and unambiguous.
   - Success criteria are measurable and technology-agnostic.
   - It covers edge cases and assumptions.
   - No implementation details (languages, frameworks, APIs) unless they are the feature's scope.
   - At most 3 `[NEEDS CLARIFICATION: …]` markers, and only for questions that really change
     scope.
2. **Header**:
   - `**Status**: Draft`.
   - `**Base**: <sha> (<branch the feature was created from>)`. Take the sha from
     `keel-state next --feature <feature>` (`BASE=`) and the branch from the ledger's branch row. This line
     is what makes this a keel feature.
   - **Delete the template's `**Path**` placeholder line**. `clarify` writes Path at Gate 1.
3. **Cite recalled decisions** that shaped the spec, under Assumptions.
4. **`## Change Classification`** (FR-028): answer the three criteria with reasons:
   - touches an external contract (API, webhook, schema, message format)?
   - changes persisted data or its structure?
   - easy to reverse?

   Then write `**Qualifies as small**: yes` only when the answers are clearly **no, no, yes**.
   Otherwise write `**Qualifies as small**: no: <reason>`.
5. **Checklist**: write `specs/<feature>/checklists/requirements.md`, Spec Kit's spec-quality checklist.
   Check each item honestly, fix the spec until it passes (at most 3 iterations), and record what
   remains in its Notes.

## 4. Record and hand back

1. Run `keel-ledger append <feature> files done - specs/<feature>`, so `keel-branch` treats the directory as
   keel's own.
2. Return to the run loop, or tell the developer the next step is `/keel:clarify`.
3. Don't ask for approval here. Gate 1 belongs to `clarify`.
