# shellcheck shell=bash
# keel shared library. Sourced by plugin/bin/* and plugin/hooks/*.
# Portability: bash 3.2 (macOS /bin/bash), BSD awk/sed. No GNU-only flags, no associative
# arrays, no `timeout`, `tac`, `date -d`, `stat -c`, `find -printf` or `xargs -r`.
# Expand possibly-empty arrays as ${arr[@]+"${arr[@]}"} under `set -u`.

# keel_resolve_path <path>: follow symlinks (no `readlink -f` on macOS) and print the real path.
keel_resolve_path() {
  local p=$1 d
  while [ -h "$p" ]; do
    d=$(cd -P "$(dirname "$p")" && pwd)
    p=$(readlink "$p")
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  d=$(cd -P "$(dirname "$p")" && pwd)
  printf '%s/%s\n' "$d" "$(basename "$p")"
}

KEEL_LIB_DIR=$(dirname "$(keel_resolve_path "${BASH_SOURCE[0]}")")

# keel_root: the plugin root. $KEEL_ROOT (exported by the SessionStart env file) wins, because
# CLAUDE_PLUGIN_ROOT is not set inside the Bash tool; otherwise derive it from this file.
keel_root() {
  if [ -n "${KEEL_ROOT:-}" ] && [ -d "$KEEL_ROOT" ]; then
    printf '%s\n' "$KEEL_ROOT"
  else
    (cd -P "$KEEL_LIB_DIR/.." && pwd)
  fi
}

# keel_emit KEY value...: machine-readable output line.
keel_emit() {
  local k=$1
  shift
  printf '%s=%s\n' "$k" "$*"
}

# keel_die <code> <message>: diagnostic on stderr, then exit.
keel_die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

# keel_repo_root: top of the current git work tree (exit 5 outside a repo).
keel_repo_root() {
  local t
  t=$(git rev-parse --show-toplevel 2>/dev/null) || keel_die 5 "MISSING=git-repo"
  (cd -P "$t" && pwd)
}

# keel_git_dir: absolute git dir of the current repository.
keel_git_dir() {
  local g
  g=$(git rev-parse --absolute-git-dir 2>/dev/null) || keel_die 5 "MISSING=git-repo"
  (cd -P "$g" && pwd)
}

# keel_scratch <feature>: run scratch dir, created on demand. Never tracked (inside .git).
keel_scratch() {
  local s
  s="$(keel_git_dir)/keel/$1"
  mkdir -p "$s"
  printf '%s\n' "$s"
}

# keel_tac: print stdin lines in reverse order (portable replacement for tac).
keel_tac() {
  awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }'
}

# keel_match_id <id-regex> <text>: true when <text> contains the unit ID at a word boundary.
# Explicit boundary classes, because \b is unsupported in BSD awk and bash 3.2 regexes.
keel_match_id() {
  printf '%s\n' "$2" | LC_ALL=C grep -Eq "(^|[^A-Za-z0-9])$1([^A-Za-z0-9-]|\$)"
}

# keel_empty_tree: the id of git's empty tree (base of an unborn repository).
keel_empty_tree() {
  git hash-object -t tree /dev/null
}

# keel_worktree_tree <ref|EMPTY> <scratch-dir>: write a tree mirroring the working tree
# (tracked + untracked, ignored excluded, .specify/feature.json excluded) without touching the
# real index. The temp index is seeded with read-tree so tracked-but-ignored files stay, and
# filled with top-anchored pathspecs so the persistent cwd doesn't matter. The index file must
# not pre-exist: a 0-byte file makes `git add` fail with rc 128.
keel_worktree_tree() {
  local ref=$1 dir=$2 idx tree rc
  mkdir -p "$dir"
  idx="$dir/idx.$$"
  rm -f "$idx"
  if [ "$ref" = "EMPTY" ]; then
    GIT_INDEX_FILE="$idx" git read-tree --empty || { rm -f "$idx"; return 1; }
  else
    GIT_INDEX_FILE="$idx" git read-tree "$ref" || { rm -f "$idx"; return 1; }
  fi
  GIT_INDEX_FILE="$idx" git add -A -- ':/' ':(top,exclude).specify/feature.json' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    tree=$(GIT_INDEX_FILE="$idx" git write-tree)
    rc=$?
  fi
  rm -f "$idx"
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "$tree"
}
