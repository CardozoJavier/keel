#!/bin/bash
# keel SessionStart hook: writes the push guard environment into $CLAUDE_ENV_FILE, which Claude
# Code sources before every Bash command (verified 2026-11-25, research R7). It exports KEEL_ROOT
# (CLAUDE_PLUGIN_ROOT is not set inside the Bash tool), the resolved real git/gh (so shims skip a
# PATH search and macOS's xcrun trampoline), and sources keel-env.sh (A0 + shims first on PATH).
# Without CLAUDE_ENV_FILE only layer B is active; keel's self-check then halts keel runs.
cat >/dev/null 2>&1 || true
root=${CLAUDE_PLUGIN_ROOT:-}
[ -n "$root" ] || root=$(cd -P "$(dirname "$0")/.." && pwd)
[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
. "$root/lib/shim-common.sh" || exit 0

real_git=$(keel_shim_real git "$root/shims" 2>/dev/null) || real_git=
if [ "$real_git" = "/usr/bin/git" ] && command -v xcrun >/dev/null 2>&1; then
  resolved=$(xcrun --find git 2>/dev/null) && [ -x "$resolved" ] && real_git=$resolved
fi
real_gh=$(keel_shim_real gh "$root/shims" 2>/dev/null) || real_gh=
{
  printf "export KEEL_ROOT='%s'\n" "$root"
  [ -n "$real_git" ] && printf "export KEEL_REAL_GIT='%s'\n" "$real_git"
  [ -n "$real_gh" ] && printf "export KEEL_REAL_GH='%s'\n" "$real_gh"
  printf ". '%s/hooks/keel-env.sh'\n" "$root"
} >> "$CLAUDE_ENV_FILE"
exit 0
