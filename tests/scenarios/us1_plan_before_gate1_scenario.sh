#!/bin/bash
# US1-AS2 / FR-006 / Principle IV: keel's plan step refuses to plan a spec that isn't approved.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_repo); scn_constitution "$r"
git -C "$r" add -A; git -C "$r" commit -q -m init
base=$(git -C "$r" rev-parse HEAD)
git -C "$r" switch -q -c 001-refund
mkdir -p "$r/specs/001-refund"
printf '{"feature_directory": "specs/001-refund"}\n' > "$r/.specify/feature.json"
cat > "$r/specs/001-refund/spec.md" <<EOF
# Feature Specification: Refund limit

**Feature Branch**: \`001-refund\`
**Status**: Draft
**Base**: $base (main)

## Requirements *(mandatory)*

- **FR-001**: Refunds MUST NOT exceed the captured amount.
EOF
out=$(scn_claude "$r" 15 "/keel:plan")
assert_eq no "$([ -f "$r/specs/001-refund/plan.md" ] && echo yes || echo no)" "no plan.md is written before Gate 1"
assert_contains "$(tr 'A-Z' 'a-z' < "$out")" "approv" "the reply points to the missing approval (out: $out)"
t_summary
