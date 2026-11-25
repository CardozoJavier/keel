#!/bin/bash
# Tests for the gh shim (push guard layer A, rules A4-A6; contracts/push-guard.md).
# A fake real gh (KEEL_REAL_GH) records argv and serves `alias list`, so nothing reaches GitHub.
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
SHIM="$KEEL_PLUGIN_ROOT/shims/gh"
CASES="$KEEL_TESTS_ROOT/guard/shims/cases"
w=$(t_tmp)
cat > "$w/fake-gh" <<'FAKE'
#!/bin/sh
if [ "$1" = "alias" ] && [ "$2" = "list" ]; then
  printf 'co: pr checkout\nmkpr: pr create --fill\nshellish: '"'"'!echo hi'"'"'\n'
  exit 0
fi
echo "REALGH $*"
FAKE
chmod +x "$w/fake-gh"
printf 'mutation M { mergePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }\n' > "$w/mutation.graphql"
printf 'query Q { viewer { login } }\n' > "$w/query.graphql"
export KEEL_REAL_GH="$w/fake-gh"
unset KEEL_SHIM_DEPTH

while IFS="$(printf '\t')" read -r rule args; do
  case "$rule" in ''|'#'*) continue ;; esac
  eval "set -- $args"
  out=$(cd "$w" && "$SHIM" "$@" </dev/null 2>&1); rc=$?
  assert_eq 2 "$rc" "deny [$args] exits 2"
  assert_contains "$out" "keel: blocked publish ($rule)" "deny [$args] reports $rule"
  assert_not_contains "$out" "REALGH" "deny [$args] never reaches the real gh"
done < "$CASES/gh-deny.tsv"

while IFS="$(printf '\t')" read -r note args; do
  case "$note" in ''|'#'*) continue ;; esac
  eval "set -- $args"
  out=$(cd "$w" && "$SHIM" "$@" 2>&1); rc=$?
  assert_eq 0 "$rc" "allow [$note] exits 0 (out: $out)"
  assert_contains "$out" "REALGH $*" "allow [$note] passes argv unchanged"
done < "$CASES/gh-allow.tsv"

# drift: every command the installed gh lists is known to the shim (allowed or explicitly denied)
if command -v gh >/dev/null 2>&1 && [ "$(command -v gh)" != "$SHIM" ]; then
  known=$("$SHIM" --keel-list-known 2>/dev/null)
  for c in $(gh --help 2>&1 | awk '/^(CORE|GITHUB ACTIONS|ADDITIONAL) COMMANDS/{s=1;next} /^[A-Z]/{s=0} s && /^  [a-z][a-z-]*:/{sub(/^  /,""); sub(/:.*/,""); print}'); do
    assert_contains " $known " " $c " "gh command '$c' is classified by the shim"
  done
fi

t_summary
