# Quickstart: keel v1 (maintainer use, FR-029)

## Install (local marketplace at the repo root; the plugin root is `plugin/`)

```text
claude plugin marketplace add ~/dev/projects/keel     # once
cd <repo> && claude plugin install keel@keel --scope local   # per repository
/reload-plugins            # picks up edits to the keel repo
```

Install keel with `--scope local`, once per repository. The plugin and its push guard are then
active only in that repository, and only for you. Don't install it at user scope: its hooks would
run in every session.

`defaultEnabled: false` was dropped, because `claude plugin eval` can't enable such a plugin in
its sandbox (research R7). A local-scope install gives the same isolation.

After enabling keel, **start a new session**. The push guard's git-level and PATH layers are set
up at session start, and `/reload-plugins` alone leaves only the static layer active. keel runs
refuse to start in that state.

## Enable per repository; disable what keel replaces; allow keel's commands

Put this in `<repo>/.claude/settings.local.json`:

```json
{
  "enabledPlugins": {
    "keel@keel": true,
    "superpowers@claude-plugins-official": false,
    "feature-dev@claude-plugins-official": false
  },
  "permissions": {
    "allow": [
      "Bash(keel-state:*)", "Bash(keel-branch:*)", "Bash(keel-ledger:*)", "Bash(keel-put:*)",
      "Bash(keel-brief:*)", "Bash(keel-diff:*)", "Bash(keel-evidence:*)", "Bash(keel-verify:*)",
      "Bash(keel-mutate:*)", "Bash(keel-classify:*)",
      "Bash(git add:*)", "Bash(git commit:*)", "Bash(git switch:*)", "Bash(git status:*)",
      "Bash(git diff:*)", "Bash(git log:*)", "Bash(git restore:*)", "Bash(git rev-parse:*)",
      "Bash(git ls-files:*)", "Bash(git symbolic-ref:*)",
      "Bash(mvn:*)", "Bash(./mvnw:*)"
    ]
  }
}
```

- **Permission mode**: run keel sessions in `acceptEdits` or auto mode. Under that setup, the only
  prompts in a run are Gate 1, Gate 2 and clarification questions (SC-001).
- **engram, optional**: its own protocol (session summaries, proactive saves) is unaffected by
  keel. To keep a run's memory down to keel's one entry per feature, disable the engram skill in
  this repository.
- **What keel reuses**: an existing `.specify/memory/constitution.md` and the `specs/NNN-*`
  numbering. Spec Kit's CLI and `speckit-*` skills aren't needed.
- **Before the first run**:
  - Commit or ignore pending files. keel refuses to start on a dirty tree, so it never mixes your
    work into a feature. In PayConductor today that means `.specify/`, `CLAUDE.md` and the
    `pom.xml` Lombok bump.
  - `.claude/settings.local.json` must be git-ignored. On this machine it is, through
    `~/.config/git/ignore`.

## Run a feature

```text
/keel:run "Add idempotency keys to the refund command"
```

1. Answer the clarification questions.
2. **Gate 1**: approve the spec, and accept the light path here if it's offered.
3. **Gate 2**: pick a design. The light path has no Gate 2.

After that, keel runs without prompts and ends with local commits on `NNN-short-name`. The
final report lists:
- commits;
- test quality;
- review;
- any halt, with the step to resume.

keel never pushes. Run `git push` in your own terminal.

## Resume

```text
/keel:run                 # the feature in .specify/feature.json
/keel:run 003             # a specific feature
```

A feature written with plain Spec Kit isn't taken over in v1. Start it as a keel feature
instead.

## Run one step

```text
/keel:specify   /keel:clarify   /keel:plan     /keel:tasks    /keel:analyze
/keel:implement /keel:mutate    /keel:review   /keel:finish
```

Each step refuses to run before its prerequisites exist, or when the push shim is inactive.

## Standalone (no feature run needed)

```text
/keel:debug "OrderServiceTest fails on the refund path"
/keel:verify
/keel:respond-review <review comments or a path>
/keel:test-audit payment-service      # report: .git/keel/audit/<ts>/report.md
```

## Mutation analysis prerequisites (Java/Maven)

- **Build tools**: a JDK and Maven (or `./mvnw`) that already build the project.
- **Tests**: JUnit 5 / JUnit Platform. JUnit 4-only or TestNG-only modules get "not run" with the
  reason.
- **First-run downloads**, fetched through your Maven into `~/.m2`:
  - `pitest-maven:1.30.2`;
  - `pitest-junit5-plugin:1.2.3`;
  - the matching `junit-platform-launcher`;
  - `maven-dependency-plugin:3.8.1` and `maven-help-plugin:3.5.1`.
- **Scope**:
  - It runs per module with `-f <module>/pom.xml` and warns when sibling SNAPSHOTs come from
    `~/.m2`, because they may be stale. `-pl -am` is under evaluation (M5).
  - Only unit tests and changed lines are analyzed.
  - Build files are never edited.

## If the guard gets in the way

- **A legitimate command is blocked**: run it in your own terminal, then report the case so it can
  be added to the allow corpus.
- **A guard defect blocks work**: `claude --settings '{"disableAllHooks": true}'` starts a session
  without keel's hooks or shims. Use it only to fix keel.

## Develop keel itself

```text
tests/run.sh                  # fast suites: guard (shims + hook), scripts, classifier, parsers
tests/run.sh --slow           # adds the Maven fixture (JDK + Maven; first run downloads PIT)
tests/mutation-self-check.sh  # sed mutants of critical scripts must fail the suites
claude plugin validate plugin/
claude plugin eval plugin --eval-dir tests/eval --no-publish --allow-tools Bash
```

## Verified environment facts

| Fact | Status |
|---|---|
| Plugin `bin/` on the Bash PATH | appended (verified 2026-11-25) |
| SessionStart `CLAUDE_ENV_FILE` PATH prepend | works; the shim intercepted zsh `gp` and `eval` (verified 2026-11-25) |
| `CLAUDE_PLUGIN_ROOT` in the Bash env | absent (verified 2026-11-25); keel exports `KEEL_ROOT` |
| Session env in subagents and skill-injected commands | yes, both (verified 2026-11-25, research R7.2) |
| User `!` commands get the session env | _TBD (item 1, interactive trial T058)_ |
| `skills:` preload in plugin agents | _TBD (item 2)_ |
| Allow rules inside plugin subagents | _TBD (item 6)_ |
