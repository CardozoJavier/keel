# shellcheck shell=bash
# keel's pinned test-quality toolchain (contracts/mutation-runner.md §Tool resolution; constitution,
# Plugin Constraints). Every Maven plugin keel invokes is addressed by full coordinates from here, so
# a host's plugin prefixes, versions or repositories never change what runs.
KEEL_PIT_VERSION=1.30.2
KEEL_PIT_JUNIT5_VERSION=1.2.3
KEEL_PIT_PLUGIN="org.pitest:pitest-maven:${KEEL_PIT_VERSION}"
KEEL_PIT_JUNIT5_ARTIFACT="org.pitest:pitest-junit5-plugin:${KEEL_PIT_JUNIT5_VERSION}"
KEEL_MVN_DEPENDENCY_PLUGIN="org.apache.maven.plugins:maven-dependency-plugin:3.8.1"
KEEL_MVN_HELP_PLUGIN="org.apache.maven.plugins:maven-help-plugin:3.5.1"
