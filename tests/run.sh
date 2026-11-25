#!/bin/bash
# Runs keel's test suites: every *_test.sh under tests/ (or $KEEL_TESTS_DIR).
#   tests/run.sh          fast suites (excludes slow/ and eval/)
#   tests/run.sh --slow   also tests/slow/ (needs JDK + Maven)
#   tests/run.sh --eval   also tests/eval/ (claude plugin eval smoke)
#   tests/run.sh --scenarios   also tests/scenarios/ (real claude -p sessions; costs model usage)
set -u
root=${KEEL_TESTS_DIR:-$(cd "$(dirname "$0")" && pwd)}
slow=0 eval=0 scn=0
for a in "$@"; do
  case "$a" in
    --slow) slow=1 ;;
    --eval) eval=1 ;;
    --scenarios) scn=1 ;;
    *) printf 'usage: %s [--slow] [--eval] [--scenarios]\n' "$0" >&2; exit 1 ;;
  esac
done

suites=0 failed=0 failed_names=
for t in $(find "$root" \( -name '*_test.sh' -o -name '*_scenario.sh' \) -type f | LC_ALL=C sort); do
  rel=${t#"$root"/}
  case "$rel" in
    slow/*) [ "$slow" -eq 1 ] || continue ;;
    eval/*) [ "$eval" -eq 1 ] || continue ;;
    scenarios/*) [ "$scn" -eq 1 ] || continue ;;
  esac
  suites=$((suites + 1))
  printf '== %s\n' "$rel"
  if /bin/bash "$t"; then :; else
    failed=$((failed + 1))
    failed_names="$failed_names $rel"
  fi
done
printf 'suites=%d failed=%d%s\n' "$suites" "$failed" "${failed_names:+ ($failed_names )}"
[ "$failed" -eq 0 ]
