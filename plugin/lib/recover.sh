# shellcheck shell=bash
# keel_recover <feature> (data-model.md §5): interrupted work-unit recovery, run by `keel-state
# recover` before `keel-branch ensure`. Needs common.sh and units.sh; cwd is the repo root.
# Output: RECOVERED=<unit>|closed:<unit>|deferred|none [PATCH=<path>]; exit 3 HALT=unattributed-changes.
# Only changes attributable to the interrupted unit are ever restored, and a patch is saved first.

keel_recover() {
  local feature=$1 ledger unit row base status cur dirty paths
  ledger="$(keel_root)/bin/keel-ledger"
  # the open unit: the unit of the last unit row, if that row is "started"
  row=$("$ledger" rows "$feature" 2>/dev/null | awk -F'\t' '$3 ~ /^(started|ok|halted|abandoned)$/ && $5 != "" { last = $0 } END { print last }')
  status=$(printf '%s' "$row" | awk -F'\t' '{ print $3 }')
  if [ -z "$row" ] || [ "$status" != "started" ]; then keel_emit RECOVERED none; return 0; fi
  unit=$(printf '%s' "$row" | awk -F'\t' '{ split($5, d, " "); print d[1] }')
  base=$(printf '%s' "$row" | awk -F'\t' '{ print $4 }')
  step=$(printf '%s' "$row" | awk -F'\t' '{ print $2 }')

  cur=$(git symbolic-ref -q --short HEAD 2>/dev/null)
  [ "$cur" = "$feature" ] || { keel_emit RECOVERED deferred; return 0; }

  dirty=$(git status --porcelain=v1 --untracked-files=all 2>/dev/null | awk '{ p = substr($0, 4); sub(/^.* -> /, "", p); if (p != ".specify/feature.json") print p }')
  head=$(git rev-parse HEAD)
  if [ -z "$dirty" ]; then
    if [ "$head" != "$base" ] && keel_recover_matching "$feature" "$unit" "$base"; then
      "$ledger" append "$feature" "$step" ok "$head" "$unit"
      keel_emit RECOVERED "closed:$unit"; return 0
    fi
    "$ledger" append "$feature" "$step" abandoned "$head" "$unit"
    keel_emit RECOVERED none; return 0
  fi
  if [ "$head" != "$base" ]; then
    echo "HALT=unattributed-changes"
    keel_die 3 "keel: uncommitted changes, but HEAD moved past $unit's BASE; they may be yours. Commit or discard them, then resume."
  fi

  # attribution, tree-to-tree against BASE
  local scratch wt from p ok attributed evtrees named
  scratch=$(keel_scratch "$feature")
  if git rev-parse -q --verify "$base^{tree}" >/dev/null 2>&1; then from="$base^{tree}"; wt=$(keel_worktree_tree "$base" "$scratch")
  else from=$(keel_empty_tree); wt=$(keel_worktree_tree EMPTY "$scratch"); fi
  named=$(keel_unit_paths "$feature" "$unit")
  evtrees=$(awk -F'\t' '{ print $5 }' "$scratch/evidence/$unit/index.tsv" 2>/dev/null)
  local evpaths= t
  for t in $evtrees; do evpaths="$evpaths
$(git diff --name-only "$from" "$t" 2>/dev/null)"; done
  for p in $(git diff --name-only "$from" "$wt"); do
    attributed=0
    for n in $named; do
      n=${n%/}
      case "$p" in "$n" | "$n"/*) attributed=1 ;; esac
    done
    [ "$attributed" -eq 0 ] && printf '%s\n' "$evpaths" | grep -qxF -- "$p" && attributed=1
    if [ "$attributed" -eq 0 ] && [ "$p" = "specs/$feature/tasks.md" ]; then
      # only the unit's own [X] may differ
      ok=$(git diff "$from" "$wt" -- "$p" | awk -v u="$unit" '
        /^--- / || /^\+\+\+ / { next }   # patch headers only; a removed "- [ ]" item starts with "--" too
        /^-/ { if ($0 !~ "^-- \\[ \\] " u "( |$)") bad = 1; next }
        /^\+/ { if ($0 !~ "^\\+- \\[[xX]\\] " u "( |$)") bad = 1; next }
        END { print bad ? "no" : "yes" }')
      [ "$ok" = yes ] && attributed=1
    fi
    if [ "$attributed" -eq 0 ]; then
      echo "HALT=unattributed-changes"
      echo "PATH_UNATTRIBUTED=$p"
      keel_die 3 "keel: $p changed but isn't part of $unit; it may be yours. Commit or discard it, then resume."
    fi
  done

  # recover: save, restore tracked paths, remove the unit's new paths
  local patch="$scratch/partial/$unit.patch"
  mkdir -p "$scratch/partial"
  git diff --binary "$from" "$wt" > "$patch" || keel_die 5 "cannot save $patch"
  for p in $(git diff --name-only "$from" "$wt"); do
    if git cat-file -e "HEAD:$p" 2>/dev/null; then
      git restore --source=HEAD --staged --worktree -- "$p" || keel_die 5 "cannot restore $p"
    else
      git rm --cached -q --ignore-unmatch -- "$p" >/dev/null 2>&1
      rm -f -- "$p"
    fi
  done
  "$ledger" append "$feature" "$step" abandoned "$head" "$unit recovered"
  keel_emit RECOVERED "$unit"
  keel_emit PATCH "$patch"
  return 0
}

# keel_recover_matching <feature> <unit> <base>: a commit in base..HEAD carries the unit ID
# (FINISH: HEAD's spec says Implemented).
keel_recover_matching() {
  local feature=$1 unit=$2 base=$3
  if [ "$unit" = FINISH ]; then
    git show "HEAD:specs/$feature/spec.md" 2>/dev/null | grep -q '^\*\*Status\*\*: Implemented'
    return
  fi
  git log --format=%s "$base..HEAD" 2>/dev/null | LC_ALL=C grep -qE "(^|[^A-Za-z0-9])$unit([^A-Za-z0-9-]|\$)"
}
