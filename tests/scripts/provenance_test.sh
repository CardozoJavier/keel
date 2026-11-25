#!/bin/bash
# FR-026 / constitution III: every vendored file has a provenance record, vendored files are
# pristine unless the change log says otherwise, NOTICE attributes all three upstreams, and
# adapted skills/agents name an existing vendored source (Apache derivatives carry a change notice).
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
V="$KEEL_PLUGIN_ROOT/vendor"
PROV="$V/PROVENANCE.md"
CHG="$V/CHANGELOG.md"

assert_eq yes "$([ -f "$PROV" ] && echo yes)" "PROVENANCE.md exists"
prov=$(cat "$PROV" 2>/dev/null)
chg=$(cat "$CHG" 2>/dev/null)

# 1. every vendored file is covered by a listed path or directory prefix
for up in speckit superpowers feature-dev; do
  assert_contains "$prov" "| $up |" "upstream row for $up"
  for f in $(cd "$V/$up" && find . -type f | sed 's#^\./##' | LC_ALL=C sort); do
    covered=no
    p=$f
    while :; do
      case "$prov" in *"\`$up/$p\`"*) covered=yes; break ;; esac
      case "$p" in */*) p=${p%/*}; case "$prov" in *"\`$up/$p/\`"*) covered=yes; break ;; esac ;; *) break ;; esac
    done
    assert_eq yes "$covered" "provenance covers $up/$f"
  done
done

# 2. upstream rows carry version and license
assert_contains "$prov" "0.8.4.dev0" "Spec Kit version recorded"
assert_contains "$prov" "7.0.2" "superpowers version recorded"
assert_contains "$prov" "1.0.1" "feature-dev version recorded"

# 3. vendored files are byte-identical to upstream unless listed in the change log
check_pristine() { # <upstream-name> <local-subdir> <upstream-dir>
  local up=$1 sub=$2 src=$3 f
  [ -d "$src" ] || return 0
  for f in $(cd "$V/$up/$sub" && find . -type f | sed 's#^\./##'); do
    [ -f "$src/$f" ] || continue
    if cmp -s "$V/$up/$sub/$f" "$src/$f"; then _t_pass; else
      assert_contains "$chg" "$up/$sub/$f" "edited vendored file $up/$sub/$f is in CHANGELOG.md"
    fi
  done
}
check_pristine speckit templates "$HOME/.local/share/uv/tools/specify-cli/lib/python3.11/site-packages/specify_cli/core_pack/templates"
check_pristine speckit scripts/bash "$HOME/.local/share/uv/tools/specify-cli/lib/python3.11/site-packages/specify_cli/core_pack/scripts/bash"
check_pristine superpowers skills "$HOME/.claude/plugins/cache/claude-plugins-official/superpowers/7.0.2/skills"
check_pristine feature-dev agents "$HOME/.claude/plugins/cache/claude-plugins-official/feature-dev/1.0.1/agents"

# 4. NOTICE files attribute all three upstreams
for n in "$KEEL_REPO_ROOT/NOTICE" "$KEEL_PLUGIN_ROOT/NOTICE"; do
  txt=$(cat "$n" 2>/dev/null)
  for w in "Spec Kit" "GitHub, Inc." "MIT" "superpowers" "Jesse Vincent" "feature-dev" "Apache License"; do
    assert_contains "$txt" "$w" "$(basename "$(dirname "$n")")/NOTICE mentions $w"
  done
done

# 5. adapted skills/agents name an existing vendored source; Apache derivatives carry a change notice
for f in $(find "$KEEL_PLUGIN_ROOT/skills" "$KEEL_PLUGIN_ROOT/agents" -name '*.md' 2>/dev/null); do
  hdr=$(grep -m1 -E 'Adapted from (speckit|superpowers|feature-dev) ' "$f" || true)
  [ -n "$hdr" ] || continue
  up=$(printf '%s' "$hdr" | sed -E 's/.*Adapted from (speckit|superpowers|feature-dev) [^ ]+ ([^ ]+).*/\1/')
  path=$(printf '%s' "$hdr" | sed -E 's/.*Adapted from (speckit|superpowers|feature-dev) [^ ]+ ([^ ]+).*/\2/')
  assert_eq yes "$([ -e "$V/$up/$path" ] && echo yes)" "$(basename "$(dirname "$f")")/$(basename "$f") source $up/$path exists"
  if [ "$up" = "feature-dev" ]; then
    assert_contains "$(cat "$f")" "Modified by keel" "$f carries an Apache-2.0 §4(b) change notice"
  fi
done

t_summary
