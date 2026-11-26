# Contract: Mutation Runner and Classifier (`keel-mutate`, `keel-classify`)

Implements FR-030 to FR-035 and SC-012 to SC-014. The v1 backend is PIT through the Maven CLI
(research R5, approach B′).

## `keel-mutate`

```text
keel-mutate --out <dir> (--base <ref|empty-tree> | --module <path>) [--classes <fqcn,…>]
            [--tests <fqcn,…>] [--threads <n>] [--budget <seconds>] [--maven <cmd>]
            [--feature <NNN-name>]
  → RESULT=ok MUTANTS= IN_SCOPE= NO_TEST= MUTANTS_TSV= LOG= COMMAND=  (exit 0)
  → RESULT=not-run REASON=… (10) · RESULT=red|flaky TESTS= LOG= (11) · RESULT=tool-failure REASON= LOG= (12)
```

### Scope

- **Feature mode** (`--base`):
  - **Changed files**: `git diff --name-only --diff-filter=AMR <base> HEAD` (two-dot, so it works
    with the empty-tree base).
  - **Changed lines**: `git diff -U0 <base> HEAD` gives `changed-lines.tsv` (`file start count`).
  - **Java sources**: each changed `**/src/main/java/**/*.java` file maps to its module (nearest
    ancestor `pom.xml`) and its FQCN.
  - **Other sources**: changed non-Java production sources are listed as "not analyzed (language)"
    in `test-quality.md`.
- **Audit mode** (`--module`, used by `test-audit`): every class in the module, or `--classes`.
  Every mutant is in scope.
- **Targets**: `targetClasses` is `X,X$*` for each changed class, so inner and anonymous classes
  are included.
- **Unit tests only.** The selection excludes test classes:
  - whose names end in `IT`, `IntegrationTest` or `E2E`;
  - annotated `@SpringBootTest`, `@Testcontainers`, `@QuarkusTest`, `@QuarkusIntegrationTest`,
    `@DataJpaTest` or `@WebMvcTest` (checked with grep).
- **Test selection**, per changed class `X`:
  - `X{Test,Tests}` in the module's `src/test/java`;
  - test classes changed in `<base> HEAD`;
  - test classes that reference `X` by simple name (import, `new X`, `X.`; checked with grep).
  - `--tests` overrides the selection.
  - Tests listed in the baseline failing set (`tasks.md` `keel:baseline` comment, read through
    `--feature`) are removed from the selection and reported as "excluded: failing at baseline" in
    `<out>/excluded-tests.txt`. Failures unrelated to the feature therefore can't cause exit 11.
    PIT selects test *classes*, so a class with any baseline-failing method is excluded as a whole.
  - Test classes changed in the feature are candidates for **every** changed class in their module.
    A changed class whose only candidates were added for other classes is still sent to PIT, and its
    uncovered mutants show as NO_COVERAGE gaps rather than NO_TEST rows; both block.
- **A changed class with no selected test**: each changed-line range is recorded as one row with
  `status=NO_TEST`, without running PIT on it.
  - Its key is `sha1(class|NO_TEST|file:start+count)`.
  - It is resolved by adding a test, after which the next round runs PIT on the class normally and
    the row is replaced by real mutants, or by a triage row with that key.

### Preconditions and support (FR-035, edge cases), checked in order

| Condition | Exit and reason |
|---|---|
| No changed Java production class | exit 10 `nothing to analyze` |
| A changed class has no ancestor `pom.xml` | exit 10 `not a Maven project` |
| `org.junit.platform:junit-platform-engine` is not on the module's test classpath (JUnit 4 or TestNG only) | exit 10 `JUnit Platform not found; v1 supports JUnit 5/Platform only` |
| The module's effective POM already configures `pitest-maven` (plugin config would override `-D` values) | exit 10 `host configures PIT; run the host's own PIT configuration` |
| Selected tests fail on one run | exit 11 (red) |
| Selected tests pass, then fail on a second run | exit 11 (flaky) |

- **Maven executable**: `--maven` (from host instructions), else `./mvnw` if present, else `mvn`.
- **Test runs**: `<mvn> <module-args> test -Dtest=<sel> -Dsurefire.failIfNoSpecifiedTests=false`.

### Module arguments (no `install`, ever; verified at M5, research R7.6)

- **The root module** (`.`): `-f pom.xml`.
- **A submodule**: keel-mutate probes `-pl <module> -am` with the pinned help plugin from the
  repository root, once per module.
  - **Reactor mode**, when the probe succeeds: `-pl <module> -am` on every Maven call for that
    module, plus `-DfailWhenNoMutations=false` on the PIT run, so upstream modules with no target
    pass.
    - Sibling SNAPSHOTs come from the reactor, so nothing needs to be installed. The classpath check
      runs with `test-compile`, because a sibling's classes exist only once the reactor has
      compiled them.
    - Upstream modules share `reportsDirectory`, but the requested module runs last, so its report
      is the final one.
  - **`-f <module>/pom.xml`**, when there is no root reactor or it can't load (e.g. a broken
    sibling POM). Sibling SNAPSHOTs then come from `~/.m2` and may be stale or missing; a missing
    one is a tool failure that names the module.
- The chosen arguments are saved in `<out>/<module>/module-args` and recorded in `test-quality.md`.
- Module paths must not contain spaces.

### Tool resolution (all versions pinned in `lib/versions.sh`)

- **Pinned versions**:
  - PIT 1.30.2.
  - pitest-junit5-plugin 1.2.3.
  - maven-dependency-plugin 3.8.1, called as `org.apache.maven.plugins:maven-dependency-plugin:3.8.1:<goal>`.
  - maven-help-plugin 3.5.1, called the same way.
  - These four are keel's pinned test-quality toolchain (constitution, Plugin Constraints).
- **Launcher version**: the `junit-platform-engine` version on the module's test classpath (from
  `dependency:list -DincludeArtifactIds=junit-platform-engine -DoutputFile=<out>/deps.txt`). It
  selects `junit-platform-launcher:<same version>`.
- **Download**: `dependency:get -Dartifact=<g:a:v>` fetches the jars into Maven's own cache. The
  `~/.m2` carve-out covers this.
- **Jar paths**: `<localRepo>/<group path>/<a>/<v>/<a>-<v>.jar`, with `localRepo` from
  `help:evaluate -Dexpression=settings.localRepository -DforceStdout -q`.

### Invocation (no `-q` on the PIT run: the fail-closed checks read its log)

```text
<mvn> <module-args> test-compile \
  org.pitest:pitest-maven:1.30.2:mutationCoverage \
  -DtargetClasses=<X,X$*,…> -DtargetTests=<fqcn,…> \
  -DoutputFormats=XML -DfullMutationMatrix=true -DtimestampedReports=false \
  -DreportsDirectory=<out>/<module-slug>/pit \
  -DadditionalClasspathElements=<pitest-junit5-plugin.jar>,<junit-platform-launcher.jar> \
  [-Dthreads=<n>]
```

- The project's build files are never edited (FR-034, SC-014).
- `test-quality.md` records the exact command.
- **Budget**: `--budget` (default 900 s) is enforced by a bash watchdog: a background `sleep` plus
  `kill` of the process group. macOS has no GNU `timeout`.
- **Long runs**: the skill runs `keel-mutate` with `run_in_background` and waits for completion,
  because the Bash tool's foreground limit is 2 minutes by default and 10 at most.

### Fail-closed checks (tool failure, exit 12)

1. Maven exits non-zero, or `mutations.xml` is missing.
2. The log contains `pitest junit 5 plugin is not installed`.
3. Tests were selected for a class, yet in `mutations.xml` every mutant of that class has an empty
   `<coveringTests>`, *and* the log shows `Ran 0 tests` or lacks a `Largest test (` line. This is
   R5's silent false negative, detected from the data rather than the log alone.
4. `RUN_ERROR` affects more than 10% of mutants. `NON_VIABLE` mutants are excluded and counted.
5. The budget is exceeded.

### Output: `<out>/mutants.tsv` (UTF-8, tab-separated, header row; lists are `|`-separated)

```text
key  class  method  line  mutator  status  in_scope  killing  succeeding
```

- **`key`**: stable across runs and across line shifts. It is the SHA-1 (via `git hash-object
  --stdin`) of `class|method|methodDescription|mutator|indexes`, with no line, because review and
  finish fixes shift lines in exactly the classes finish re-mutates. Triage rows refer to it, and
  the implementer proposes them in its report while the orchestrator writes them within the
  unit.
- **`in_scope`**:
  - `yes` when `line` falls inside a changed-line range of the class's source file, and always in
    audit mode;
  - otherwise `no`, which means reported and never blocking (FR-030: "code the feature changed").
- **`status`**: one of KILLED, SURVIVED, NO_COVERAGE, TIMED_OUT, MEMORY_ERROR, RUN_ERROR,
  NON_VIABLE, NO_TEST.
- **Test IDs**:
  - XML entities (`&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`) are decoded first.
  - Then the JUnit unique ID is normalized:
    - `[class:C]/[method:m(..)]` becomes `C#m`.
    - `[nested-class:N]` becomes `C$N#m`.
    - `[test-template:m(..)]/[test-template-invocation:#k]` becomes `C#m`.
    - `[test-factory:m(..)]/[dynamic-test:#k]` becomes `C#m`.
  - Any other form keeps its raw ID (no failure).
- **Parser**: `lib/pit-xml.sh` relies on one `<mutation>` element per line (confirmed in the spike).
  A line without `mutatedClass` and `status` is a tool failure (exit 12).
- **Logs**: `<out>/run.log` holds the combined Maven and PIT output.
- **Exit codes**: 0 ok, 10 unsupported or nothing to analyze, 11 red or flaky, 12 tool failure.

## `keel-classify`

```text
keel-classify <mutants.tsv> [--triage specs/<NNN>/test-quality.triage.tsv] [--out <file>] [--summary]
```

- `--out <file>` writes the rows to a file, so callers never redirect into `.git`, and keeps the
  exit code.
- `--summary` prints only the `test-quality.md` Summary line:
  `SUMMARY=<n> mutants (<n> in scope); killed <k>; coverage gaps <c>; assertion gaps <a>; triaged <t>; excluded <x>`.
  NO_TEST rows count as coverage gaps but not as generated mutants; when there are any, the coverage
  count reads `<c> (<u> with no test)`. The model copies the line and never counts by hand.

Pure POSIX awk under `LC_ALL=C`, deterministic (FR-031). `triage.tsv` holds `key reason` rows,
written by the `mutate` skill.

| kind | Rule | Blocking |
|---|---|---|
| `coverage-gap` | `in_scope=yes` and status NO_COVERAGE or NO_TEST, key not triaged | yes |
| `assertion-gap` | `in_scope=yes` and status SURVIVED, key not triaged | yes |
| `triaged` | an in-scope gap whose key appears in `triage.tsv` | no (reason listed) |
| `out-of-scope` | `in_scope=no` gaps | no (count reported) |
| `redundant` | test T has a non-empty kill set K(T), and every mutant in K(T) is also killed by another test | no |
| `kills-nothing` | T appears in `succeeding` at least once and in no `killing` list | no |
| `overlap` | ≥ 2 tests with identical non-empty kill sets | no |
| `excluded` | NON_VIABLE, RUN_ERROR, TIMED_OUT, MEMORY_ERROR (the last two count as detected) | no |

- **Output columns**: `kind subject detail`.
- **Exit codes**: 0 when there are no blocking rows, 1 when there are blocking rows, 2 for
  malformed input.

Resolution status is **computed** (blocking rows minus triaged keys), never judged by the model.
Only the triage *reasons* are written by the model; reviewers check them (see `review`).

## Gap resolution (performed by the `mutate` skill)

- Each blocking row gets one of two resolutions:
  - **Test**: a new or strengthened test that references the FR or acceptance scenario it checks.
    `task-reviewer` rejects tests that assert implementation details only to kill a mutant
    (FR-032).
  - **Triage**: a `triage.tsv` row with the key and a reason, either `equivalent: <why no
    observable effect>` or `not worth a test: <why>`.
- At most 3 resolve-and-re-run rounds, re-running only the affected classes. `keel-classify` exit 1
  after round 3 halts the run.
- Gap-closing tests check existing spec behavior, so they pass on the current code. Their RED
  equivalent is the computed kill: the targeted key must turn KILLED on the re-run, or the test
  doesn't count. They are committed after `verify` passes.

## `test-quality.md` (committed in the feature directory)

```markdown
# Test Quality: <feature>
**Result**: resolved | not-run (<reason>)        ← a halted mutate never writes this file; its summary goes to scratch and the final report
**Base**: <sha> | **Tool**: PIT 1.30.2 + pitest-junit5-plugin 1.2.3 + junit-platform-launcher <v>
**Command**: <invocation> | **Module args**: -f <module> (sibling SNAPSHOTs from ~/.m2: <list or none>) | -pl/-am (if verified at M5)
**Scope**: <n> classes in <modules>; changed lines only; tests: <list>; not analyzed: <non-Java files>
**Summary**: <generated> mutants (<in-scope> in scope); killed <k>; coverage gaps <c>; assertion gaps <a>; triaged <t>; excluded <x>

## Gaps (in scope)
| Key | Location | Mutator | Status | Resolution |
|---|---|---|---|---|
| 3f2a… | FeeCalculator:12 | ConditionalsBoundary | SURVIVED | test `FeeCalculatorTest#should_…` (FR-007) |
| 9b01… | FeeCalculator:20 | VoidMethodCall | SURVIVED | triaged: equivalent (log call, no observable effect) |

## Redundancy and overlap (not blocking)
- redundant: `C#t1` (kills ⊂ `C#t2`)
- kills nothing: `C#t3`
- overlap: {`C#t4`, `C#t5`}: action: none | merged (identical behavior)

## Rounds
1. <date>: <n> gaps → <n> tests, <n> triaged
```

**History and re-runs**:
- `--base` always reads **committed** history (`<base>..HEAD`). Every work unit (`T###`, `MUT-n`,
  `REV-n`, `FIN-n`) is committed before any analysis runs, so fix lines are in scope and line
  numbers match.
- `--classes` restricts a run to the given classes, with either `--base` or `--module`.
- Review fixes don't trigger a re-run inside `review`. Instead, `finish` re-runs `keel-mutate
  --base <feature base> --classes <production classes changed since the test-quality commit>`
  before its commit, resolves the gaps in `FIN-n` units, and updates this file (SC-012).
- Triage decisions are committed in `specs/<NNN>/test-quality.triage.tsv` (`key reason`). They are
  keel's decisions, not raw tool output, so they survive the loss of `.git/keel/`.

Raw output (`mutations.xml`, `run.log`, the TSVs) stays in `.git/keel/<feature>/mut/` and is never
committed (FR-034).
