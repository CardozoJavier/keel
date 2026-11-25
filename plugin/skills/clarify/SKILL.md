---
name: clarify
description: Resolve the remaining ambiguities in a keel spec (up to 5 targeted questions, one at a time), then hold Gate 1. It presents the spec and its change classification for explicit approval, and on approval records Status and Path in one edit. Used by /keel:run, or on its own.
argument-hint: "--feature NNN-name"
---

<!-- Adapted from speckit 0.8.4.dev0 commands/clarify.md (MIT): no extension hooks; ends with keel's
     Gate 1 (FR-006) and the light-path acceptance (FR-028). -->

# keel: clarify

`<feature>` is the feature name, `NNN-short-name` (e.g. `001-refund-limit`). Take it from the
`--feature` argument; otherwise run `keel-state next` and use its `FEATURE=` value. Never pass a
placeholder literally.

## 0. Preconditions

Run `keel-state require clarify --feature <feature>`. On a non-zero exit, stop and report its line.

## 1. Ambiguity scan

Read `specs/<feature>/spec.md`. Check it against Spec Kit's taxonomy:
- functional scope and behavior;
- domain and data model;
- interaction flows;
- non-functional qualities: performance, reliability, security, observability;
- integrations and external dependencies;
- edge cases and failure handling;
- constraints and tradeoffs;
- terminology;
- completion signals;
- every `[NEEDS CLARIFICATION]` marker.

## 2. Ask (at most 5 questions, one at a time)

- Ask only questions whose answers change the spec materially: architecture, data, tasks, tests,
  UX, compliance.
- For each question, give 2–4 concrete options plus your recommended answer and why. Accept a
  short reply such as "B" or "yes".
- After each answer:
  - update the spec where it belongs (requirements, scenarios, edge cases, assumptions);
  - add the question and answer under `## Clarifications` → `### Session <date>`;
  - remove the marker it resolves.
- When nothing material is open, ask nothing. Questions are inputs, not gates.

## 3. Gate 1: approval (FR-006)

1. **Present a short summary**:
   - the user stories with priorities;
   - the number of FRs and success criteria;
   - key assumptions;
   - the Change Classification table with its verdict.
2. **Ask for explicit approval.**
   - **Light path**: offer it **only** when `**Qualifies as small**: yes`, meaning the answers are
     no, no and yes. Phrase it as: "approve, approve with the light path (one gate, no competing
     designs or plan review), or tell me what to change".
   - **A change that touches a contract or persisted data never gets the light path** (SC-010).
   - **If keel proposed the constitution** (no host instructions existed), say that approving the
     spec also accepts it.
3. **Stop the turn and wait.**

When the developer answers:
- **Changes requested**: edit the spec, then present Gate 1 again.
- **Approved**: make **one edit** to the header:
  - Replace `**Status**: Draft` with `**Status**: Approved (Gate 1, <YYYY-MM-DD>)`.
  - Directly below it, insert `**Path**: full` or `**Path**: light (accepted at Gate 1)`.
  - Write both lines in the same edit: a Status without a Path is drift.
- Then return to the run loop. The next step is `plan`.
