#!/bin/bash
# Tests for plugin/lib/shim-common.sh: finding the real binary behind a keel shim, and the
# recursion guard (contracts/push-guard.md, layer A step 1).
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"
LIB="$KEEL_PLUGIN_ROOT/lib/shim-common.sh"

d=$(t_tmp)
mkdir -p "$d/real" "$d/real2" "$d/shim1" "$d/shim2" "$d/dirtool/git" "$d/noexec"
printf '#!/bin/sh\necho real\n' > "$d/real/git"; chmod +x "$d/real/git"
printf '#!/bin/sh\necho real2\n' > "$d/real2/git"; chmod +x "$d/real2/git"
printf '#!/bin/sh\n# keel-shim: never resolve to this file as the real binary\n' > "$d/shim1/git"; chmod +x "$d/shim1/git"
cp "$d/shim1/git" "$d/shim2/git"
printf '#!/bin/sh\necho noexec\n' > "$d/noexec/git"
real() { # <PATH> [env assignments...] → resolved path or exit code
  local p=$1; shift
  env -u KEEL_REAL_GIT "$@" PATH="$p" /bin/bash -c ". '$LIB'; keel_shim_real git '$d/shim1'" 2>/dev/null || echo "rc=$?"
}

assert_eq "$d/real/git" "$(real "$d/shim1:$d/real")" "skips the shim's own directory"
assert_eq "$d/real/git" "$(real "$d/shim1:$d/shim2:$d/real")" "skips a second keel shim directory (marker)"
assert_eq "$d/real/git" "$(real ":relative:./x:$d/shim1:$d/real")" "skips empty and relative PATH entries"
assert_eq "$d/real/git" "$(real "$d/dirtool:$d/noexec:$d/real")" "skips a directory named git and a non-executable file"
assert_eq "$d/real2/git" "$(real "$d/shim1:$d/real" KEEL_REAL_GIT="$d/real2/git")" "KEEL_REAL_GIT wins when valid"
assert_eq "$d/real/git" "$(real "$d/shim1:$d/real" KEEL_REAL_GIT="$d/shim2/git")" "KEEL_REAL_GIT pointing at a shim is ignored"
assert_eq "$d/real/git" "$(real "$d/shim1:$d/real" KEEL_REAL_GIT="$d/missing")" "missing KEEL_REAL_GIT falls back to PATH"
assert_eq "rc=127" "$(real "$d/shim1:$d/shim2")" "no real binary exits 127"

# symlinked shim directory is still recognized as the shim's own
ln -s "$d/shim1" "$d/shimlink"
assert_eq "$d/real/git" "$(real "$d/shimlink:$d/real")" "symlink to the shim directory is skipped"

# recursion guard
out=$(KEEL_SHIM_DEPTH=3 /bin/bash -c ". '$LIB'; keel_shim_enter git push; echo after" 2>&1); rc=$?
assert_eq 2 "$rc" "depth above 3 exits 2"
assert_contains "$out" "keel: blocked publish (AF)" "recursion is reported as AF"
assert_not_contains "$out" "after" "nothing runs after the recursion stop"
out=$(KEEL_SHIM_DEPTH=1 /bin/bash -c ". '$LIB'; keel_shim_enter git status; echo \$KEEL_SHIM_DEPTH")
assert_eq "2" "$out" "depth is incremented and exported"

# deny message format
out=$(/bin/bash -c ". '$LIB'; keel_shim_deny A1 git push origin main" 2>&1); rc=$?
assert_eq 2 "$rc" "keel_shim_deny exits 2"
assert_eq "keel: blocked publish (A1): git push origin main. Run it yourself if intended." "$out" "deny message format"

t_summary
