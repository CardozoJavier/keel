---
name: verify
description: Evidence before claims. Run the host's full build and tests (detected, or from CLAUDE.md), show the output, and only then state the result. Use before claiming anything is done, fixed or passing, and before any commit; inside a keel run or on its own ("/keel:verify").
argument-hint: "[--feature NNN-name --label <label>]"
allowed-tools: Read, Grep, Glob, Bash(keel-state:*), Bash(keel-verify:*), Bash(mvn:*), Bash(./mvnw:*)
---

<!-- Adapted from superpowers 7.0.2 skills/verification-before-completion/SKILL.md (MIT).
     Changes: the gate runs keel-verify detect / keel-verify run (host command wins, VII); PR and
     push wording removed (keel never publishes); a keel-run mode with labels. Logged in
     vendor/CHANGELOG.md. -->

# keel: verify

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this turn, you can't claim it passes.

## 0. Preconditions

Run `keel-state guard`. On a non-zero exit, stop and report it.

## The gate

1. **Identify the command that proves the claim.**
   - If the host's CLAUDE.md defines a build-and-test command, use that one.
   - Otherwise run `keel-verify detect` and use its `TESTCMD=`.
   - If it prints `BUILD=undetected`: stop. Ask the developer to define build and test commands
     in CLAUDE.md.
   - If it prints `BUILD=none`: say "nothing to build or test", show the output, and claim nothing
     more.
2. **Run it, fresh and complete.**
   - **Inside a keel run** (`--feature f --label L`): run
     `keel-verify run <f> --label <L> -- <command>`. Read `RESULT=`, `FAILING=`, `NEW=` and
     `LOG=`.
   - **Standalone**: run the command itself.
3. **Read all the output**: the exit code, the reactor summary, failures and errors, and any
   `TESTS=none` or `BUILD=none`.
4. **Show the developer the evidence**: the summary lines and the tail of the log, including the
   failing test names.
5. **Only then state the result, quoting the evidence.**
   - On failure, state the real status, for example "3 failing: …". Never soften it.
   - Inside a keel run, a failure goes to the `debug` path. A run can't move on while it's red.

## Claims and what proves them

| Claim | Requires | Not enough |
|---|---|---|
| Tests pass | test output with 0 failures, from this turn | an earlier run, "should pass" |
| Build succeeds | the build command exits 0 | a clean IDE, a compile of one module |
| Bug fixed | the original symptom's test passes, and the RED of that test was seen | "the code changed" |
| Regression test works | red, then green, recorded | one passing run |
| Agent finished | the diff shows the change, and verify passes | the agent's report |
| Requirements met | each FR checked against the code and tests | "tests pass" |

## Red flags: stop and run the command

- "Should", "probably", "seems to".
- Expressing satisfaction ("Done!", "Perfect!") before the output is shown.
- Trusting a subagent's success report without the diff and a verify.
- A partial run (one module, one test class) used as evidence for the whole.
- "Just this once."

keel never pushes or publishes, whatever the result. Verification evidence is for the local commit
and the report.
