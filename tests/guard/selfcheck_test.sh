#!/bin/bash
# Functional guard self-check (plugin/lib/guard-check.sh, contracts/push-guard.md §Self-check):
# passes only when A0 works (hook listed+enabled, every push URL rewritten, no foreign
# pushInsteadOf, no pushurl) and the git shim is first on PATH.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
home=$(t_tmp)
export HOME="$home" XDG_CONFIG_HOME="$home/.config" GIT_CONFIG_NOSYSTEM=1 KEEL_ROOT="$KEEL_PLUGIN_ROOT"
unset GIT_CONFIG_COUNT KEEL_SHIM_DEPTH

remote=$(mk_bare_remote)
r=$(mk_repo); git -C "$r" remote add origin "$remote"; git -C "$r" commit -q --allow-empty -m one
check() { # [extra shell before the check] → "rc out"
  out=$(cd "$r" && /bin/sh -c ". '$KEEL_PLUGIN_ROOT/hooks/keel-env.sh'; ${1:-:}; /bin/bash -c \". '$KEEL_PLUGIN_ROOT/lib/guard-check.sh'; keel_guard_check\"" 2>&1); echo "$? $out"
}

assert_eq "0 " "$(check)" "passes with the full guard environment"
git -C "$r" config hook.keel-nopush.enabled false
assert_eq "0 " "$(check)" "file-config enabled=false loses to the environment (still passes)"
git -C "$r" config --unset hook.keel-nopush.enabled

assert_contains "$(check 'GIT_CONFIG_COUNT=0')" "5 MISSING=push-guard:pre-push-hook" "A0 hook missing fails"
git -C "$r" config remote.origin.pushurl "$remote"
assert_contains "$(check)" "MISSING=push-guard:" "explicit pushurl fails"
git -C "$r" config --unset remote.origin.pushurl
git -C "$r" config "url.$remote.pushInsteadOf" "$remote"
assert_contains "$(check)" "MISSING=push-guard:" "longer pushInsteadOf fails"
git -C "$r" config --unset "url.$remote.pushInsteadOf"
git -C "$r" config "url.$home/.pushInsteadOf" ""
assert_contains "$(check)" "MISSING=push-guard:" "tying empty-prefix pushInsteadOf fails"
git -C "$r" remote remove origin
assert_contains "$(check)" "MISSING=push-guard:foreign-pushinsteadof" "with no remotes, a file-config pushInsteadOf still fails"
git -C "$r" config --unset "url.$home/.pushInsteadOf"
assert_eq "0 " "$(check)" "no remotes and no foreign rules passes"
git -C "$r" config remote.other.pushurl /x
assert_contains "$(check)" "MISSING=push-guard:push" "a pushurl on any remote fails (push-url or pushurl check)"
git -C "$r" config --unset remote.other.pushurl
assert_contains "$(check 'PATH=/usr/bin:/bin')" "MISSING=push-guard:git-shim" "git shim not first on PATH fails"
# a git without config hooks: simulate with a fake real git whose 'hook list' is unknown
mkdir -p "$home/oldgit"; printf '#!/bin/sh\n[ "$1" = hook ] && { echo "git: '"'"'hook'"'"' is not a git command" >&2; exit 1; }\nexec /usr/bin/git "$@"\n' > "$home/oldgit/git"; chmod +x "$home/oldgit/git"
assert_contains "$(check "KEEL_REAL_GIT=$home/oldgit/git; export KEEL_REAL_GIT")" "MISSING=push-guard:pre-push-hook" "git without config hooks fails"
t_summary
