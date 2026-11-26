#!/bin/bash
# Runs keel's plugin eval scenarios (plugin/evals/*) through `claude plugin eval`.
# Invoked by `tests/run.sh --eval`. Exit status is the eval run's (threshold 1.0).
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
args=(plugin eval "$KEEL_PLUGIN_ROOT" --no-publish --ablation none --trust-plugin --runs 1 --threshold 1.0 --scaffold --allow-tools Bash Write Edit)
[ -n "${KEEL_EVAL_CASE:-}" ] && args+=(--case "$KEEL_EVAL_CASE")
[ -n "${KEEL_EVAL_MODEL:-}" ] && args+=(--model "$KEEL_EVAL_MODEL")
claude "${args[@]}"
