---
name: plan
description: Plan an approved keel feature. On the full path it explores the code with parallel agents, gets 2–3 competing designs (smallest change, clean architecture, pragmatic balance), holds Gate 2, writes plan.md (with Design Decision) and the Phase 0/1 artifacts, then runs fresh plan reviews until GO. On the light path it writes a single-design plan. Re-entry never repeats Gate 2.
argument-hint: "--feature NNN-name"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Write, Edit, Agent, Bash(keel-put:*)
---

<!-- Adapted from speckit 0.8.4.dev0 commands/plan.md (MIT): no extension hooks; no setup-plan
     script and no CLAUDE.md marker edits; adds explorers and competing architects (feature-dev),
     Gate 2 with a recorded Design Decision (FR-007..FR-009), the fresh-reviewer loop with
     3-round escalation (FR-010) and keyed engram saves (FR-025). -->

# keel: plan

`<feature>` is the feature name, `NNN-short-name` (e.g. `001-refund-limit`). Take it from the
`--feature` argument; otherwise run `keel-state next` and use its `FEATURE=` value. Never pass a
placeholder literally.

## 0. Preconditions and re-entry

1. Run `keel-state require plan --feature <feature>`. On a non-zero exit, stop and report its line.
2. Read `specs/<feature>/spec.md`. Its `**Path**` line is `full` or `light`.
3. **Re-entry**: if `specs/<feature>/plan.md` already has `## Design Decision` with a `**Chosen**:` line,
   Gate 2 is done. **Skip steps 1–3, never run the explorers or architects again, and never ask
   for a design choice again.**
   - If `**Plan status**: complete` is already set, go to step 5.
   - Otherwise, go to step 4.

## Light path (Path: light)

1. Write `specs/<feature>/plan.md` from `$KEEL_ROOT/vendor/speckit/templates/plan-template.md`:
   - `## Design Decision` with `**Chosen**: single design (light path)` and the design in a few
     lines;
   - Technical Context;
   - Constitution Check;
   - Project Structure.
2. Phase 0/1 artifacts are optional on the light path. Write them only if they're needed.
3. Set `**Plan status**: complete`.
4. Save the decision to memory (step 6), then return to the run loop. No Gate 2 and no plan
   review.

## 1. Recall (optional)

If engram's `mem_search` is available, search for decisions related to this feature, and cite
the relevant ones in the plan. Skip silently if it's unavailable.

## 2. Explore (FR-007)

Always dispatch the explorers, **even when the codebase looks small**. FR-007 requires
independent explorations, and an explorer finishes quickly on a small repository. Reading the code
yourself does not replace them; that comes after they report.

1. Dispatch 2–3 `keel:explorer` agents **in parallel**, each with the spec path and one focus
   area:
   - the code the feature changes;
   - conventions and patterns, including CLAUDE.md;
   - tests and build.
2. Read the essential files they name.

## 3. Designs and Gate 2 (FR-008, FR-009)

1. Dispatch `keel:architect` agents **in parallel**, one per lens: `smallest change`,
   `clean architecture`, `pragmatic balance`. Give each the spec path, the explorers' findings and
   its lens. Use two lenses when only two are meaningfully different.
2. Present the designs side by side: what each changes, trade-offs, risks, and its
   contract/data/reversibility answers.
3. **Recommend one, with reasons.**
4. **Gate 2**: ask the developer to pick a design, or to describe their own. Then stop the turn and
   wait.
5. When the developer answers, **immediately** write `specs/<feature>/plan.md` from the plan template,
   with the header line `**Plan status**: draft` and a filled `## Design Decision`:
   - `**Chosen**: <name> (Gate 2, <YYYY-MM-DD>)`, plus a summary.
   - `### Rejected designs`: a table of what each offered and why it was rejected.
   - If the developer rejected all the proposals, record their design as chosen, with its
     trade-offs against the proposals.

## 4. Plan artifacts (Spec Kit Phase 0 and 1)

1. Fill the plan:
   - Technical Context;
   - Constitution Check, evaluating **every** principle in `.specify/memory/constitution.md`;
   - Project Structure (real paths);
   - Complexity Tracking, which justifies any violation, or the plan is blocked.
2. Write `research.md`: decision, rationale and alternatives for each unknown.
3. Write `data-model.md`, `contracts/` and `quickstart.md` as the feature needs.
4. Set `**Plan status**: complete`.

## 5. Plan review (FR-010; full path only)

1. **Dispatch a fresh `keel:plan-reviewer`**. Never reuse one. Give it the paths to the spec, the
   plan, the Phase 1 artifacts and the constitution. From round 2 on, also give it every earlier
   round's verbatim output and a disposition log (resolved, rejected or deferred, each with a
   one-line reason).
2. **Store the output** with
   `keel-put <feature> plan-review/round-<N>.md <<'EOF' … EOF`.
3. **Append it to `plan.md`** under `## Plan Review`, using the format in
   `$KEEL_ROOT/templates/plan-review.md`: `### Round <N> (<date>)`, `**Verdict**: GO|NO_GO`, the
   reviewer's output verbatim, then `**Dispositions**`.
4. **On NO_GO**: revise the plan and artifacts for each blocker, record each disposition, and go
   back to step 1 of this section.
5. **On the third round with the same blocker**: escalate. Present the blocker and ask the
   developer to decide. This is the only extra contact FR-010 allows. Record their decision as a
   new round with `**Verdict**: GO (developer decision)`, quoting their words.
6. **Never continue past an open NO_GO.**

## 6. Save the decision (optional, FR-025)

- **If engram's `mem_save` is available**: save one memory with `topic_key: keel/<feature>` and
  `type: decision`. It holds the chosen and rejected designs and key constraints.
  - If the response says `judgment_required`, resolve each candidate without asking, using
    `related` or `compatible`, and note any conflict in the final report.
- **If it isn't available, or fails**: skip silently. Never call `mem_session_*` tools.

## 7. Hand back

Return to the run loop. The next step is `tasks`.
