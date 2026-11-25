---
name: respond-review
description: Handle code review feedback with technical rigor - verify every comment against the code before acting, push back with reasons when it is wrong, apply what is right one item at a time with tests. Use on review comments from a person or a tool ("/keel:respond-review <comments or file>"); keel's review step applies the same rules to its reviewers' findings.
argument-hint: "<review comments, or a path to them>"
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(keel-state:*), Bash(keel-verify:*), Bash(mvn:*), Bash(./mvnw:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*)
---

<!-- Adapted from superpowers 7.0.2 skills/receiving-code-review/SKILL.md (MIT). Changes: the
     GitHub thread-reply section removed (keel never publishes); "human partner" wording
     replaced; every comment ends verified-and-applied or answered-with-a-reason; fixes follow
     tdd/verify. Logged in vendor/CHANGELOG.md. -->

# keel: respond-review

Verify before implementing. Technical correctness wins over social comfort.

## 0. Preconditions

Run `keel-state guard`. On a non-zero exit, stop and report it.

## The pattern, for every comment

1. **Read** all the feedback before reacting.
2. **Understand** each item: restate the requirement in your own words. If any item is unclear,
   **stop**. Implement nothing yet and ask about the unclear items. Items are often related, and
   partial understanding leads to the wrong fix.
3. **Verify** each item against the code, not against the comment:
   - read the lines it cites;
   - check that the problem actually exists;
   - for a suggested API or behavior, check that it works on this stack and version.
4. **Evaluate**: is it technically right for **this** codebase? Will it break existing behavior?
   Is there a reason for the current code (compatibility, a host rule, an approved design)? Does
   the reviewer have the full context?
5. **Respond** with a technical acknowledgement or a reasoned push-back.
6. **Implement** one item at a time:
   - order: blocking issues first (breaks, security), then simple fixes, then complex ones;
   - change behavior test-first (the `tdd` discipline);
   - run the tests after each fix and show the output (the `verify` discipline).

## YAGNI check

When a comment asks to "implement it properly" (metrics, options, abstractions), search the code
for real usage first. If nothing uses it, propose removing it instead.

## When to push back

Push back when a suggestion:
- breaks existing behavior;
- is wrong for this stack;
- violates YAGNI;
- conflicts with the host's CLAUDE.md rules or the approved design;
- misses context the reviewer didn't have.

Give the technical reason, and cite the code or test that shows it. If the conflict is
architectural, raise it with the developer instead of deciding alone.

## Tone

- No performative agreement or gratitude ("You're absolutely right!", "Great point!", "Thanks!").
- **Correct feedback**: state the fix: "Fixed: `<what changed>` in `<file:line>`."
- **Your push-back turned out wrong**: say so in one line ("Checked: it does X; fixing.") and move
  on.
- **You can't verify it**: say what you'd need to verify it.

## Outcome

Every comment ends in exactly one of these states:
- **applied**: the fix, the test that pins it, and the verify output;
- **declined**: the technical reason, with evidence;
- **needs input**: the specific question.

List all of them at the end. keel never pushes or replies on a forge. Your reply goes to the
developer, and the commits stay local.
