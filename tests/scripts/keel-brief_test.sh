#!/bin/bash
# keel-brief (contracts/run-state.md, contracts/agent-handoffs.md): builds the implementer brief for
# a work unit from tasks.md, spec.md (FRs, story acceptance scenarios) and design excerpts.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
K="$KEEL_PLUGIN_ROOT/bin/keel-brief"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
f=001-refund
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
r=$(mk_repo); mkdir -p "$r/specs/$f/contracts"
cat > "$r/specs/$f/spec.md" <<'DOC'
# Feature Specification: Refund limit
**Status**: Approved (Gate 1, 2026-11-26)
### User Story 1 - Refunds never exceed the capture (Priority: P1)
A merchant refunds part of a payment.
**Acceptance Scenarios**:
1. **Given** a captured payment of 100, **When** a refund of 120 is requested, **Then** it is rejected.
2. **Given** a captured payment of 100, **When** a refund of 40 is requested, **Then** it is accepted.
---
### User Story 2 - Reporting (Priority: P2)
**Acceptance Scenarios**:
1. **Given** refunds, **When** the report runs, **Then** totals match.
### Functional Requirements
- **FR-001**: Refunds MUST NOT exceed the captured amount.
- **FR-002**: Reports MUST list refunds.
DOC
cat > "$r/specs/$f/tasks.md" <<'DOC'
# Tasks: Refund limit
## Phase 3: User Story 1 - Refunds never exceed the capture (Priority: P1)
- [ ] T001 [US1] Add RefundPolicy.limit (FR-001) in src/main/java/pay/RefundPolicy.java (test: src/test/java/pay/RefundPolicyTest.java)
- [ ] T002 [P] [US2] Add a report in src/main/java/pay/Report.java (test: src/test/java/pay/ReportTest.java)
DOC
cat > "$r/specs/$f/plan.md" <<'DOC'
# Implementation Plan: Refund limit
## Architecture
RefundPolicy.java holds the limit rule and is called by RefundService.
Unrelated line about something else.
DOC
echo "Contract: RefundPolicy.java returns Decision." > "$r/specs/$f/contracts/policy.md"
echo "# repo rules: use records" > "$r/CLAUDE.md"
git -C "$r" add -A; git -C "$r" commit -q -m docs
(cd "$r" && "$L" append $f implement started "$(git -C "$r" rev-parse HEAD)" T001 n/a src/main/java/pay/RefundPolicy.java)

out=$(cd "$r" && "$K" $f T001); rc=$?
assert_eq 0 "$rc" "brief for T001"
b=$(cat "$(kv "$out" BRIEF)")
assert_contains "$b" "# Brief: T001" "title"
assert_contains "$b" "- [ ] T001 [US1] Add RefundPolicy.limit (FR-001) in src/main/java/pay/RefundPolicy.java" "task line verbatim"
assert_contains "$b" "**Story**: US1" "story"
assert_contains "$b" "**Kind**: behavior" "kind from the task's production path"
assert_contains "$b" "**Intent**: n/a" "intent from the ledger"
assert_contains "$b" "a refund of 120 is requested" "story acceptance scenarios"
assert_not_contains "$b" "totals match" "other stories' scenarios are left out"
assert_contains "$b" "**FR-001**: Refunds MUST NOT exceed the captured amount." "referenced FR text"
assert_not_contains "$b" "FR-002" "unreferenced FRs are left out"
assert_contains "$b" "RefundPolicy.java holds the limit rule" "plan excerpt mentioning the task's file"
assert_contains "$b" "returns Decision" "contracts excerpt mentioning the task's file"
assert_not_contains "$b" "Unrelated line" "unrelated plan lines are left out"
assert_contains "$b" "$(cd "$r" && pwd -P)/CLAUDE.md" "host CLAUDE.md path listed"
assert_contains "$b" "keel-evidence run $f T001 red --" "rules name the evidence command"
assert_contains "$b" "keel-put $f reports/T001.md <<'KEEL_EOF'" "the implementer stores its own report"
assert_not_contains "$b" "Return your report as your final message" "the report is not retyped by the orchestrator"

# non-task units take their content from --from
mkdir -p "$r/.git/keel/$f/mut"
printf 'assertion-gap\tk1\tRefundPolicy:12 ConditionalsBoundary (FR-001)\n' > "$r/.git/keel/$f/mut/round1.tsv"
(cd "$r" && "$L" append $f mutate started "$(git -C "$r" rev-parse HEAD)" MUT-1 gap src/test/java)
out=$(cd "$r" && "$K" $f MUT-1 --from "$r/.git/keel/$f/mut/round1.tsv"); rc=$?
assert_eq 0 "$rc" "brief for MUT-1"
b=$(cat "$(kv "$out" BRIEF)")
assert_contains "$b" "RefundPolicy:12 ConditionalsBoundary" "--from content included"
assert_contains "$b" "**FR-001**" "FRs named in the --from content are included"
assert_contains "$b" "**Intent**: gap" "gap intent"
assert_contains "$b" "tests only" "gap rule"
assert_exit 3 "unknown task exits 3" -- sh -c "cd '$r' && '$K' $f T099"
assert_exit 3 "non-task unit without --from exits 3" -- sh -c "cd '$r' && '$K' $f REV-1"
t_summary
