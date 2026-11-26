#!/bin/bash
# FR-013 / FR-006 / FR-023: /keel:run binds a new feature (branch before any write, Spec Kit
# feature.json), writes a keel spec and stops at Gate 1 instead of planning.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_repo); scn_constitution "$r"
mkdir -p "$r/src/main/java/shop"
printf 'package shop;\n\npublic record Price(long minor) {\n    public Price {\n        if (minor < 0) throw new IllegalArgumentException("negative");\n    }\n}\n' > "$r/src/main/java/shop/Price.java"
printf '# Shop\n\n- Build and test: `mvn -q verify`\n- Commits: Conventional Commits; never add an AI co-author trailer.\n' > "$r/CLAUDE.md"
git -C "$r" add -A; git -C "$r" commit -q -m init
prompt='/keel:run Prices can be discounted by a percentage between 0 and 100.

Clarification answers, so you do not need to ask anything:
- Intent and why: marketing runs percentage promotions and enters final prices by hand today.
- Goals: a price can be reduced by a whole-number percentage, rounding half up to the cent.
- Non-goals: stacking discounts; currencies.
- Anti-goals: a discount that ever produces a negative price.
- Missing requirements: none.'
out=$(scn_claude "$r" 60 "$prompt")
branch=$(git -C "$r" symbolic-ref --short HEAD)
case "$branch" in 001-*) _t_pass ;; *) _t_fail "the run switched to a 001-* feature branch (got $branch; out: $out)" ;; esac
assert_contains "$(cat "$r/.specify/feature.json" 2>/dev/null)" '"feature_directory": "specs/001-' "feature.json in Spec Kit's format"
spec=$(ls "$r"/specs/001-*/spec.md 2>/dev/null | head -1)
assert_contains "$(cat "$spec" 2>/dev/null)" "**Status**: Draft" "the spec is written and still a draft"
assert_eq no "$(ls "$r"/specs/001-*/plan.md >/dev/null 2>&1 && echo yes || echo no)" "no plan before Gate 1"
assert_contains "$(tr 'A-Z' 'a-z' < "$out")" "approv" "the run asks for approval (Gate 1)"
assert_eq "" "$(git -C "$r" log --oneline main..HEAD)" "nothing is committed before the docs commit"
t_summary
