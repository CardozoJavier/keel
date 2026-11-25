# keel eval scenarios

Skill and agent behavior is checked with `claude plugin eval` (constitution V: "skill and agent
behavior has scenario checks"). The cases live in **`plugin/evals/<case>/`**, because the eval dir
must sit below the plugin root. `tests/eval/evals_test.sh` runs them when you call
`tests/run.sh --eval`.

## Running

```text
tests/run.sh --eval                         # all cases, 1 run each, threshold 1.0
KEEL_EVAL_CASE='plan-*' tests/run.sh --eval  # filter by glob
KEEL_EVAL_MODEL=sonnet tests/run.sh --eval   # override the model
```

The wrapper runs `claude plugin eval plugin --no-publish --ablation none --trust-plugin --runs 1
--threshold 1.0`. Cases that need a fixture repo use `context.scaffold_script`, and the wrapper
adds `--scaffold` because the case files are keel's own. Results go to `plugin/evals/results/`,
which is git-ignored.

## Case format (verified 2026-11-25, Claude Code 2.1.332; docs: code.claude.com/docs/en/plugin-evals.md)

- **Case layout**: a directory with `prompt.md` (frontmatter + prompt) and/or `case.yaml`
  (`schema_version: "1.1"`, `name`), plus at least one grader.
- **`prompt.md` frontmatter**: `name`, `description`, `tags`, `plugins`, `runs`,
  `expected_outcome`, `model`, `max_turns`, `timeout_seconds`, `allowed_tools`,
  `disallowed_tools`, `append_system_prompt`, `env` (keys `EVAL_*`). Unknown keys are errors.
- **`case.yaml` only**: `context.scaffold_script`, `context.history_file` (a `.jsonl` transcript;
  the case prompt becomes the next user turn) and `context.add_dirs`.
- **Graders** go in `graders/<name>.md` (frontmatter `type`, `weight`, `arm`; the body is the
  pattern or criteria) or in a `case.yaml` `graders:` list. Types:
  - `regex`: `pattern`, `flags`, `match` (contains, not_contains, count:N), `target`.
  - `tool_used`: `tool`, `input_match`, `min`, `max`. Use `max: 0` to assert a tool was not used.
  - `tool_order`: `before`, `after`.
  - `file_exists`: `path`, `exists`.
  - `llm`: `criteria`, `focus`.
  - `baseline`: `baseline_file`, `criteria`.
- **Targets**: `last_message`, `trace`, `files`, `{source: file, path}`, `mock_calls`.

## Findings

- **`defaultEnabled: false` breaks evals.** The runner warns that "nothing in the eval sandbox
  enables it" and runs **without** the plugin. keel therefore doesn't set it, and instead installs
  with `--scope local` per repository (quickstart).
- **`plugins:` takes resolvable plugin names.** A bare `keel` is "does not exist", and a relative
  path doesn't enable it either. The plugin under test is loaded automatically, so cases don't set
  `plugins:`.
- **The sandbox can't execute plugin files** (research R7.3). keel's scripts and git shim fail
  with `operation not permitted`, so skill and agent behavior is checked with
  `tests/scenarios/*_scenario.sh` (`tests/run.sh --scenarios`) instead. Only `smoke` stays here.
- **`tool_used` with `max: 0` also needs `min: 0`**; otherwise the range is `1..0` and always fails.
