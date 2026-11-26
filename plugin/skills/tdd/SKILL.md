---
name: tdd
description: keel's test-driven development discipline for implementer agents. Write the test first, watch it fail for the right reason through keel-evidence, write the smallest change to pass, then refactor green. Preloaded into keel's implementer.
user-invocable: false
---

<!-- Adapted from superpowers 7.0.2 skills/test-driven-development/SKILL.md (MIT), with
     writing-good-tests.md condensed in. Changes: every run goes through keel-evidence (recorded
     RED/GREEN trees); Java/JUnit 5 examples replace TypeScript; the compile-failure RED rule for
     Java; "ask your human partner" exits become report statuses (BLOCKED,
     DONE_WITH_CONCERNS). Logged in vendor/CHANGELOG.md. -->

# Test-driven development (keel)

Write the test first. Watch it fail. Write the smallest code that passes. If you didn't watch the
test fail, you don't know whether it tests the right thing.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote production code before the test? Delete it and start over. Don't keep it as a reference,
and don't adapt it while you write the test. keel checks this mechanically: `keel-evidence`
records the working tree of every run, and `keel-evidence check` fails a unit whose RED run already
contained a production change.

## Every run goes through keel-evidence

Your brief names the feature (`<f>`), the unit (`<u>`) and the test command. Never run tests or
builds directly.

```bash
keel-evidence run <f> <u> red      -- mvn -q test -Dtest='PriceTest#should_*'
keel-evidence run <f> <u> green    -- mvn -q test -Dtest='PriceTest#should_*'
keel-evidence run <f> <u> refactor -- mvn -q test
```

In a multi-module build, add `-pl <module> -am -Dsurefire.failIfNoSpecifiedTests=false`. Use the
host's build tool and wrapper (`./mvnw`) when the brief or the host's CLAUDE.md names one.

## Red, green, refactor

### 1. RED: write one failing test

One behavior, a name that states it (the host's convention, e.g. `should_<expected>_when_<condition>`),
and real code (no mocks unless a dependency is slow or external).

```java
@Test
void should_reject_refund_when_amount_exceeds_capture() {
    Payment payment = Payment.captured(new Money(100_00, EUR));

    assertThrows(RefundExceedsCaptureException.class,
            () -> payment.refund(new Money(120_00, EUR)));
}
```

Bad: `void refundWorks()` asserting `verify(mockLedger).append(any())`. It has a vague name and
tests the mock, not the code.

### 2. Verify RED: watch it fail for the right reason. Mandatory.

Run it with `keel-evidence run <f> <u> red -- <test command>` **before touching any production
file**. Then read the output:

- **It fails on an assertion or the expected exception**: this is the right reason. Continue.
- **It passes**: you're testing existing behavior. Change the test.
- **It fails to compile**: in Java this is a valid RED **only** when the compiler error names
  exactly the type or member this task introduces (`cannot find symbol: method refund(Money)`).
  - Any other compile error (a typo, an import, a signature you didn't intend) is the wrong
    reason. Fix the test and run RED again.
  - Don't add a production stub to get an assertion failure. A stub is a production change before
    RED, and the evidence check rejects it.
- **It errors for an unrelated reason** (setup, fixture, environment): fix that and run RED again.
  Several red entries are fine; the check uses the last valid one.

### 3. GREEN: the smallest change

Write the simplest production code that makes this test pass. Add no options, parameters or
abstractions the test doesn't need (YAGNI), and don't "improve" neighboring code.

### 4. Verify GREEN. Mandatory.

1. Run `keel-evidence run <f> <u> green -- <same test command>`. It must pass.
2. **Then run the module's whole test suite** through `keel-evidence run <f> <u> green -- <module
   test command>`. A green run of your one test isn't a green suite.
3. Every failure that run shows goes in your report **by name**, including ones you think you
   didn't cause. A red test you saw and didn't report makes the report false.

If your test fails, fix the code, not the test.

### 5. REFACTOR: only after green

Remove duplication, improve names, extract helpers. Add no behavior. Then run
`keel-evidence run <f> <u> refactor -- <module test command>`. **The last recorded run must pass.**

Then go back to step 1 for the next behavior the task needs.

## Writing good tests

- **Name the break first.** Before writing the test body, name the production change that would
  make the test fail. If you can't, redesign the test around an observable behavior.
- **Derive expectations independently.** Use literals and hand-checked values. An expected value
  computed by the code under test, or by its helpers, passes whatever the code does.
- **No change detectors.** Don't assert a constant's value, exact message wording or private
  structure. Assert the behavior that depends on them.
- **Test your code, not the framework.** Test the contract at your code's boundary: the value
  returned, the event emitted, the row written. Don't test that Spring wires a bean or that a
  `@KafkaListener` is invoked.
- **The mock earns no assertions.** An assertion on a mock proves only that the mock exists.
  Assert the real component's behavior. Mock only what is slow or external, after you've learned
  its side effects.
- **Make doubles specific.** When arguments, counts or order are part of the contract, assert
  them. Give each branch (success, error, malformed) its own fixture.
- **No test-only code in production classes.** Put helpers in test sources.
- **Edge cases and errors**: cover every edge case and error path the spec names in your task's
  scope.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Too simple to test" | Simple code breaks. The test takes a minute. |
| "I'll test after" | A test written after passes immediately and proves nothing. |
| "I already checked it by hand" | There's no record, and it can't be re-run. keel requires the recorded RED. |
| "Keep it as a reference" | You'll adapt it, and that's testing after. Delete it. |
| "A stub makes RED cleaner" | A stub is a production change before RED. Use the compile-failure rule. |
| "The test is hard to write" | Hard to test means hard to use. Simplify the interface. |
| "Existing code has no tests" | Add tests for the code you touch. |

## Red flags: stop and start over

- Production code before the test.
- A test that passes on its first run.
- You can't explain why the RED run failed.
- "Just this once", or "this case is different".

## When you're stuck

Don't guess and don't widen the task. Report it:
- **`BLOCKED`**: you can't write a meaningful failing test with what the brief gives you.
- **`NEEDS_CONTEXT`**: a requirement is ambiguous.
- **`DONE_WITH_CONCERNS`**: the design makes the test awkward. Say why.

For a failure you don't understand, follow the `debug` skill: root cause first, and stop after 3
failed fixes.

## Checklist before you report DONE

- [ ] Every new behavior has a test that I watched fail for the right reason (a recorded red run).
- [ ] I wrote the smallest code that passes.
- [ ] The module's whole suite passed in the last recorded run, and every failure is named in the
      report.
- [ ] The tests assert real behavior, not mocks, with independently derived expectations.
