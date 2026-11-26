<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
specs/001-spec-to-commit-flow/plan.md
<!-- SPECKIT END -->

# keel: working rules

## Never publish

- Never `git push`, never open or merge pull requests, and never write to a forge (issues,
  releases, PR comments). keel's whole contract is "committed locally, ready to push", and that
  applies to keel's own repository too.
- Commit only on a feature branch, in Conventional Commits style, with no AI co-author trailer.

## Shell portability (all of `plugin/bin`, `plugin/lib`, `plugin/hooks`, `plugin/shims`, `tests/`)

- **Target `/bin/bash` 3.2** (macOS) and BSD userland:
  - no `mapfile`, `declare -A`, `${x,,}` or `|&`;
  - guard `"${a[@]}"` for empty arrays under `set -u`;
  - keep `[[ =~ ]]` patterns in variables.
- **No GNU-only tools or flags**: no `timeout`, `tac`, `date -d`, `stat -c`, `find -printf`,
  `xargs -r`, `sed -r`, `\b` or GNU-only `0,/re/` addresses.
  - Run awk with `LC_ALL=C`.
  - Don't name awk variables after builtins (`sub`, `close`, `index`, …).
- **bash 3.2 can't parse a `case` pattern `)` inside `$( … )`.** Move such logic into a function.
- **`read` with a tab `IFS` collapses empty fields**, because tab is IFS whitespace. Split TSV
  rows in awk or with `${line%%<tab>*}`.
- **Scripts write only** under `.git/keel/` (`keel-put`, `keel-classify --out`) and never redirect
  into `.git` from a skill. Temp files use `mktemp` inside the scratch directory.

## Tests (constitution V: test-first; show the output before every commit; never commit on red)

```text
tests/run.sh                  # fast suites (every commit)
tests/run.sh --slow           # + real Maven/PIT (when mutation code changes)
tests/run.sh --scenarios      # skill/agent behavior: real `claude -p --plugin-dir plugin` sessions
tests/mutation-self-check.sh  # sed mutants of critical scripts must fail their suites
claude plugin validate plugin/
```

- **Scenario checks** (`tests/scenarios/*_scenario.sh`) replace `claude plugin eval` for skills,
  because the eval sandbox can't execute plugin files (research R7.3).
- **Each scenario asserts something only the skill causes**, and is confirmed RED first, either
  before the skill exists or with `KEEL_SCN_PLUGIN` pointing at a plugin copy without it.
- **The scenario environment** disables superpowers, feature-dev, pr-review-toolkit, engram,
  jdtls-lsp and github. Memory scenarios use `tests/scenarios/fake_engram.py`, never the real
  engram.

## Vendored material

- `plugin/vendor/` holds pristine upstream copies. `tests/scripts/provenance_test.sh` checks them
  against the installed sources.
- Any in-place edit to a vendored file goes in `plugin/vendor/CHANGELOG.md`, as does every derived
  skill or agent.
- Derived files carry an `Adapted from <upstream> <version> <path>` header. feature-dev
  derivatives also carry an Apache-2.0 §4(b) "Modified by keel" notice.
