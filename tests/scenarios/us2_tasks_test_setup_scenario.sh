#!/bin/bash
# FR-011 / plan §Tasks: in a Maven repo with no test framework (TESTFW=none), tasks adds a
# non-behavior test-setup task naming pom.xml before the first behavior task, and every behavior
# task names its test path.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
r=$(scn_sample)
# drop the test framework: a pom with no test-scoped dependency, and no tests
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
assert_contains "$(scn_keel "$r" keel-verify detect)" "TESTFW=none" "the fixture has no test framework"
out=$(scn_claude "$r" 40 "/keel:tasks --feature $f")
t="$r/specs/$f/tasks.md"
assert_eq yes "$([ -f "$t" ] && echo yes)" "tasks.md is written (out: $out)"
setup=$(grep -nE '^- \[ \] T[0-9]{3}' "$t" 2>/dev/null | grep -i 'pom\.xml' | head -1 | cut -d: -f1)
first_behavior=$(grep -nE '^- \[ \] T[0-9]{3}.*\(test: ' "$t" 2>/dev/null | head -1 | cut -d: -f1)
assert_eq yes "$([ -n "$setup" ] && echo yes)" "a setup task names pom.xml"
assert_eq yes "$([ -n "$setup" ] && [ -n "$first_behavior" ] && [ "$setup" -lt "$first_behavior" ] && echo yes)" "the setup task comes before the first behavior task"
assert_eq 0 "$(grep -E '^- \[ \] T[0-9]{3}' "$t" 2>/dev/null | grep 'src/main/' | grep -vc '(test: ')" "every task touching src/main names its test path"
assert_eq analyze "$(scn_state "$r" --feature "$f" | sed -n 's/^STEP=//p')" "keel-state moves on to analyze"
t_summary
