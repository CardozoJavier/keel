#!/bin/bash
# Mutation self-check (T075, constitution V): keel's own critical bash, mutated with sed. PIT doesn't
# apply to bash; these hand-written mutants are its equivalent. Each mutant is applied to a copy of
# the repository and must make its suite fail. Survivors must be triaged in
# tests/mutation-self-check.triage (`<id><TAB><reason>`); an untriaged survivor exits 1.
# Usage: tests/mutation-self-check.sh [<id>...]
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
triage="$root/tests/mutation-self-check.triage"
work=$(mktemp -d "${TMPDIR:-/tmp}/keel-selfcheck.XXXXXX")
trap 'rm -rf "$work"' EXIT
rsync -a --exclude .git --exclude plugin/evals/results "$root/" "$work/repo/"

# id ~ file ~ sed expression (BSD sed, BRE: | and & are literals) ~ suites ~ what the mutant breaks
MUTANTS='M01~plugin/shims/git~s/    push | send-pack | http-push | send-email | imap-send)/    send-pack | http-push | send-email | imap-send)/~tests/guard/shims/git_test.sh~git push no longer denied (A1)
M02~plugin/shims/git~s/dcommit | set-tree) keel_shim_deny A2/dcommit) keel_shim_deny A2/~tests/guard/shims/git_test.sh~git svn set-tree allowed (A2)
M03~plugin/shims/git~s/_protected_key "$key" && keel_shim_deny A8/true/~tests/guard/shims/git_test.sh~git -c with a protected key allowed (A8)
M04~plugin/shims/gh~s/create | new | merge | update-branch | revert | reopen | ready) _deny A4/new | merge | update-branch | revert | reopen | ready) _deny A4/~tests/guard/shims/gh_test.sh~gh pr create allowed (A4)
M05~plugin/shims/gh~s/state=open | state=OPEN) _deny A5/state=OPEN) _deny A5/~tests/guard/shims/gh_test.sh~gh api state=open allowed (A5)
M06~plugin/hooks/guard-push.sh~/^deny() {/,/^}/s/exit 2/exit 0/~tests/guard/hook/shell_test.sh tests/guard/hook/mcp_test.sh~layer B allows what it means to deny
M07~plugin/hooks/guard-push.sh~s/\[ "$has_path" -eq 1 \] || deny B2/true || deny B2/~tests/guard/hook/shell_test.sh~PATH replaced without the shims allowed (B2)
M08~plugin/bin/keel-classify~s/else { emit(gap, key, loc); blocking++;/else { emit(gap, key, loc);/~tests/scripts/keel-classify_test.sh~gaps no longer block
M09~plugin/bin/keel-classify~s/if (scope != "yes") emit("out-of-scope"/if (scope == "yes") emit("out-of-scope"/~tests/scripts/keel-classify_test.sh~scope inverted
M10~plugin/bin/keel-classify~s/if (nkillers\[km\[i\]\] < 2) { all = 0; break }/if (nkillers[km[i]] < 1) { all = 0; break }/~tests/scripts/keel-classify_test.sh~every killing test reported redundant
M11~plugin/bin/keel-state~s/^elif row_review; then progress=finish/elif row_mutate; then progress=finish/~tests/scripts/keel-state_test.sh tests/scripts/resume_matrix_test.sh~review is skipped
M12~plugin/bin/keel-state~s/^row_analyze() { head_file "$tasks"/row_analyze() { cat "$tasks"/~tests/scripts/keel-state_test.sh tests/scripts/resume_matrix_test.sh~an uncommitted Analyzed line counts
M13~plugin/bin/keel-state~s/^row_finish() { head_file "$spec"/row_finish() { cat "$spec"/~tests/scripts/keel-state_test.sh tests/scripts/resume_matrix_test.sh~an uncommitted Implemented counts as done
M14~plugin/bin/keel-evidence~s/\[ -z "$(changed_kind "$from_tree" "$red_tree" production)" \] || miss/true || miss/~tests/scripts/keel-evidence_test.sh~RED with a production change accepted
M15~plugin/bin/keel-evidence~s/if \[ "$phase" = red \] && \[ "$rc" != 0 \]/if [ "$phase" = red ]/~tests/scripts/keel-evidence_test.sh~a passing run counts as RED
M16~plugin/bin/keel-evidence~s/\[ -n "$red_tree" \] && \[ "$green_ok" -eq 1 \] || miss/true || miss/~tests/scripts/keel-evidence_test.sh~GREEN-only evidence accepted'

only=" $* "
killed=0 survived=0 untriaged=0 broken=0
printf '%-4s %-9s %s\n' ID RESULT MUTANT
while IFS='~' read -r id file expr suites what; do
  [ -n "$id" ] || continue
  case "$only" in "  ") ;; *" $id "*) ;; *) continue ;; esac
  cp "$root/$file" "$work/repo/$file"
  sed -i '' -e "$expr" "$work/repo/$file" 2>/dev/null
  if cmp -s "$root/$file" "$work/repo/$file"; then
    printf '%-4s %-9s %s (%s: sed did not apply)\n' "$id" NOT-APPL "$what" "$file"; broken=$((broken + 1)); continue
  fi
  failed=0
  for s in $suites; do
    (cd "$work/repo" && /bin/bash "$s" >/dev/null 2>&1) || { failed=1; break; }
  done
  cp "$root/$file" "$work/repo/$file"
  if [ "$failed" -eq 1 ]; then
    killed=$((killed + 1)); printf '%-4s %-9s %s\n' "$id" KILLED "$what"
  else
    survived=$((survived + 1))
    reason=$(awk -F'\t' -v i="$id" '$1 == i { print $2 }' "$triage" 2>/dev/null)
    if [ -n "$reason" ]; then printf '%-4s %-9s %s (triaged: %s)\n' "$id" SURVIVED "$what" "$reason"
    else untriaged=$((untriaged + 1)); printf '%-4s %-9s %s (UNTRIAGED)\n' "$id" SURVIVED "$what"; fi
  fi
done <<EOF
$MUTANTS
EOF
printf 'killed=%d survived=%d untriaged=%d not-applied=%d\n' "$killed" "$survived" "$untriaged" "$broken"
[ "$untriaged" -eq 0 ] && [ "$broken" -eq 0 ]
