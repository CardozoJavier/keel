#!/bin/bash
# FR-012 / plan §Tasks and analyze: a CRITICAL finding (no test framework and no setup task) halts
# analyze before the baseline: no **Analyzed** line, no docs commit.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
cat > "$r/pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>shop</groupId>
  <artifactId>shop</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.release>21</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
</project>
EOF
rm -rf "$r/src/test"
git -C "$r" add -A; git -C "$r" commit -q -m "chore: no tests yet"
f=001-price-is-zero
scn_light_feature "$r" "$f" "Price isZero" "Price MUST report whether its amount is zero, through an isZero() check."
printf '# Tasks: %s\n\n## Phase 1: User Story 1\n\n- [ ] T001 [US1] Add Price.isZero() in src/main/java/shop/Price.java (test: src/test/java/shop/PriceTest.java)\n' "$f" > "$r/specs/$f/tasks.md"
before=$(git -C "$r" rev-parse HEAD)
out=$(scn_claude "$r" 40 "/keel:analyze --feature $f")
assert_contains "$(cat "$out")" "CRITICAL" "analyze reports the missing setup task as CRITICAL (out: $out)"
assert_eq no "$(grep -q '^\*\*Analyzed\*\*' "$r/specs/$f/tasks.md" && echo yes || echo no)" "no Analyzed line is written"
assert_eq "$before" "$(git -C "$r" rev-parse HEAD)" "no docs commit"
assert_eq analyze "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "keel-state stays at analyze"
t_summary
