#!/bin/bash
# Push guard layer A0 (contracts/push-guard.md): environment git config that every git process
# inherits: a config-defined pre-push hook plus an empty-prefix pushInsteadOf rewrite. Every push
# form must fail with only the A0 environment (no shims on PATH); fetch/ls-remote/clone keep working.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
ENVSH="$KEEL_PLUGIN_ROOT/hooks/keel-env.sh"
SESSION="$KEEL_PLUGIN_ROOT/hooks/session-env.sh"
home=$(t_tmp)
export HOME="$home" XDG_CONFIG_HOME="$home/.config" GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT KEEL_SHIM_DEPTH

# --- keel-env.sh: entries, idempotency, appending after existing entries ------------------------
out=$(env -u GIT_CONFIG_COUNT KEEL_ROOT="$KEEL_PLUGIN_ROOT" /bin/sh -c ". '$ENVSH'; . '$ENVSH'; echo \$GIT_CONFIG_COUNT; echo \$GIT_CONFIG_KEY_0=\$GIT_CONFIG_VALUE_0; echo \$GIT_CONFIG_KEY_3=\$GIT_CONFIG_VALUE_3; echo \$PATH")
assert_eq 5 "$(printf '%s\n' "$out" | sed -n 1p)" "five entries, sourcing twice adds nothing"
assert_eq "hook.keel-nopush.event=pre-push" "$(printf '%s\n' "$out" | sed -n 2p)" "pre-push hook event entry"
assert_eq "url.keel-blocked-push://.pushInsteadOf=" "$(printf '%s\n' "$out" | sed -n 3p)" "empty-prefix pushInsteadOf entry"
assert_eq "$KEEL_PLUGIN_ROOT/shims" "$(printf '%s\n' "$out" | sed -n 4p | cut -d: -f1)" "shims first on PATH"
out=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.x GIT_CONFIG_VALUE_0=y KEEL_ROOT="$KEEL_PLUGIN_ROOT" /bin/sh -c ". '$ENVSH'; echo \$GIT_CONFIG_COUNT \$GIT_CONFIG_KEY_0 \$GIT_CONFIG_KEY_1")
assert_eq "6 user.x hook.keel-nopush.event" "$out" "appends after an existing entry and keeps it"
out=$(KEEL_ROOT="$KEEL_PLUGIN_ROOT" zsh -f -c ". '$ENVSH'; . '$ENVSH'; echo \$GIT_CONFIG_COUNT" 2>&1)
assert_eq 5 "$out" "zsh can source it (the Bash tool's shell here)"

# --- session-env.sh writes the env file ------------------------------------------------------
ef="$home/env-file.sh"
printf '{"hook_event_name":"SessionStart"}' | CLAUDE_ENV_FILE="$ef" CLAUDE_PLUGIN_ROOT="$KEEL_PLUGIN_ROOT" /bin/bash "$SESSION"
assert_eq 0 "$?" "session-env.sh exits 0"
assert_contains "$(cat "$ef")" "KEEL_ROOT=" "env file exports KEEL_ROOT"
assert_contains "$(cat "$ef")" "KEEL_REAL_GIT=" "env file exports KEEL_REAL_GIT"
assert_contains "$(cat "$ef")" "keel-env.sh" "env file sources keel-env.sh"
printf '{}' | env -u CLAUDE_ENV_FILE CLAUDE_PLUGIN_ROOT="$KEEL_PLUGIN_ROOT" /bin/bash "$SESSION"
assert_eq 0 "$?" "session-env.sh without CLAUDE_ENV_FILE exits 0 (layer B only; self-check halts keel runs)"
real_git=$(sed -n "s/^export KEEL_REAL_GIT='\(.*\)'$/\1/p" "$ef")
assert_eq yes "$([ -x "$real_git" ] && echo yes)" "KEEL_REAL_GIT is an executable git ($real_git)"

# --- every push form fails with only A0 (shims deliberately NOT on PATH) ----------------------
remote=$(mk_bare_remote)
r=$(mk_repo)
git -C "$r" remote add origin "$remote"
git -C "$r" commit -q --allow-empty -m one
git -C "$r" commit -q --allow-empty -m two
refs() { git --git-dir="$remote" for-each-ref | wc -l | tr -d ' '; }
a0() { # run a command with only the A0 git config (and keel's helper reachable) in the repo
  ( cd "$r" && env GIT_CONFIG_COUNT= sh -c ". '$ENVSH'; PATH=\${PATH#$KEEL_PLUGIN_ROOT/shims:}; PATH=\$PATH:$KEEL_PLUGIN_ROOT/shims; $1" ) >"$home/a0.out" 2>&1
}
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"
blocked() { # <label> <command>
  a0 "$2"; rc=$?
  assert_eq 0 "$(refs)" "$1: remote unchanged"
  assert_contains "$(cat "$home/a0.out")" "keel: blocked publish (A0)" "$1: reports A0"
}
blocked "plain push" "git push origin main"
blocked "absolute path" "/usr/bin/git push origin main"
command -v xcrun >/dev/null 2>&1 && blocked "xcrun" "xcrun git push origin main"
blocked "env -P" "env -P /usr/bin:/bin git push origin main"
blocked "zsh login shell" "zsh -lc 'git push origin main'"
blocked "bash login shell" "bash -lc 'git push origin main'"
blocked "bang alias" "git -c alias.x='!git push origin main' x"
blocked "no-verify (URL rewrite)" "git push --no-verify origin main"
blocked "explicit URL no-verify" "git push --no-verify '$remote' main"
blocked "rebase -x" "git rebase -x 'git push origin HEAD:refs/heads/main' HEAD~1; git rebase --abort 2>/dev/null; true"
blocked "rebase -x no-verify" "git rebase -x 'git push --no-verify origin HEAD:refs/heads/main' HEAD~1; git rebase --abort 2>/dev/null; true"
blocked "bisect run" "git bisect start HEAD HEAD~1 >/dev/null; git bisect run sh -c 'git push origin HEAD:refs/heads/main; exit 0'; git bisect reset >/dev/null 2>&1; true"
mkdir -p "$r/.git/hooks"
printf '#!/bin/sh\ngit push origin HEAD:refs/heads/main\n' > "$r/.git/hooks/post-commit"; chmod +x "$r/.git/hooks/post-commit"
blocked "post-commit hook" "git commit -q --allow-empty -m three"
rm "$r/.git/hooks/post-commit"
printf '#!/bin/sh\ngit push origin HEAD:refs/heads/main\nexit 0\n' > "$r/.git/hooks/pre-commit"; chmod +x "$r/.git/hooks/pre-commit"
blocked "pre-commit hook" "git commit -q --allow-empty -m four"
rm "$r/.git/hooks/pre-commit"
git -C "$r" config hook.keel-nopush.enabled false
blocked "file-config enabled=false loses to the env" "git push origin main"
git -C "$r" config --unset hook.keel-nopush.enabled
# submodule foreach
sub=$(mk_repo); git -C "$sub" commit -q --allow-empty -m s; subremote=$(mk_bare_remote)
git -C "$sub" remote add origin "$subremote"
git -C "$r" -c protocol.file.allow=always submodule -q add "$sub" sm >/dev/null 2>&1
git -C "$r/sm" remote set-url origin "$subremote"
a0 "git submodule foreach 'git push origin HEAD:refs/heads/main'"
assert_eq 0 "$(git --git-dir="$subremote" for-each-ref | wc -l | tr -d ' ')" "submodule foreach: submodule remote unchanged"
assert_contains "$(cat "$home/a0.out")" "keel: blocked publish (A0)" "submodule foreach: reports A0"

# --- reads keep working ---------------------------------------------------------------------
git -C "$r" push -q origin HEAD:refs/heads/seed 2>/dev/null   # seed the remote WITHOUT A0
a0 "git fetch -q origin && git ls-remote origin >/dev/null && git clone -q '$remote' '$home/clone'"
assert_eq 0 "$?" "fetch, ls-remote and clone work under A0"

t_summary
