---
name: debug
description: Systematic debugging - root cause before any fix, in four phases (investigate, compare patterns, test one hypothesis, fix with a failing test), stopping after 3 failed fixes to question the design. Use for any bug, test failure, build failure or unexpected behavior, inside a keel run or on its own ("/keel:debug <symptom>").
argument-hint: "<symptom, failing test or error>"
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(keel-state:*), Bash(keel-evidence:*), Bash(keel-verify:*), Bash(mvn:*), Bash(./mvnw:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*)
---

<!-- Adapted from superpowers 7.0.2 skills/systematic-debugging/SKILL.md (MIT). Changes: the
     superpowers skill handoffs and "human partner" wording removed; the 3-failed-fixes stop
     becomes a reported halt (FR-016) inside keel runs; test runs go through keel-evidence inside
     a unit; Java/Maven evidence examples. Logged in vendor/CHANGELOG.md. -->

# keel: debug

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

A symptom fix is a failure. Finish each phase before starting the next.

## 0. Preconditions

- **Standalone**: run `keel-state guard` and stop if it fails. Run tests and builds with the
  host's commands, and show their output.
- **Inside a keel unit** (an implementer brief): run every test and build through `keel-evidence
  run <f> <u> …` or `keel-verify`, never directly.

## Phase 1: Root cause investigation

1. **Read the error completely.** Read the whole stack trace and the first `Caused by:`, and note
   file:line and error codes.
   - For surefire, read `target/surefire-reports/<Test>.txt`, not only the console.
2. **Reproduce it consistently.** Get the exact command and inputs. If you can't trigger it
   reliably, gather more data. Don't guess.
3. **Check recent changes.** Use `git diff`, `git log -p -- <path>`, dependency or config changes,
   and environment differences.
4. **Multi-component systems** (HTTP → service → DB, producer → Kafka → consumer): add temporary
   instrumentation at each boundary, showing what enters and leaves and the config each layer
   sees. Run it once, find **where** it breaks, then investigate that component. Never log card
   data, credentials or other secrets. Mask them.
5. **Trace the data flow backwards** from the bad value to where it originates, and fix it at the
   source.

## Phase 2: Pattern analysis

1. Find similar code in the same codebase that works.
2. If you're applying a pattern, read the reference implementation completely.
3. List every difference between the working and the broken code, however small.
4. Name the dependencies, config and assumptions the broken code relies on.

## Phase 3: One hypothesis at a time

1. State it: "X is the root cause because Y."
2. Test it with the smallest change, one variable at a time.
3. If it's confirmed, go to Phase 4. If not, form a **new** hypothesis. Don't stack fixes.
4. If you don't understand something, say so. Don't pretend.

## Phase 4: Fix

1. **Write a failing test that reproduces it first**, following the `tdd` discipline. Inside a
   unit, that's the recorded `red` run.
2. **Make one fix**, at the root cause. No "while I'm here" changes.
3. **Verify it**: the test passes, the rest of the suite still passes, and the original symptom is
   gone. Show the output.
4. **If it doesn't work, count your fixes.**
   - Fewer than 3: go back to Phase 1 with what you learned.
   - **3 failed fixes on the same problem: stop.** This points to a design problem, not a bad
     hypothesis. Signs: each fix reveals a new problem somewhere else, or the next fix needs a
     large refactor.
     - Inside a keel run: report `BLOCKED` with what you tried and what each attempt showed. The
       run halts (FR-016).
     - Standalone: present the evidence and the design question. Don't attempt fix #4.

## Red flags: back to Phase 1

- "Quick fix now, investigate later."
- "Let me just try X."
- Several changes before one test run.
- "It's probably X" without evidence.
- Proposing fixes before tracing the data flow.
- "One more attempt" after 2 failures.

## "No root cause found"

If the cause turns out to be environmental, timing-dependent or external:
- write down what you investigated;
- add handling (a retry with a bound, a timeout, a clear error);
- add the logging that would catch it next time.

Most "no root cause" cases are incomplete investigations. Be sure before you settle.

## Report

State the root cause, the evidence (commands and output), the fix, and the verification output.
Use no "should work" wording. Show the output that proves it.
