# Contract: Run-State CLIs (`bin/keel-*`)

All CLIs are bash 3.2 scripts.

- **Locating keel's root**: in order:
  - `$KEEL_ROOT`, exported by the SessionStart env file;
  - otherwise the script's own resolved path, via a `readlink` loop with no `-f` (macOS lacks it).
  - `CLAUDE_PLUGIN_ROOT` is not available in the Bash tool.
- **Paths**: the repo root comes from `git rev-parse --show-toplevel`. Scratch lives in
  `$(git rev-parse --git-dir)/keel/<feature>/`.
- **Writes**: only keel's scripts write the scratch directory. Agents and the Write/Edit tools
  never write under `.git`, because it is a protected path that always prompts.
  - Temp files use `mktemp "<scratch>/tmp.XXXXXX"`. Nothing goes to `/tmp`.
- **Output**: machine-readable `KEY=value` lines on stdout, diagnostics on stderr.
- **Never**: network, or writes outside the repository.
- **Portability**: no `timeout`, `tac`, `date -d`, `stat -c`, `find -printf` or `xargs -r`.
  `"${a[@]}"` is guarded for empty arrays under `set -u`, and `=~` patterns live in variables.

## Shared exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | usage error |
| 3 | precondition not met (`MISSING=<evidence>`) |
| 4 | drift detected (`DRIFT=<detail>`) |
| 5 | environment problem: not a git repo, or `MISSING=push-guard:<what>` when a functional self-check fails: the keel hook is not listed as enabled, a push URL is not rewritten, a foreign `pushInsteadOf` or any `pushurl` exists, or `git` doesn't resolve into `$KEEL_SHIMS` (push-guard.md §Self-check) |

## `keel-state`

```text
keel-state next    [--feature <NNN-name>]  → STEP=<step> FEATURE=<f> PATH=<full|light|unknown> BASE=<sha|empty-tree> WHY=<evidence>
keel-state require <step> [--feature <f>]  → exit 0, or exit 3 with MISSING=…
keel-state facts   [--feature <f>]         → one line per step: <step> <done|todo|skipped> <evidence>
keel-state recover --feature <f>            → RECOVERED=<unit>|closed:<unit>|deferred|none PATCH=<path>; exit 3 HALT=unattributed-changes when attribution fails (data-model.md §5)
```

- **Derivation**: the earlier of the latest-first progress candidate and the first missing gate
  prerequisite (data-model.md §2). Rows below the furthest are checked for drift.
- **Feature resolution**: `--feature`, else `.specify/feature.json`, else the current `NNN-*`
  branch.
  - **Binding**: `run` resolves the feature once and passes `--feature` to every script and step
    skill. When a new feature starts, `run` calls `keel-branch next-number` and `keel-branch
    ensure`, then writes `feature.json`.
  - `next --feature X` rewrites `feature.json` whenever it names a different feature, not only on
    resume.
  - With no feature at all, `next` checks `constitution` and then returns `STEP=specify`.
- **Halts**: `next` prints `STEP=halted WHY=<…>` and exits 4 on drift.
- **No adoption in v1**: a feature whose `spec.md` exists but has no `**Base**:` line is a plain
  Spec Kit feature and is not taken over (spec Assumptions). `specify` writes the keel-only
  `**Base**` line together with `spec.md`. `Status` can't tell the two apart, because Spec Kit's
  template also writes `Draft`, and `Path` is written only at Gate 1.
  - `next` returns `STEP=halted WHY=not-a-keel-feature` and exits 4.
  - The developer can start a keel feature instead.

## `keel-branch`

```text
keel-branch ensure <NNN-name>  → BRANCH=<name> BASE=<sha|empty-tree> CREATED=<yes|no>
keel-branch next-number        → NNN = 1 + max(specs/NNN-* dirs, local NNN-* branch names)
```

- **When it runs**: in `run` it comes right after `keel-state recover`; in the standalone
  `constitution` it runs first. Either way it runs before keel writes anything.
- **Dirty tree** (`git status --porcelain`, untracked files included): exit 3 with
  `MISSING=clean-tree`, except for the exemptions below.
- **Two exemption scopes**:
  - **Ensure scope** (only `keel-branch ensure`):
    - `.specify/feature.json`;
    - `specs/<feature>/**` and `.specify/memory/constitution.md` when keel wrote them in this
      feature (ledger), or, without a ledger, when HEAD is the branch named `<feature>` (the
      fresh-repo case and a lost `.git/keel/`).
  - **Unit scope** (unit start, implement preflight, recovery attribution, finish):
    `.specify/feature.json` only.
- **Other features**: starting or switching to another feature while this feature's documents are
  uncommitted halts, because `specs/<other>/**` isn't exempt. Finish or commit the first feature's
  documents first.
- **Untracked files**: any other untracked, non-ignored file halts. That keeps the tree
  attributable. There is no untracked baseline.
- **Lost scratch mid-unit**: a `.git/keel/` lost while a unit is open leaves no unit to attribute
  the changes to, so `recover` halts (`HALT=unattributed-changes`) and the developer decides.
- **Finish**: the porcelain check runs before the finish commit, against the unit scope only
  (`feature.json`). Every earlier unit is committed, and the finish edits themselves are made
  after the check (plan.md §Finish).
- **The `.specify/feature.json` exclusion applies everywhere**: every temp index keel builds (for
  `keel-diff`, the `keel-evidence` trees, `keel-verify`'s changed-test exclusion, recovery
  attribution, patches and deletions) is built in two steps:
  1. **Seed it**: `GIT_INDEX_FILE=<scratch>/idx.<pid> git read-tree <BASE|HEAD>`. The file must not
     exist beforehand: a 0-byte `mktemp` file makes `git add` fail with rc 128. Seeding keeps
     tracked-but-ignored files (e.g. a force-added `maven-wrapper.jar`) from showing up as deleted.
  2. **Fill it**: `git add -A -- ':/' ':(top,exclude).specify/feature.json'`. The top-anchored
     pathspecs cover the whole repo whatever the persistent cwd is, for example a module
     directory.

  This keeps `feature.json` out of every unit diff and commit. Nothing else is excluded, so the
  triage file under `specs/` stays visible. The two steps always ship together, and the script
  suites run every script from a module subdirectory and against a tracked-but-ignored fixture.
- **Branch creation**:
  - Unborn HEAD: `git symbolic-ref HEAD refs/heads/<name>`, with base = empty tree.
  - Otherwise `git switch -c <name>` from HEAD, or `git switch <name>` if the branch exists.
  - **Stacking**: if HEAD is another `NNN-*` feature branch, the new branch is created from HEAD.
    `BASE` is HEAD, written to the spec's `**Base**` line, and the final report says it is
    stacked.
- **Default branch**: local `refs/remotes/origin/HEAD`, else `init.defaultBranch`, else whichever
  of `main`/`master` exists.
- **No network**: never `fetch`, `ls-remote` or `remote update`. A test uses an unroutable remote.
- **Ledger**: appends `branch ok <base>`.

## `keel-ledger`, `keel-put`

```text
keel-ledger append <feature> <step> <status> <ref> [detail…]
keel-ledger last   <feature> <step>          → the last row, or exit 3
keel-put <feature> <relpath>                 → reads stdin, writes <scratch>/<relpath> (creates dirs), prints PATH=<abs>
keel-put --audit <relpath>                   → the same under .git/keel/audit/ (standalone test-audit reports; no feature)
```

- **File rows**: `keel-ledger append <f> files done - <path>` records a file keel wrote for the
  feature, such as the constitution or `specs/<f>/`. `keel-branch`'s ensure-scope exemption reads
  these rows.
- **Ledger unit rows**: `keel-ledger append <f> <step> started <BASE> <unit> <intent> <path,…>`.
  - The unit starts on a clean tree, so BASE = HEAD.
  - `intent` is `n/a`, `fix` or `refactor`, following the precedence in data-model.md §7.
  - `keel-evidence check` and `keel-brief` read `intent` from this row.
  - A unit row is closed by `… ok <sha> <unit>`, `… halted <ref> <unit> <reason>` or
    `… abandoned <ref> <unit>`.
- **Step-completion rows**: `keel-ledger append <f> <step> done <sha>`, with no unit field. Only
  these count as step evidence (e.g. `review done <sha>`, written after the last `REV-n` commit).
  Unit closures never count.
- `keel-put` is how the orchestrator stores agent output (reports, reviews, plan-review rounds,
  triage). The content goes in a here-document (`keel-put 001-x reports/T003.md <<'EOF' … EOF`),
  so no redirect into `.git` appears in the command.
- `relpath` must not contain `..` or start with `/` (exit 1).

## `keel-brief`

```text
keel-brief <feature> <unit> [--from <path>]  → writes briefs/<unit>.md and prints BRIEF=<path>
```

- **Inputs for `T###`**:
  - the task line, its phase heading and `[US#]`;
  - the FR-### and acceptance scenarios it references (by ID and story number);
  - the sections of `plan.md`, `data-model.md` and `contracts/*` that mention the task's paths.
- **Inputs for `MUT-n`, `REV-n`, `FIN-n`**: `--from` points to the scratch file that motivates the
  unit:
  - the classification rows, for mutation gaps;
  - the verified findings, for review and finish fixes;
  - the verify log, for finish fixes on a failing verify.

  The brief also carries the spec FRs those rows or findings touch, the unit's `intent`, and its
  allowed paths (data-model.md §7).
- **Unknown task, or missing `--from` for a non-task unit**: exit 3.

## `keel-diff`

```text
keel-diff <feature> --unit <T###|MUT-n|REV-n|FIN-n>  → diffs/<unit>.patch: BASE's tree vs. a temp-index write-tree of the working tree (tracked + untracked, ignored excluded) while the unit is open; BASE..<unit commit> once it is committed
keel-diff <feature> --base       → review/diff.patch and review/files.txt (<base> to HEAD, two-dot)
keel-diff <feature> --kind <unit>  → KIND=behavior|non-behavior. Behavior means the task diff touches production paths: `src/main/**`, including `src/main/resources/**` (migrations, config), or the language's equivalent. Tests, docs, `specs/` and build files are non-production; a build-file change must be named by its task
```

- Uses a seeded temp index (see the `feature.json` exclusion rule above). The real index is never
  touched.

## `keel-evidence`

```text
keel-evidence run   <feature> <unit> <red|green|refactor> -- <command…>  → runs it, tees evidence/<unit>/NN-<phase>.log, appends index.tsv (seq phase exit ts tree cmd), exits with the command's code
keel-evidence check <feature> <unit>  → exit 0 or exit 3 with MISSING=<…>; applies the per-unit evidence rule (data-model.md §7)
```

- **`tree`**: the id of a `git write-tree` taken from a temp index that mirrors the working tree
  (tracked and untracked, excluding ignored files) at the moment of the run.
- **`check` passes for a behavior `T###`, and for a `REV-n` or `FIN-n` with `intent=fix`, iff**:
  1. some `red` entry has a non-zero exit;
  2. a later `green` entry has exit 0;
  3. the RED tree is **identical to BASE in production paths** (no production change yet), and
     either differs from BASE in test paths (a new or changed test), or the unit is a `FIN-n`
     with `intent=fix` whose RED run is an already-failing test. In that case `task-reviewer`
     judges whether the RED reason is valid;
  4. the RED→GREEN tree diff touches at least one production path;
  5. the last entry has exit 0.
- **Non-behavior tasks** (`keel-diff --kind`) need no RED. `check` only requires that `verify`
  passed for the task.
- Whether RED failed for the *right reason* is judged by `task-reviewer` from the log.

## `keel-verify`

```text
keel-verify run <feature> --label <baseline|T###|MUT-n|REV-n|FIN-n|test-quality|finish> -- <build-and-test command…>
            → runs it, tees verify/<label>.log, writes verify/<label>.failing (sorted failing test IDs parsed from
              surefire/failsafe XML reports under */target/*-reports/), prints RESULT=pass|fail FAILING=<n> NEW=<n>
keel-verify record <feature> --setup <T###|none>
            → writes the **Analyzed** line and the keel:baseline comment (data-model.md §3) into tasks.md, right after
              its title, from the last passing baseline; RECORDED=<path>, or exit 3 MISSING=baseline|tasks
```

- **`record`** is how analyze writes its evidence, so the model never escapes values by hand:
  - It reads `baseline.result` (`build=`, `tests=`), which exists only after a **passing**
    baseline, plus `baseline.cmd` and `baseline.failing`.
  - It applies the `%2D`/`%25` escaping.
  - It replaces any earlier `**Analyzed**` line and comment, so it is idempotent.

- **The command**: comes from the skill. Host instructions win (VII); otherwise it is detected:
  - `./mvnw verify` or `mvn verify` from the reactor root;
  - a per-module `-f` fallback when the root can't load.
- **Baseline** (`--label baseline`):
  - It always runs with `-fae -Dmaven.test.failure.ignore=true`, so one failing module can't hide
    downstream tests.
  - `RESULT=pass` iff the build *compiled*. It records:
    - the failing set in `baseline.failing`;
    - the tests that ran in `baseline.ran`;
    - the command in `baseline.cmd`.
  - A non-empty failing set is reported as pre-existing (edge case).
  - **No tests yet**: `RESULT=pass TESTS=none` when the build compiles.
  - **Nothing to build**: `RESULT=pass BUILD=none TESTS=none`, as defined by `keel-verify detect`
    below (no build file and no source file by extension).
  - **Undetected build**: sources exist but no build command is defined by the host or detected
    (v1 detects Maven: `./mvnw`, `mvn`). The result is `RESULT=fail BUILD=undetected` with
    `MISSING=build-command`, and the run halts with a request to define the build and test
    commands in CLAUDE.md.
  - The output is shown either way. For a repo with no build at all, the shown "nothing to build or
    test" output is the docs commit's evidence (SC-003 interpretation).
  - **Persistence**: analyze writes the failing set, its count, `baseline.cmd`, the build/test
    state and the setup task into `tasks.md` (data-model.md §3), so they survive the loss of
    `.git/keel/`.
- **Later labels**:
  - Maven runs add `-fae -Dmaven.test.failure.ignore=true` only when `baseline.failing` is
    non-empty.
  - `RESULT=pass` iff the build compiled **and** `NEW=0`. `NEW` counts:
    - failing tests not in `baseline.failing`;
    - tests in `baseline.ran` that produced no fresh report, but only when the label's command
      equals `baseline.cmd` after removing the keel-added `-fae -Dmaven.test.failure.ignore=true`
      (finish always runs the baseline command). Tests whose source file the feature changed or
      deleted are excluded (renames, merges, removals).
  - When `baseline.ran` is unknown (restored from `tasks.md` after losing `.git/keel/`), the
    missing-report clause is skipped, and `NEW` counts only failures not in `baseline.failing`.
  - **No reports**: `RESULT=pass TESTS=none`.
  - **No build**: `RESULT=pass BUILD=none TESTS=none`.
  - The output is shown either way.
- **`MISSING=test-reports`** (research R7.5): for any label, a Maven run with test sources
  (`src/test/**` with a `.java`, `.kt`, `.groovy` or `.scala` extension) that compiled but
  produced no fresh reports gives `RESULT=fail` and exit 1, with a hint to clean the build output.
  "No tests yet" (`TESTS=none` passing) applies only when there are no test sources.
- **`MISSING=test-command`**: exit 3 **only** when the label is a behavior task (`--kind
  behavior`), the repository has no test sources, and no test command can be detected or is
  defined by the host. It never fires at
  baseline, at non-behavior tasks (including the test-setup task) or at finish.
- **Interface additions**:
  - `keel-verify run … --kind behavior|non-behavior` (from `keel-diff --kind`). `MISSING=test-command`
    depends on it.
  - `keel-verify detect` prints `BUILD=maven|host|none|undetected`, `TESTCMD=<cmd|none>` and
    `TESTFW=junit5|junit4|testng|none`. The `tasks` step uses the same detection.
    - `host`: build and test commands are defined in host instructions (VII).
    - `none`: no build file (`pom.xml`, `mvnw`, `build.gradle*`, `settings.gradle*`,
      `package.json`, `Makefile`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `setup.py`) and no
      source file by extension (`.java .kt .kts .scala .groovy .js .mjs .ts .tsx .py .go .rs .rb
      .cs .c .cc .cpp .h .hpp .swift .php`). Dotfiles, `LICENSE*`, `NOTICE*` and `*.md` don't
      count.
    - `undetected`: anything else without a known or host-defined command.
    - `TESTFW=none` in a Maven project (no test-scoped JUnit/TestNG dependency in the effective
      POM) means the `tasks` step must add a setup task that names `pom.xml`, the same as having
      no test command.
  - **Command comparison**: keel's own flags (`-fae -Dmaven.test.failure.ignore=true`) are stripped
    from both commands before comparing. `baseline.cmd` is stored without them.
  - **Changed-test exclusion**: "tests whose source file the feature changed or deleted" is
    computed tree-to-tree, from the base tree against a temp-index tree of the working tree, so it
    is correct before a unit's commit.
- **Fresh reports**: the script touches `verify/<label>.start` before running and counts only
  report files newer than it (`find … -newer`). Stale `target/` reports are ignored.
- **"Compiled"**: no module failed for a reason other than surefire or failsafe test failures,
  judged from Maven's reactor summary and `[ERROR] Failed to execute goal` lines.
- **Spawned commands**: `keel-verify` and `keel-evidence` export the shim PATH and the A0
  environment to the commands they spawn. Subagents' test and build runs are then guarded even if
  the session env doesn't reach subagents (verification item 5).
- **Never skipped silently**: every `TESTS=none` and `BUILD=none` result is shown and listed in the
  final report.
- **Logs**: the skill shows the tail of the log and the summary lines to the developer before any
  commit (Constitution V).

## `keel-mutate`, `keel-classify`

See [mutation-runner.md](./mutation-runner.md).
