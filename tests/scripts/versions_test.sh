#!/bin/bash
# lib/versions.sh pins keel's test-quality toolchain; keel-mutate invokes Maven plugins only by those
# pinned coordinates (no plugin prefixes such as `dependency:list`, no literal versions).
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
. "$KEEL_PLUGIN_ROOT/lib/versions.sh"
assert_eq "org.pitest:pitest-maven:1.30.2" "$KEEL_PIT_PLUGIN" "PIT 1.30.2"
assert_eq "org.pitest:pitest-junit5-plugin:1.2.3" "$KEEL_PIT_JUNIT5_ARTIFACT" "pitest-junit5-plugin 1.2.3"
assert_eq "org.apache.maven.plugins:maven-dependency-plugin:3.8.1" "$KEEL_MVN_DEPENDENCY_PLUGIN" "maven-dependency-plugin 3.8.1"
assert_eq "org.apache.maven.plugins:maven-help-plugin:3.5.1" "$KEEL_MVN_HELP_PLUGIN" "maven-help-plugin 3.5.1"

M="$KEEL_PLUGIN_ROOT/bin/keel-mutate"
assert_eq yes "$([ -f "$M" ] && echo yes)" "keel-mutate exists"
code=$(grep -v '^[[:space:]]*#' "$M" 2>/dev/null)
assert_eq "" "$(printf '%s\n' "$code" | grep -nE '(^|[^A-Za-z0-9_}.:-])(dependency|help|pitest|surefire):[a-z]' )" "no unpinned plugin-prefix goals"
assert_eq "" "$(printf '%s\n' "$code" | grep -nE '[0-9]+\.[0-9]+\.[0-9]+')" "no literal versions: all come from versions.sh"
assert_eq "" "$(printf '%s\n' "$code" | grep -nwE 'install|deploy')" "never install or deploy"
for v in KEEL_PIT_PLUGIN KEEL_MVN_DEPENDENCY_PLUGIN KEEL_MVN_HELP_PLUGIN KEEL_PIT_JUNIT5_ARTIFACT; do
  assert_contains "$code" "\$$v" "keel-mutate uses \$$v"
done
t_summary
