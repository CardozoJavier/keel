# shellcheck shell=bash
# Shared code for keel's execution-time shims (push guard layer A, contracts/push-guard.md).
# Sourced by plugin/shims/*. bash 3.2. Every shim file carries KEEL_SHIM_MARKER so that discovery
# never mistakes another keel shim (e.g. a second plugin root on PATH) for the real binary.

KEEL_SHIM_MARKER='# keel-shim: never resolve to this file as the real binary'

# keel_shim_deny <rule> <argv...>: the single deny path. Exit 2 is what Claude Code shows the model.
keel_shim_deny() {
  local rule=$1
  shift
  printf 'keel: blocked publish (%s): %s. Run it yourself if intended.\n' "$rule" "$*" >&2
  exit 2
}

# keel_shim_enter <argv...>: recursion guard. Shims exec the real tool, which may run hooks or
# aliases that call the shim again; depth above 3 means a loop, so fail closed.
keel_shim_enter() {
  local depth=${KEEL_SHIM_DEPTH:-0}
  case "$depth" in '' | *[!0-9]*) depth=0 ;; esac
  depth=$((depth + 1))
  if [ "$depth" -gt 3 ]; then
    printf 'keel: blocked publish (AF): shim recursion (depth %s): %s. Run it yourself if intended.\n' "$depth" "$*" >&2
    exit 2
  fi
  KEEL_SHIM_DEPTH=$depth
  export KEEL_SHIM_DEPTH
}

# _keel_is_shim <file>: true if the file carries the keel shim marker in its first 5 lines.
# Builtins only: a shim runs under the caller's PATH, which may lack head/grep.
_keel_is_shim() {
  local line i=0
  while [ "$i" -lt 5 ] && IFS= read -r line; do
    [ "$line" = "$KEEL_SHIM_MARKER" ] && return 0
    i=$((i + 1))
  done < "$1" 2>/dev/null
  return 1
}

# _keel_real_var <tool>: name of the KEEL_REAL_* variable for a tool (builtins only).
_keel_real_var() {
  case "$1" in
    git) echo KEEL_REAL_GIT ;;
    gh) echo KEEL_REAL_GH ;;
    jj) echo KEEL_REAL_JJ ;;
    sl) echo KEEL_REAL_SL ;;
    gt) echo KEEL_REAL_GT ;;
    glab) echo KEEL_REAL_GLAB ;;
    hub) echo KEEL_REAL_HUB ;;
    *) echo KEEL_REAL_UNKNOWN ;;
  esac
}

# _keel_realdir <dir>: physical path of a directory (empty if it doesn't exist).
_keel_realdir() {
  (cd -P "$1" 2>/dev/null && pwd)
}

# keel_shim_real <tool> <shim-dir>: print the real binary for <tool>.
# $KEEL_REAL_<TOOL> (resolved at session start) wins when it is a regular executable file and not
# a shim; otherwise search PATH, skipping empty and relative entries, the shim's own directory
# (physically), any candidate carrying the marker, directories and non-executables. Exit 127 if none.
keel_shim_real() {
  local tool=$1 shimdir var cand own entry rest
  var=$(_keel_real_var "$tool")
  eval "cand=\${$var:-}"
  if [ -n "$cand" ] && [ -f "$cand" ] && [ -x "$cand" ] && ! _keel_is_shim "$cand"; then
    printf '%s\n' "$cand"
    return 0
  fi
  own=$(_keel_realdir "$2")
  rest=$PATH
  while [ -n "$rest" ]; do
    case "$rest" in
      *:*) entry=${rest%%:*}; rest=${rest#*:} ;;
      *) entry=$rest; rest= ;;
    esac
    case "$entry" in /*) ;; *) continue ;; esac
    [ -n "$own" ] && [ "$(_keel_realdir "$entry")" = "$own" ] && continue
    cand="$entry/$tool"
    [ -f "$cand" ] && [ -x "$cand" ] || continue
    _keel_is_shim "$cand" && continue
    printf '%s\n' "$cand"
    return 0
  done
  printf 'keel: %s: real binary not found on PATH\n' "$tool" >&2
  return 127
}
