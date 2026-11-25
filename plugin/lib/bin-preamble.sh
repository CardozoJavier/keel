# shellcheck shell=bash
# Sourced first by every plugin/bin/keel-* script (after it locates this file) to load common.sh.
# The scripts find the plugin root from $KEEL_ROOT (exported by the session env file) or from their
# own resolved path, because CLAUDE_PLUGIN_ROOT is not set inside the Bash tool.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# keel_feature_ok <name>: feature names are NNN-slug, never paths.
keel_feature_ok() {
  case "$1" in
    [0-9][0-9][0-9]-*) case "$1" in */* | *..* | *[!A-Za-z0-9._-]*) return 1 ;; esac; return 0 ;;
  esac
  return 1
}
