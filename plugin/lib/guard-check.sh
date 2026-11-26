# shellcheck shell=bash
# keel_guard_check: functional self-check of push guard layers A0 and A (contracts/push-guard.md
# §Self-check). Run by `keel-state` before every keel step, so a keel run never proceeds partly
# guarded. Prints MISSING=push-guard:<what> and returns 5 on the first failed check.
# Must run inside the target repository with the session environment (keel-env.sh) applied.
keel_guard_check() {
  local line r url scope key out g
  # 1. the config-defined pre-push hook is listed and enabled (also proves git supports it)
  out=$(git hook list pre-push 2>/dev/null) || { echo "MISSING=push-guard:pre-push-hook"; return 5; }
  local ok=0
  while IFS= read -r line; do
    [ "$line" = "keel-nopush" ] && ok=1
  done <<EOS
$out
EOS
  [ "$ok" -eq 1 ] || { echo "MISSING=push-guard:pre-push-hook"; return 5; }

  # 2. every push URL of every remote is rewritten to the blocked scheme
  for r in $(git remote 2>/dev/null); do
    out=$(git remote get-url --push --all "$r" 2>/dev/null) || { echo "MISSING=push-guard:push-url($r)"; return 5; }
    while IFS= read -r url; do
      case "$url" in keel-blocked-push://*) ;; *) echo "MISSING=push-guard:push-url($r)"; return 5 ;; esac
    done <<EOS
$out
EOS
  done

  # 3. no pushInsteadOf other than keel's command-scope one (it would beat keel's rewrite), and
  #    no pushurl anywhere: checked even without remotes, so the check never passes vacuously
  out=$(git config --show-scope --get-regexp '^url\..*\.pushinsteadof$' 2>/dev/null)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    scope=${line%%	*}
    key=${line#*	}; key=${key%% *}
    if [ "$scope" != "command" ] || [ "$key" != "url.keel-blocked-push://.pushinsteadof" ]; then
      echo "MISSING=push-guard:foreign-pushinsteadof"; return 5
    fi
  done <<EOS
$out
EOS
  if [ -n "$(git config --get-regexp '^remote\..*\.pushurl$' 2>/dev/null)" ]; then
    echo "MISSING=push-guard:pushurl"; return 5
  fi

  # 4. layer A: `git` resolves to keel's shim
  g=$(command -v git 2>/dev/null)
  case "$g" in "${KEEL_SHIMS:-/nonexistent}"/git) ;; *) echo "MISSING=push-guard:git-shim"; return 5 ;; esac
  return 0
}
