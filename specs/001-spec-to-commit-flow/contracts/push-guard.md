# Contract: Push Guard (three layers)

Implements FR-022, SC-002 and constitution I (v1.3.0).

## Scope

**Blocked: publishing only.** That means:
- sending commits or refs to a remote;
- creating, merging or reopening a pull request, or updating its branch.

**Allowed:**
- Local git: commit, stash (including `stash push`), rebase (including `-x` with non-publishing
  commands), reset, cherry-pick, merge, tag, fetch, pull, clone, branch, worktree.
- PR metadata edits (`gh pr edit`, comments, reviews).

## Threat model

- **Defended against:** an assistant that publishes by mistake, because an instruction told it to
  (including a host instruction or a prompt-injected one), or through ordinary indirection such as
  aliases, functions, scripts, hooks, wrappers and tools that spawn git.
- **Not defended against:** an adaptive adversary that writes and runs code built to defeat the
  guard. Residuals are listed under Known limits.

## Verified facts (2026-11-25, probe plugin in `claude -p`, git 2.54, macOS)

- **PATH order**
  - The Bash tool runs zsh with Claude Code's shell snapshot loaded; `gp` is `git push`.
  - A plugin's `bin/` is appended to PATH.
  - A SessionStart hook writing to `CLAUDE_ENV_FILE` can prepend to PATH. A shim placed this way
    received `gp --dry-run` as `push --dry-run`.
- **Where shims don't help**
  - git puts its own exec-path first for every process it spawns: hooks, `!` aliases,
    `rebase -x`, `submodule foreach`, `bisect run`, externals, pagers and editors. Inside them,
    `git` is the real binary, not the shim.
  - Login shells (`bash -lc`, `zsh -lc`) run `path_helper`, which moves the shims to the end of
    PATH.
  - `xcrun git` and `env -P <dir> git` don't use the caller's PATH.
- **What does work**
  - Environment config (`GIT_CONFIG_COUNT/KEY/VALUE`) is inherited by *every* git process,
    including all of the cases above.
  - A config-defined `pre-push` hook (`hook.<name>.event` + `hook.<name>.command`) blocked
    `git push` in every case listed above, plus absolute paths. `--no-verify` skips it.
  - An empty-prefix `url.keel-blocked-push://.pushInsteadOf=` rewrites every push URL (remote
    names, explicit paths, https). The push then fails **even with `--no-verify`**, while fetch,
    ls-remote and clone keep working.
  - The empty-prefix rewrite loses to a longer `pushInsteadOf` prefix in file config, to an
    empty-prefix rule in file config (which wins a tie), and to an explicit
    `remote.<name>.pushurl`, which git uses without rewriting.
  - Plumbing (`git send-pack <url>`, `git http-push`) skips both the pre-push hook and the
    rewrite. Only A and B cover it.
  - `hook.keel-nopush.enabled=true` from the environment beats a file-config `false`.
  - `git hook list pre-push` lists `keel-nopush`, which proves both git support and enablement.
  - `git remote get-url --push <r>` shows the rewritten `keel-blocked-push://…` URL, or the real
    URL when a pushurl or a longer rule wins.
- **Other facts**
  - `CLAUDE_PLUGIN_ROOT` is absent in the Bash tool.
  - `/usr/bin/git` is an xcrun trampoline, about 10 ms per exec.
  - `git --list-cmds=main,others` costs about 16 ms per call.

## Layer A0 (primary for git): git-level block through environment config

### Installation

The `SessionStart` hook `${CLAUDE_PLUGIN_ROOT}/hooks/session-env.sh` appends to `$CLAUDE_ENV_FILE`.
- **Starting index**: if `GIT_CONFIG_COUNT` is already set in the hook's environment, keel's
  entries start at index N and the count becomes N+4. Otherwise they start at index 0.
- **Idempotent**: `session-env.sh`, `keel-verify` and `keel-evidence` (which re-export the
  environment for the commands they spawn) first look for keel's keys among the existing
  `GIT_CONFIG_KEY_*`. They never append them twice.

```sh
export GIT_CONFIG_COUNT=<N+4>
export GIT_CONFIG_KEY_<N>=hook.keel-nopush.event          GIT_CONFIG_VALUE_<N>=pre-push
export GIT_CONFIG_KEY_<N+1>=hook.keel-nopush.command      GIT_CONFIG_VALUE_<N+1>=<plugin-root>/hooks/deny-push
export GIT_CONFIG_KEY_<N+2>=hook.keel-nopush.enabled      GIT_CONFIG_VALUE_<N+2>=true
export GIT_CONFIG_KEY_<N+3>=url.keel-blocked-push://.pushInsteadOf  GIT_CONFIG_VALUE_<N+3>=
export KEEL_ROOT=<plugin-root> KEEL_SHIMS=<plugin-root>/shims
export KEEL_REAL_GIT=<first non-shim git on PATH, resolved> KEEL_REAL_GH=<same for gh>
export PATH="<plugin-root>/shims:$PATH"
```

### Pieces

- `hooks/deny-push` prints `keel: blocked publish (A0): …` and exits 1.
- `shims/git-remote-keel-blocked-push` is a remote helper that git finds through PATH. It prints
  the same message and exits 1, so the rewritten URL fails with a clear reason. Without it the
  push still fails, with "not a git command".
- **Combined effect**: every `git push` started from the Bash tool fails, however it was started,
  unless a pushurl or a longer file-config rule defeats the rewrite (the self-check catches those)
  and `--no-verify` also skips the hook.
- **Plumbing**: `send-pack` and `http-push` are covered only by A and B.
- **`--no-verify`**: it skips only the hook. The URL rewrite still blocks the push.

### Self-check

This is a functional check, not a presence check. `keel-state` exits 5 with
`MISSING=push-guard:<what>` unless all of these hold:
1. `git hook list pre-push` lists `keel-nopush` without a `disabled` prefix. This also proves the
   installed git supports config-defined hooks.
2. For every remote `r`, every line of `git remote get-url --push --all <r>` starts with
   `keel-blocked-push://`. This catches pushurl and longer or tying `pushInsteadOf` rules.
3. It must not pass vacuously in a repo with no remotes:
   - `git config --show-scope --get-regexp '^url\..*\.pushinsteadof$'` lists only keel's
     `command`-scope entry (verified on 2.54: it prints
     `command url.keel-blocked-push://.pushinsteadof`);
   - `git config --get-regexp '^remote\..*\.pushurl$'` is empty.
4. `command -v git` resolves into `$KEEL_SHIMS`.

Every step skill runs that check, so a keel run never proceeds partly guarded.

## Layer A (primary for gh and other tools; early, clear denial for git): execution-time shims

### Shims

`shims/` holds:
- `git`, `gh`;
- `jj`, `sl`, `gt`, `glab`, `hub`;
- `git-remote-keel-blocked-push`.

### What each shim does

1. **Find the real binary.**
   - `$KEEL_REAL_<TOOL>` if executable.
   - Otherwise a PATH search that skips:
     - empty and relative entries;
     - the shim's own resolved directory;
     - any entry whose candidate carries the keel shim marker line.
   - The candidate must be a regular file (`-f`) and executable (`-x`).
   - None found: exit 127.
   - `KEEL_SHIM_DEPTH` is incremented on every exec. Above 3 the shim exits 2 with rule `AF`
     (recursion).
2. **Parse argv.** It is final: aliases, functions, variables, globs and `eval` were already
   expanded by the shell.
   - **git global options** are skipped: `-C`, `-c`, `--git-dir[=]`, `--work-tree[=]`,
     `--namespace[=]`, `--exec-path[=]`, `--config-env=`, `-P`, `--no-pager`, `--paginate`,
     `--bare`, `--no-replace-objects`, `--*-pathspecs`, `--no-optional-locks`, `--no-advice`.
   - **Builtin subcommands** come from an embedded list, generated from `git --list-cmds=main` at
     build time and checked by a test. `--list-cmds` runs only for unknown words.
   - **Aliases** resolve through `$KEEL_REAL_GIT <same global opts> config --get alias.<x>`,
     recursively, at most 5 levels.
     - The real git sees `-c alias.*`, `--config-env` and `GIT_CONFIG_*`, so those are covered.
     - A `!shell` alias's inner git calls run under git's exec-path, where **A0** covers them.
3. **Deny (exit 2)**, with `keel: blocked publish (<rule>): <argv>. Run it yourself if
   intended.` on stderr, when the resolved command matches:

| Rule | Resolved command |
|---|---|
| A1 | `git push`, `send-pack`, `http-push`, `send-email`, `imap-send` (`request-pull` is allowed: it only prints) |
| A2 | `git svn dcommit\|set-tree`, `git p4 submit`, `git lfs push`, `git subtree push` |
| A3 | `git remote-<helper>` or `receive-pack` invoked as a subcommand |
| A4 | `gh pr create\|new\|merge\|update-branch\|revert\|reopen\|ready`, `gh repo sync`, `gh repo create … --push`, `gh release create` |
| A5 | `gh api` with a write method (`-X`, `-XPOST`, `--method[=]` POST/PUT/PATCH/DELETE, or `-f`/`-F`/`--field`/`--raw-field`/`--input`) on `^/?(api/v3/)?repos/[^/]+/[^/]+/(pulls\|pulls/[0-9]+/(merge\|update-branch)\|git/(refs\|commits\|trees\|blobs\|tags)(/.*)?\|contents/.*\|merges\|merge-upstream)$`; `PATCH …/pulls/N` with `state=open`; `gh api graphql` whose query (inline, or `query=@file`, which is read; unreadable → deny) names `createPullRequest mergePullRequest updatePullRequestBranch revertPullRequest reopenPullRequest enqueuePullRequest enablePullRequestAutoMerge createCommitOnBranch createRef updateRef updateRefs mergeBranch` |
| A6 | `gh` subcommand that isn't core (`alias api attestation auth browse cache codespace completion config extension gist gpg-key issue label org pr project release repo ruleset run search secret ssh-key status variable workflow`), after `$KEEL_REAL_GH alias list` resolution; extensions and unknown → deny; `gh --version`, `gh version`, `gh help` pass |
| A7 | `jj git push`, `sl push`/`sl pr`, `gt submit`/`gt sync`, `glab mr create\|merge`, `hub push`/`hub pull-request` |
| A8 | weakening A0: `git config` writes to `url.*.pushinsteadof`, `url.*.insteadof`, `remote.*.pushurl`, `hook.*` or `include*`; `git remote set-url --push`/`--add --push`; `-c`/`--config-env` setting those keys or `core.hooksPath` |

4. Otherwise `exec` the real binary with the original argv.

### Failure handling

- Fail closed: an internal error (trap ERR) or an unresolvable alias exits 2 with rule `AF`.
- Layer A covers everything that resolves `gh`, `jj` and the other tools through PATH, and gives an
  early, clear denial for `git`. A0 is the backstop for git wherever the shim is bypassed.

## Layer B: static PreToolUse guard (`hooks/guard-push.sh`)

**Role**: catch the visible forms that skip PATH (needed for `gh` and the non-git tools, which A0
doesn't cover), attempts to weaken A0, and non-shell tools.

### Registration (`hooks/hooks.json`, anchored matchers, `onFailure: "block"`, timeout 10 s)

| Matcher | Mode |
|---|---|
| `^(Bash\|Monitor\|PowerShell)$` | shell; Monitor calls without `command` (ws mode) pass |
| `^mcp__.*github.*__.*$` | `--github-mcp`: allow `^(get\|list\|search)_` and the named non-publishing writes `add_issue_comment`, `create_issue`, `update_issue`, `add_comment_to_pending_review`, `create_pending_pull_request_review`, `submit_pending_pull_request_review`, `request_copilot_review`; deny the rest |
| `^mcp__codex__codex$` | `--codex`: deny if `sandbox` is `danger-full-access`, or `config` sets `sandbox_mode` or enables network; with `sandbox` absent, use `sandbox_mode` from `${CODEX_HOME:-~/.codex}/config.toml` (unreadable → deny) |
| `^mcp__codex__codex-reply$` | allow |
| `PreSkillShellCommand` event (if its payload carries the command; verification item 7) | shell |

### Shell mode

1. **Extract `tool_input.command`** with `lib/json.sh`. It decodes ASCII `\u00XX` only. A parse
   failure or missing field denies (F1).
2. **Tokenize** in one awk pass under `LC_ALL=C`.
   - Split simple commands on `; && || | & ( ) { }` and newlines.
   - `$( … )`, backticks and `<( … )` are parsed recursively.
   - Skip reserved words: `if then elif else fi while until for in do done case esac select
     function ! time coproc`.
   - Skip leading redirections, `VAR=value` assignments and zsh precommand modifiers (`noglob`,
     `nocorrect`, `-`, `builtin`, `command`, `exec`).
   - Here-document bodies are data, unless they are fed to a shell or interpreter (rule B4).
3. **Normalize the command word.**
   - Drop a leading `\` or zsh `=`.
   - Take the basename, and read `git-<x>` as `git <x>`.
   - Unwrap wrappers to the command they run: `xcrun`, `env` (all options, including `-P`, `-S`,
     `-i`, `-u`), `sudo`, `nice`, `nohup`, `time`, `timeout`, `caffeinate`, `arch`, `script`,
     `direnv exec`, `mise exec`, `ssh <host> <cmd>`, `xargs` (the command after its options),
     `find … -exec|-execdir|-ok`, and `keel-evidence run … --`.

### Deny rules

| Rule | Matches |
|---|---|
| B1 | after unwrapping, a path to `git`, `gh`, `jj`, `sl`, `gt`, `glab` or `hub`, or a `xcrun`/`env -P` invocation of them: A1–A8 applied to the visible argv |
| B2 | shim or A0 tampering:<br>• `command -p` with those tools;<br>• `env -i`, `env -u PATH`, `unset PATH` or `hash -p` in a command that names them;<br>• a `PATH=`/`export PATH=` assignment whose resulting PATH leaves out `$KEEL_SHIMS`, or puts before it a directory holding an executable `git`, `gh`, `jj`, `sl`, `gt`, `glab` or `hub` (checked with `-x` at hook time). So `export PATH=$JAVA_HOME/bin:$PATH` passes, because that directory holds none of those tools. For an entry that can't be expanded at hook time (`$(…)`, or a variable neither assigned literally in the same command nor set in the hook's environment), deny only if the same command names one of the tools, runs a script, or has an unresolved command word;<br>• assignment, `export`, `unset` or `env -u` of `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_*`, `GIT_CONFIG_VALUE_*`, `GIT_CONFIG_PARAMETERS`, `KEEL_*` or `GIT_EXEC_PATH`. `GIT_CONFIG_NOSYSTEM` and `GIT_CONFIG_GLOBAL` pass;<br>• the git config writes and `-c` keys of rule A8 when the git invocation bypasses the shim (B1). Plain text mentions (e.g. `rg pushInsteadOf docs/`) are not matched |
| B3 | a literal publish command (A1–A7 on the visible argv), including `--no-verify` forms |
| B4 | literal payloads parsed recursively with the same rules: `sh\|bash\|zsh\|dash\|ksh` with `-c`, `-lc`, `--login -c` or `-ic`; here-documents and here-strings fed to them; `git rebase -x/--exec`, `git submodule foreach`, `git bisect run`, `-c alias.*=!…`, `-c core.pager\|core.editor\|sequence.editor\|diff.external\|core.sshCommand=` |
| B5 | an unresolved command word (`$…`, backtick, `$(…)`) in a simple command whose other words match the publish vocabulary V1 |
| W1 | `curl`, `wget`, `http`, `xh` with a write method or data flag to: A5 endpoints on `api.github.com` or `*/api/v3/`; `api.bitbucket.org/2.0/repositories/*/*/pullrequests` (POST) and `…/merge`; `*/api/v4/projects/*/merge_requests` (POST) and `…/merge`; `*/repository/commits` (POST); `*/git-receive-pack` |
| W2 | non-shell interpreters with inline code (`python* -c`, `node -e`, `perl -e`, `ruby -e`, `osascript -e`) whose code matches V1 |
| F1 | JSON parse failure or missing command |
| F2 | internal error (trap ERR); `onFailure: "block"` covers crashes and timeouts |

**V1**:
- The pattern is
  `(^|[^A-Za-z0-9_])(push|send-pack|receive-pack|http-push|pullrequests?|pull_request|merge_requests?|createPullRequest|mergePullRequest|createCommitOnBranch|dcommit|submit)([^A-Za-z0-9_]|$)`.
- It uses explicit boundary classes, because `\b` is unsupported in BSD awk and bash 3.2.
- It applies only in B5 and W2. B5 requires an unresolved command word, so
  `rg -l push | xargs sed …` is not affected.

## Allow corpus (excerpt; full set in `tests/guard/cases/allow/`)

```text
git status
git commit -m "push notifications"
git commit -m "$(cat <<'EOF' … push … EOF)"
git stash push -m wip
git stash pop
git rebase -i main
git rebase -x 'mvn -q test' HEAD~3
git reset --hard HEAD~1
git cherry-pick abc
git fetch
git pull --rebase
git ls-remote origin
git clone <url>
git lfs pull
git tag v1
git -C ../x status
git log --grep=push
eval "$(ssh-agent -s)"
"$MVN" test
bash -lc 'mvn test'
mvn -q verify
./mvnw test
rg -l push | xargs sed -n 1p
gh pr view 3
gh pr list
gh pr checks
gh pr edit 3 --title x
gh api repos/o/r/pulls
gh api repos/o/r/pulls/3/comments -f body=x
gh --version
GitHub MCP get_pull_request
mcp__codex__codex-reply
Monitor (ws mode)
```

## Deny corpus (excerpt; full set in `tests/guard/cases/deny/`, each case tagged with its expected layer)

**A0 (git process level, run with only the A0 environment and no shims)**:

```text
git push
/usr/bin/git push
xcrun git push
env -P /usr/bin git push
zsh -lc 'git push'
bash -lc 'git push'
git -c alias.x='!git push origin main' x
a post-commit, pre-commit or reference-transaction hook running git push
git rebase -x 'git push origin HEAD:refs/heads/main' HEAD~1
git submodule foreach 'git push'
git bisect run sh -c 'git push'
git push --no-verify (URL rewrite)
a file-config hook.keel-nopush.enabled=false (env true wins; the hook still fires)
self-check failures (exit 5) for: a remote with pushurl, a longer repo-level pushInsteadOf, a git without config hooks (simulated)
```

**A (shims)**:

```text
gp
gpsup
ggpush
ggp
git -c alias.p=push p
GIT_CONFIG_COUNT-based alias
x=push; git $x
git ${x}sh
git {push,}
git pu\sh
echo 'git push' | sh
source f
$(cat f)
xargs git < args
if true; then git push; fi
! git push
{ git push; }
>/dev/null git push
caffeinate git push
keel-evidence run … -- git push
./deploy.sh
make release
mvn release:prepare (A0 too)
gh pr create
gh pr new
gh pr merge 3
gh pr update-branch
gh pr revert 3
gh pr reopen 3
gh repo sync
git send-pack <url> main (A and B; not A0)
git remote set-url --push origin <url>
git config remote.origin.pushurl <url>
gh api -XPOST repos/o/r/pulls -f title=x
gh api -X PATCH repos/o/r/pulls/3 -f state=open
gh api graphql -f query='mutation{createPullRequest…}'
gh api graphql -F query=@q.graphql (mutation inside)
git config url.x.pushInsteadOf y
git -c core.hooksPath=/tmp/h push
```

**B**:

```text
/opt/homebrew/bin/gh pr create
xcrun gh pr create
zsh -lc 'gh pr create'
G=/opt/homebrew/bin/gh; $G pr create
GIT_CONFIG_COUNT=0 git push
env -u GIT_CONFIG_COUNT git push
unset GIT_CONFIG_COUNT
export PATH=/usr/bin:$PATH; gh pr create
curl -X POST https://api.github.com/repos/o/r/pulls -d …
curl … https://ghe.example/api/v3/repos/o/r/pulls -d …
python3 -c "…git push…"
GitHub MCP create_pull_request, merge_pull_request, push_files, create_or_update_file, update_pull_request_branch
mcp__codex__codex with sandbox danger-full-access
malformed JSON
empty stdin
```

## Performance

- **Layer B**: p95 < 50 ms on the allow corpus. Measured with bash 3.2 `TIMEFORMAT=%3R; time …`.
- **Layer A**: < 15 ms added per git/gh call.
  - It execs `$KEEL_REAL_GIT` directly, skipping the xcrun trampoline when it resolved to the CLT
    binary.
  - It uses the embedded builtin list, with no `--list-cmds` on known subcommands.
- **A0**: no cost until a push is attempted.

## Enablement, degraded mode, escape hatch

- **Enablement**: `plugin.json` has `"defaultEnabled": false`, and keel is enabled per repository.
  In those sessions, `/ship` and `/steward` can't push.
- **Degraded mode**:
  - If SessionStart didn't run in a session (e.g. keel was enabled mid-session through
    `/reload-plugins`), only layer B is active for ordinary turns.
  - Every keel step halts on the self-check, so keel runs never proceed degraded.
  - The quickstart says to start a new session after enabling keel.
- **Escape hatch**: `claude --settings '{"disableAllHooks": true}'`. No keel hooks, shims or A0 run
  in that session.

## Known limits (stated, not silent)

- A program that speaks the git or forge protocol itself, without the git binary (JGit, a custom
  HTTP client), is not caught; W1/W2 catch only its visible forms.
- A file-hidden `git push --no-verify` to a remote with a `pushurl`, or whose URL matches a
  longer or tying file-config `pushInsteadOf`: the self-check halts keel runs when such a remote
  exists, but ordinary turns are not protected against it.
- File-hidden plumbing (`send-pack`, `http-push`) run through a path that skips the shim (a hook,
  a `!` alias, an absolute path inside a script). A0 doesn't cover plumbing.
- A hidden `gh` publish through an absolute path or a login shell inside a script file (A6/A4 are
  shim-only there, and A0 doesn't apply to gh).
- User `!` commands: covered by A0 and A if Claude Code gives them the session env (verification
  item 1). The developer can always push from their own terminal.
