#!/bin/bash
# Regenerates plugin/lib/git-builtins.sh from the installed git (run after upgrading git).
# A sourced variable is the fastest lookup for the shim (one `case`, no per-line reads).
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
out="$root/plugin/lib/git-builtins.sh"
{
  printf '# generated from git %s by tests/tools/gen-git-builtins.sh; sourced by plugin/shims/git\n' "$(git --version | awk '{print $3}')"
  printf "KEEL_GIT_BUILTINS=' %s '\n" "$(git --list-cmds=main | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
} > "$out"
printf 'wrote %s\n' "$out"
