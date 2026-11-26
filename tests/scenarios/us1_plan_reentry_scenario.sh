#!/bin/bash
# US4-AS1 / Principle IV: resuming the plan step after Gate 2 never re-runs the architects and
# never asks for the design choice again.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_repo); scn_constitution "$r"
mkdir -p "$r/src/main/java/shop"
printf 'package shop;\n\npublic record Price(long minor) {}\n' > "$r/src/main/java/shop/Price.java"
git -C "$r" add -A; git -C "$r" commit -q -m init
base=$(git -C "$r" rev-parse HEAD)
git -C "$r" switch -q -c 001-discount
mkdir -p "$r/specs/001-discount"
printf '{"feature_directory": "specs/001-discount"}\n' > "$r/.specify/feature.json"
cat > "$r/specs/001-discount/spec.md" <<EOF
# Feature Specification: Percentage discounts

**Feature Branch**: \`001-discount\`
**Status**: Approved (Gate 1, 2026-11-26)
**Path**: full
**Base**: $base (main)

## Requirements *(mandatory)*

- **FR-001**: A price can be reduced by a whole-number percentage from 0 to 100, rounding half up.
EOF
cat > "$r/specs/001-discount/plan.md" <<'EOF'
# Implementation Plan: Percentage discounts

**Branch**: `001-discount` | **Spec**: [spec.md](./spec.md)
**Plan status**: draft

## Design Decision

**Chosen**: smallest change (Gate 2, 2026-11-26)

Add `Price.discounted(int percent)` to the existing record.

### Rejected designs

| Design | What it offered | Why rejected |
|---|---|---|
| clean | a Discount value object | more types than one rule needs |
EOF
out=$(scn_claude "$r" 60 "/keel:plan" --output-format stream-json --verbose)
assert_eq 0 "$(scn_dispatches "$out" architect)" "no architect agent is dispatched on re-entry"
assert_eq 0 "$(scn_dispatches "$out" explorer)" "no explorer agent is dispatched on re-entry"
assert_not_contains "$(tr 'A-Z' 'a-z' < "$out")" "which design" "the design choice is not asked again"
assert_contains "$(cat "$r/specs/001-discount/plan.md")" "**Chosen**: smallest change" "the recorded decision is kept"
t_summary
