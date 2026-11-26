#!/bin/bash
# US1-AS1 / FR-002: the constitution is built from the host's instructions and refers to them.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_repo)
cat > "$r/CLAUDE.md" <<'EOF'
# Payments service

## Principles
- Every payment operation is idempotent: retries never double-charge.
- Never log PAN, CVV or processor credentials; mask them automatically.
- Test-first: a failing test precedes every behavior change.

## Commands
- Build and test: `mvn -q verify`
- Commits: Conventional Commits; never add an AI co-author trailer.
EOF
git -C "$r" add -A; git -C "$r" commit -q -m init
out=$(scn_claude "$r" 25 "/keel:constitution")
c="$r/.specify/memory/constitution.md"
assert_eq yes "$([ -f "$c" ] && echo yes)" "constitution written (out: $out)"
assert_contains "$(cat "$c" 2>/dev/null)" "CLAUDE.md" "it refers to CLAUDE.md"
assert_eq no "$(grep -qE '\[[A-Z][A-Z_]{2,}\]' "$c" 2>/dev/null && echo yes || echo no)" "no template placeholders remain"
assert_eq yes "$(grep -qi 'idempot' "$c" && grep -qiE 'PAN|card' "$c" && echo yes)" "host principles are reflected"
assert_eq "" "$(git -C "$r" log --oneline -1 --format=%s | grep -v '^init$')" "keel does not commit on the default branch"
t_summary
