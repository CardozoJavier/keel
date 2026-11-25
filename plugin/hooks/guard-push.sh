#!/bin/bash
# keel push guard, layer B: static PreToolUse guard (contracts/push-guard.md).
# Catches what bypasses PATH (and so layer A), attempts to weaken A0/A, literal publish commands
# (early, clear denials), literal shell payloads parsed recursively, forge HTTP writes and inline
# interpreter payloads. Publish rules for git/gh/jj/sl/gt/glab/hub are not re-implemented here: the
# shims are called in check-only mode (KEEL_SHIM_CHECK=1), so both layers apply the same rules.
# Exit 0 allows; exit 2 denies with the reason on stderr. Anything this script can't decide is
# denied (F1/F2); hooks.json adds onFailure: "block" for crashes and timeouts.
# Modes: (default) shell tools; --github-mcp; --codex. bash 3.2.
set -u

root=${CLAUDE_PLUGIN_ROOT:-}
[ -n "$root" ] || root=$(cd -P "$(dirname "$0")/.." 2>/dev/null && pwd)
KEEL_ROOT=${KEEL_ROOT:-$root}
. "$root/lib/json.sh" || { echo "keel: blocked publish (F2): guard library missing" >&2; exit 2; }
. "$root/lib/shell-tokens.sh" || { echo "keel: blocked publish (F2): guard library missing" >&2; exit 2; }

deny() {
  printf 'keel: blocked publish (%s): %s. Run it yourself if intended.\n' "$1" "$2" >&2
  exit 2
}

KEEL_TOOLS=' git gh jj sl gt glab hub '
KEEL_SHELLS=' sh bash zsh dash ksh '
KEEL_PROTECTED_RE='^(GIT_CONFIG_COUNT|GIT_CONFIG_KEY_[0-9]+|GIT_CONFIG_VALUE_[0-9]+|GIT_CONFIG_PARAMETERS|GIT_EXEC_PATH|KEEL_[A-Za-z0-9_]*)$'
KEEL_V1_RE='(^|[^A-Za-z0-9_])(push|send-pack|receive-pack|http-push|pullrequests?|pull_request|merge_requests?|createPullRequest|mergePullRequest|createCommitOnBranch|dcommit|submit)([^A-Za-z0-9_]|$)'
KEEL_GH_REF_RE='^/?(api/v3/)?repos/[^/]+/[^/]+/(pulls|pulls/[0-9]+/(merge|update-branch)|git/(refs|commits|trees|blobs|tags)(/.*)?|contents/.*|merges|merge-upstream)/?$'
KEEL_NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'
KEEL_BB_RE='^/2[.]0/repositories/[^/]+/[^/]+/pullrequests(/[0-9]+/merge)?/?$'
KEEL_GL_RE='/api/v4/projects/[^/]+/(merge_requests(/[0-9]+/merge)?|repository/commits)/?$'
KEEL_RP_RE='/git-receive-pack$'
KEEL_ASSIGN_RE='^([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
KEEL_VAR_RE='\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?'
NLE=$'\036'

input=$(cat) || deny F1 "cannot read the hook payload"
[ -n "$input" ] || deny F1 "empty hook payload"
fields=$(printf '%s' "$input" | keel_json_fields tool_name tool_input.command cwd; printf x) || deny F1 "hook payload is not valid JSON"
fields=${fields%x}
case "$fields" in *$'\036'*$'\036'*$'\036') ;; *) deny F1 "hook payload is not valid JSON" ;; esac
f_tool=${fields%%$'\036'*}; fields=${fields#*$'\036'}
f_cmd=${fields%%$'\036'*}; fields=${fields#*$'\036'}
f_cwd=${fields%%$'\036'*}; fields=${fields#*$'\036'}
[ -z "$fields" ] || deny F1 "hook payload contains a reserved control character"
cwd=$PWD
case "$f_cwd" in S*) [ -d "${f_cwd#S}" ] && cwd=${f_cwd#S} ;; esac
. "$root/lib/git-builtins.sh" 2>/dev/null || KEEL_GIT_BUILTINS=

# ---------------------------------------------------------------------------------------------
# literal assignments seen so far in this command (NAME=value with a literal value)
a_names=() a_vals=()
remember() { a_names+=("$1"); a_vals+=("$2"); }
lookup() { # <name> → value of the latest literal assignment; returns 1 if none
  local i=${#a_names[@]}
  while [ "$i" -gt 0 ]; do
    i=$((i - 1))
    if [ "${a_names[$i]}" = "$1" ]; then printf '%s' "${a_vals[$i]}"; return 0; fi
  done
  return 1
}
# expand <text> [env]: substitute $NAME/${NAME} from literal assignments (and, with "env", from
# the hook's environment). Prints the result; returns 1 if anything unresolved remains.
expand() {
  local s=$1 useenv=${2:-} name val out= guard=0
  while [[ "$s" =~ $KEEL_VAR_RE ]] && [ "$guard" -lt 20 ]; do
    guard=$((guard + 1))
    name=${BASH_REMATCH[1]}
    if val=$(lookup "$name"); then :
    elif [ -n "$useenv" ] && eval "[ -n \"\${$name+x}\" ]"; then eval "val=\${$name}"
    else printf '%s' "$out$s"; return 1
    fi
    out="$out${s%%"${BASH_REMATCH[0]}"*}$val"
    s=${s#*"${BASH_REMATCH[0]}"}
  done
  out="$out$s"
  printf '%s' "$out"
  case "$out" in *'$'* | *'`'*) return 1 ;; esac
  return 0
}
decode() { printf '%s' "${1//$NLE/$'\n'}"; }

# names_tool: true when the whole command text mentions one of the guarded tools as a word,
# runs a path (./x, /x), or has an unresolved command word (used for unexpandable PATH changes).
KEEL_TOOLWORD_RE='(^|[^A-Za-z0-9_.-])(git|gh|jj|sl|gt|glab|hub)([^A-Za-z0-9_-]|$)'
KEEL_PATHCMD_RE='(^|[[:space:];|&(])[.]?/'
names_tool() {
  [[ "$command_text" =~ $KEEL_TOOLWORD_RE ]] && return 0
  [[ "$command_text" =~ $KEEL_PATHCMD_RE ]] && return 0
  return 1
}

# path_check <value>: rule B2 for PATH assignments.
path_check() {
  local val=$1 rest entry exp t has_path=0 unexp=0
  case ":$val:" in *':$PATH:'* | *':${PATH}:'*) has_path=1 ;; esac
  [ "$has_path" -eq 1 ] || deny B2 "PATH is replaced without keel's shims"
  rest=$val
  while [ -n "$rest" ]; do
    case "$rest" in *:*) entry=${rest%%:*}; rest=${rest#*:} ;; *) entry=$rest; rest= ;; esac
    case "$entry" in '$PATH' | '${PATH}') break ;; '') continue ;; esac
    if exp=$(expand "$entry" env); then
      for t in $KEEL_TOOLS; do
        [ -x "$exp/$t" ] && [ ! -d "$exp/$t" ] && deny B2 "PATH puts $exp (which holds $t) before keel's shims"
      done
    else
      unexp=1
    fi
  done
  if [ "$unexp" -eq 1 ] && names_tool; then
    deny B2 "PATH is changed with an entry that can't be resolved, in a command that runs a guarded tool"
  fi
}

check_name() { # <variable name> <how>: rule B2 for protected variables
  [[ "$1" =~ $KEEL_PROTECTED_RE ]] && deny B2 "$2 of $1 would weaken keel's push guard"
  return 0
}

# shim_check <label> <tool> <args...>: apply layer A's rules without executing anything.
shim_check() {
  local label=$1 tool=$2 out rc
  shift 2
  out=$(cd "$cwd" 2>/dev/null; KEEL_SHIM_CHECK=1 KEEL_SHIM_DEPTH=0 KEEL_ROOT="$KEEL_ROOT" "$KEEL_ROOT/shims/$tool" "$@" 2>&1 </dev/null)
  rc=$?
  if [ "$rc" -eq 2 ]; then
    local rule=${out#*blocked publish (}
    rule=${rule%%)*}
    deny "$label" "$tool $* (rule $rule)"
  fi
  return 0
}

# w1_check <tool> <args...>: forge HTTP writes (rule W1).
w1_check() {
  local tool=$1 method= data=0 a u host path urls=()
  shift
  while [ $# -gt 0 ]; do
    a=$1
    case "$tool" in
      curl)
        case "$a" in
          -X | --request) method=${2:-}; shift ;;
          -X?*) method=${a#-X} ;;
          --request=*) method=${a#--request=} ;;
          -d | --data | --data-raw | --data-binary | --data-urlencode | --data-ascii | -F | --form | --form-string | --json) data=1; shift ;;
          --data=* | --data-*=* | --form=* | --json=*) data=1 ;;
          -T | --upload-file) method=${method:-PUT}; shift ;;
          --url) urls+=("${2:-}"); shift ;;
        esac ;;
      wget)
        case "$a" in
          --method) method=${2:-}; shift ;;
          --method=*) method=${a#--method=} ;;
          --post-data* | --post-file* | --body-data* | --body-file*) data=1 ;;
        esac ;;
      http | https | xh | xhs)
        case "$a" in
          GET | POST | PUT | PATCH | DELETE | HEAD | OPTIONS) [ -z "$method" ] && method=$a ;;
          -*) ;;
          *://*) ;;
          *=* | *:=* | *@*) data=1 ;;
        esac ;;
    esac
    case "$a" in http://* | https://*) urls+=("$a") ;; esac
    shift
  done
  [ -n "$method" ] || { [ "$data" -eq 1 ] && method=POST || method=GET; }
  method=$(printf '%s' "$method" | tr 'a-z' 'A-Z')
  case "$method" in POST | PUT | PATCH | DELETE) ;; *) return 0 ;; esac
  for u in ${urls[@]+"${urls[@]}"}; do
    u=${u#*://}; host=${u%%/*}; path=/${u#*/}; [ "$host" = "$u" ] && path=/
    path=${path%%\?*}
    case "$host" in
      api.github.com) [[ "${path#/}" =~ $KEEL_GH_REF_RE ]] && deny W1 "$tool $method to GitHub $path" ;;
    esac
    case "$path" in
      /api/v3/repos/*) [[ "${path#/}" =~ $KEEL_GH_REF_RE ]] && deny W1 "$tool $method to GitHub Enterprise $path" ;;
    esac
    [ "$host" = "api.bitbucket.org" ] && [[ "$path" =~ $KEEL_BB_RE ]] && deny W1 "$tool $method to Bitbucket $path"
    [[ "$path" =~ $KEEL_GL_RE ]] && deny W1 "$tool $method to GitLab $path"
    [[ "$path" =~ $KEEL_RP_RE ]] && deny W1 "$tool $method to a git smart-HTTP push endpoint"
  done
  return 0
}

v1() { [[ "$1" =~ $KEEL_V1_RE ]]; }

# git_fast_allow <args...>: true for a git builtin that can neither publish nor touch guarded
# config, with no -c/--config-env (which could define aliases or protected keys). Saves spawning
# the shim (and git) for everyday commands; everything else goes through shim_check.
git_fast_allow() {
  local a sub=
  while [ $# -gt 0 ]; do
    a=$1
    case "$a" in
      -c | --config-env | --config-env=* | --exec-path* | -*=*) return 1 ;;
      -C | --git-dir | --work-tree | --namespace) shift 2; continue ;;
      -*) shift; continue ;;
      *) sub=$a; break ;;
    esac
  done
  [ -n "$sub" ] || return 1
  case " ${KEEL_GIT_BUILTINS:-} " in *" $sub "*) ;; *) return 1 ;; esac
  case "$sub" in
    push | send-pack | http-push | send-email | imap-send | svn | p4 | subtree | receive-pack | remote-* | config | remote) return 1 ;;
  esac
  return 0   # rebase -x, submodule foreach and bisect run payloads are analyzed by git_payloads
}

# gh_fast_allow <args...>: true for gh commands that cannot publish (reads, issues, runs, auth...).
# pr/repo/release/agent-task/api, aliases, extensions and anything unknown go through shim_check.
gh_fast_allow() {
  local cmd=${1:-} sub= a
  case "$cmd" in
    auth | browse | codespace | gist | issue | org | project | skill | cache | run | workflow | alias | attestation | \
      completion | config | extension | gpg-key | label | licenses | preview | ruleset | search | secret | ssh-key | \
      status | variable | help | version | --version | --help) return 0 ;;
    pr)
      shift
      for a in "$@"; do case "$a" in -*) ;; *) sub=$a; break ;; esac; done
      case "$sub" in view | list | status | checks | diff | comment | edit | checkout | review | close | lock | unlock) return 0 ;; esac
      return 1 ;;
  esac
  return 1
}

# git_payloads <depth> <args...>: literal commands git runs for us (rule B4).
git_payloads() {
  local depth=$1 a key val sub= i=0 args=()
  shift
  args=("$@")
  while [ "$i" -lt "${#args[@]}" ]; do
    a=${args[$i]}
    case "$a" in
      -c)
        i=$((i + 1)); val=${args[$i]:-}
        key=${val%%=*}; val=${val#*=}
        case "$key" in
          alias.*) case "$val" in '!'*) analyze "${val#!}" $((depth + 1)) B4 ;; esac ;;
          core.pager | core.editor | sequence.editor | diff.external | core.sshCommand | core.sshcommand) analyze "$val" $((depth + 1)) B4 ;;
        esac ;;
      -C | --git-dir | --work-tree | --namespace) i=$((i + 1)) ;;
      -*) ;;
      *) sub=$a; break ;;
    esac
    i=$((i + 1))
  done
  [ -n "$sub" ] || return 0
  i=$((i + 1))
  case "$sub" in
    rebase)
      while [ "$i" -lt "${#args[@]}" ]; do
        a=${args[$i]}
        case "$a" in
          -x | --exec) i=$((i + 1)); analyze "${args[$i]:-}" $((depth + 1)) B4 ;;
          --exec=*) analyze "${a#--exec=}" $((depth + 1)) B4 ;;
          -x?*) analyze "${a#-x}" $((depth + 1)) B4 ;;
        esac
        i=$((i + 1))
      done ;;
    submodule)
      [ "${args[$i]:-}" = "foreach" ] || return 0
      i=$((i + 1))
      while [ "$i" -lt "${#args[@]}" ]; do case "${args[$i]}" in -*) i=$((i + 1)) ;; *) break ;; esac; done
      analyze "${args[*]:$i}" $((depth + 1)) B4 ;;
    bisect)
      [ "${args[$i]:-}" = "run" ] || return 0
      i=$((i + 1))
      analyze "$(printf '%q ' "${args[@]:$i}")" $((depth + 1)) B4 ;;
  esac
  return 0
}

# command_rules <words> <depth> <label> <heredoc> <herestring>
command_rules() {
  local depth=$2 over=$3 heredoc=$4 herestr=$5 raw=() w cmd base i bypass=0 label envclear=0 name val sub n
  local IFS=$'\037'
  read -r -a raw <<< "$1"
  IFS=$' \t\n'
  local words=() unres=()
  for w in ${raw[@]+"${raw[@]}"}; do
    val=${w#?}
    if [ "${w:0:1}" = "U" ]; then
      if val=$(expand "$val"); then words+=("$val"); unres+=(0); else words+=("$val"); unres+=(1); fi
    else
      words+=("$val"); unres+=(0)
    fi
  done
  set -- ${words[@]+"${words[@]}"}
  local u=(${unres[@]+"${unres[@]}"})

  # leading assignments, reserved words, precommand modifiers
  while [ $# -gt 0 ]; do
    if [[ "$1" =~ $KEEL_ASSIGN_RE ]]; then
      name=${BASH_REMATCH[1]}; val=$(decode "${BASH_REMATCH[2]}")
      check_name "$name" "assignment"
      [ "$name" = "PATH" ] && path_check "$val"
      [ "${u[0]:-0}" = 0 ] && remember "$name" "$val"
      shift; u=("${u[@]:1}"); continue
    fi
    case "$1" in
      if | then | elif | else | fi | while | until | do | done | case | esac | select | '!' | time | coproc | '{' | '}' | '[[' | noglob | nocorrect | - | builtin | nohup)
        shift; u=("${u[@]:1}"); continue ;;
      -p) [ "${prev_word:-}" = "time" ] && { shift; u=("${u[@]:1}"); continue; } ;;
    esac
    break
  done
  [ $# -gt 0 ] || return 0

  # an unresolved command word (rule B5)
  if [ "${u[0]:-0}" = 1 ]; then
    for w in "${@:2}"; do v1 "${w//$NLE/$'\n'}" && deny B5 "unresolved command word with publish vocabulary: $*"; done
    return 0
  fi

  # wrappers that run another command, some of them bypassing PATH
  n=0
  while [ $# -gt 0 ] && [ "$n" -lt 12 ]; do
    n=$((n + 1))
    cmd=$1
    case "$cmd" in '='*) cmd=${cmd#=}; bypass=1 ;; esac
    base=${cmd##*/}
    [ "$base" != "$cmd" ] && case "$KEEL_TOOLS" in *" $base "*) bypass=1 ;; esac
    case "$base" in
      git-?*) set -- git "${base#git-}" "${@:2}"; continue ;;
      xcrun)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -f | --find | -v | --version | -h | --help | --show-sdk-*) return 0 ;; --sdk | -sdk | --toolchain) shift 2 ;; -*) shift ;; *) break ;; esac
        done
        bypass=1; continue ;;
      env)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -i | --ignore-environment | -) envclear=1; shift ;;
            -u | --unset) check_name "${2:-}" "env -u"; [ "${2:-}" = PATH ] && names_tool && deny B2 "env -u PATH in a command that runs a guarded tool"; shift 2 ;;
            -u?*) check_name "${1#-u}" "env -u"; shift ;;
            --unset=*) check_name "${1#--unset=}" "env --unset"; shift ;;
            -P) bypass=1; shift 2 ;;
            -P?*) bypass=1; shift ;;
            -S | --split-string) local split=${2:-}; shift 2; set -- $split "$@" ;;
            -C | --chdir) shift 2 ;;
            -0 | -v | --debug) shift ;;
            --) shift; break ;;
            -*) shift ;;
            *)
              if [[ "$1" =~ $KEEL_ASSIGN_RE ]]; then
                check_name "${BASH_REMATCH[1]}" "env assignment"
                [ "${BASH_REMATCH[1]}" = PATH ] && path_check "${BASH_REMATCH[2]}"
                shift
              else break
              fi ;;
          esac
        done
        if [ "$envclear" -eq 1 ] && [ $# -gt 0 ]; then
          case "$KEEL_TOOLS" in *" ${1##*/} "*) deny B2 "env -i clears keel's push guard for ${1##*/}" ;; esac
        fi
        continue ;;
      command)
        case "${2:-}" in
          -p) case "$KEEL_TOOLS" in *" ${3##*/} "*) deny B2 "command -p bypasses keel's shims for ${3##*/}" ;; esac; shift 2; bypass=1; continue ;;
          -v | -V) return 0 ;;
        esac
        shift; continue ;;
      exec) shift; [ "${1:-}" = "-a" ] && shift 2; continue ;;
      nice) shift; case "${1:-}" in -n) shift 2 ;; -[0-9]* | --adjustment=*) shift ;; esac; continue ;;
      time) shift; [ "${1:-}" = "-p" ] && shift; continue ;;
      timeout)
        shift
        while [ $# -gt 0 ]; do case "$1" in -s | -k | --signal | --kill-after) shift 2 ;; -*) shift ;; *) break ;; esac; done
        shift; continue ;;
      caffeinate)
        shift
        while [ $# -gt 0 ]; do case "$1" in -t | -w) shift 2 ;; -*) shift ;; *) break ;; esac; done
        continue ;;
      arch)
        shift
        while [ $# -gt 0 ]; do case "$1" in -arch | -e) shift 2 ;; -*) shift ;; *) break ;; esac; done
        continue ;;
      script)
        shift
        while [ $# -gt 0 ]; do case "$1" in -t | -T | -F) shift 2 ;; -*) shift ;; *) break ;; esac; done
        shift; continue ;;
      sudo | doas)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -u | -g | -h | -C | -D | -p | -r | -t | -U | -T) shift 2 ;; -s | -i) return 0 ;; -*) shift ;; *) break ;; esac
        done
        continue ;;
      stdbuf | unbuffer)
        shift
        while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
        continue ;;
      direnv) [ "${2:-}" = "exec" ] || return 0; shift 3; continue ;;
      mise | asdf)
        case "${2:-}" in exec | x) ;; *) return 0 ;; esac
        shift 2
        local j=1 found=0
        for w in "$@"; do if [ "$w" = "--" ]; then found=1; break; fi; j=$((j + 1)); done
        if [ "$found" -eq 1 ]; then shift "$j"; else while [ $# -gt 0 ]; do case "$1" in -*|*@*) shift ;; *) break ;; esac; done; fi
        continue ;;
      xargs)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -n | -L | -P | -s | -E | -d | -I | -a) shift 2 ;; -*) shift ;; *) break ;; esac
        done
        continue ;;
      keel-evidence)
        local j=1 found=0
        for w in "$@"; do if [ "$w" = "--" ]; then found=1; break; fi; j=$((j + 1)); done
        [ "$found" -eq 1 ] || return 0
        shift "$j"; continue ;;
      find)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -exec | -execdir | -ok | -okdir)
              shift
              local sub_words=()
              while [ $# -gt 0 ] && [ "$1" != ";" ] && [ "$1" != "+" ]; do sub_words+=("$1"); shift; done
              [ ${#sub_words[@]} -gt 0 ] && analyze "$(printf '%q ' "${sub_words[@]}")" $((depth + 1)) "$over" ;;
          esac
          [ $# -gt 0 ] && shift
        done
        return 0 ;;
      ssh)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -p | -i | -l | -o | -F | -J | -L | -R | -D | -W | -b | -c | -e | -m | -O | -Q | -S | -w | -E | -B) shift 2 ;; -*) shift ;; *) break ;; esac
        done
        [ $# -gt 1 ] || return 0
        shift
        analyze "$*" $((depth + 1)) "${over:-B4}"
        return 0 ;;
    esac
    break
  done
  [ $# -gt 0 ] || return 0
  cmd=$1
  case "$cmd" in '='*) cmd=${cmd#=}; bypass=1 ;; esac   # zsh =cmd expands to a path lookup result
  base=${cmd##*/}
  [ "$base" != "$cmd" ] && case "$KEEL_TOOLS" in *" $base "*) bypass=1 ;; esac
  shift

  case "$KEEL_TOOLS" in
    *" $base "*)
      label=B3; [ "$bypass" -eq 1 ] && label=B1; [ -n "$over" ] && label=$over
      local args=()
      for w in "$@"; do args+=("${w//$NLE/$'\n'}"); done
      if [ "$base" = "git" ] && git_fast_allow ${args[@]+"${args[@]}"}; then :
      elif [ "$base" = "gh" ] && gh_fast_allow ${args[@]+"${args[@]}"}; then :
      else shim_check "$label" "$base" ${args[@]+"${args[@]}"}
      fi
      [ "$base" = "git" ] && git_payloads "$depth" ${args[@]+"${args[@]}"}
      return 0 ;;
  esac

  case "$KEEL_SHELLS" in
    *" $base "*)
      local cflag=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; break ;;
          --*) shift ;;
          -*) case "$1" in *c*) cflag=1 ;; esac; shift ;;
          *) break ;;
        esac
      done
      if [ "$cflag" -eq 1 ] && [ $# -gt 0 ]; then analyze "$(decode "$1")" $((depth + 1)) B4; return 0; fi
      [ -n "$heredoc" ] && [ $# -eq 0 ] && analyze "$(decode "$heredoc")" $((depth + 1)) B4
      [ -n "$herestr" ] && [ $# -eq 0 ] && analyze "$(decode "$herestr")" $((depth + 1)) B4
      return 0 ;;
  esac

  case "$base" in
    eval)
      [ $# -gt 0 ] && analyze "$(decode "$*")" $((depth + 1)) "${over:-B4}"
      return 0 ;;
    python | python2 | python3 | python3.* | node | nodejs | perl | ruby | osascript)
      while [ $# -gt 0 ]; do
        case "$1" in
          -c | -e | -E) v1 "$(decode "${2:-}")" && deny W2 "$base inline code with publish vocabulary"; shift 2 ;;
          *) shift ;;
        esac
      done
      [ -n "$heredoc" ] && v1 "$(decode "$heredoc")" && deny W2 "$base here-document with publish vocabulary"
      [ -n "$herestr" ] && v1 "$(decode "$herestr")" && deny W2 "$base here-string with publish vocabulary"
      return 0 ;;
    curl | wget | http | https | xh | xhs)
      w1_check "$base" "$@"
      return 0 ;;
    hash)
      if [ "${1:-}" = "-p" ]; then
        case "$KEEL_TOOLS" in *" ${3:-} "*) deny B2 "hash -p redirects ${3:-} away from keel's shims" ;; esac
      fi
      return 0 ;;
    unset)
      for w in "$@"; do
        case "$w" in -*) continue ;; esac
        check_name "$w" "unset"
        [ "$w" = PATH ] && deny B2 "unset PATH removes keel's shims"
      done
      return 0 ;;
    export | declare | typeset | local | readonly)
      for w in "$@"; do
        case "$w" in -*) continue ;; esac
        if [[ "$w" =~ $KEEL_ASSIGN_RE ]]; then
          name=${BASH_REMATCH[1]}; val=$(decode "${BASH_REMATCH[2]}")
          check_name "$name" "$base"
          [ "$name" = PATH ] && path_check "$val"
          remember "$name" "$val"
        else
          [[ "$w" =~ $KEEL_NAME_RE ]] && check_name "$w" "$base"
        fi
      done
      return 0 ;;
  esac
  return 0
}

# analyze <text> <depth> <label-override>: tokenize and apply the rules to every simple command.
analyze() {
  local text=$1 depth=$2 over=${3:-} toks rec rest idx
  [ "$depth" -le 5 ] || deny F2 "shell payloads nested deeper than 5 levels"
  toks=$(printf '%s' "$text" | keel_shell_tokens) || deny F2 "the command could not be parsed"
  local hd=() hs=()
  while IFS= read -r rec; do
    case "$rec" in
      H$'\t'*) rest=${rec#H$'\t'}; idx=${rest%%$'\t'*}; hd[$idx]="${hd[$idx]:-}${rest#*$'\t'}" ;;
      S$'\t'*) rest=${rec#S$'\t'}; idx=${rest%%$'\t'*}; hs[$idx]=${rest#*$'\t'} ;;
    esac
  done <<EOF
$toks
EOF
  while IFS= read -r rec; do
    case "$rec" in C$'\t'*) ;; *) continue ;; esac
    rest=${rec#C$'\t'}; idx=${rest%%$'\t'*}; rest=${rest#*$'\t'}
    command_rules "$rest" "$depth" "$over" "${hd[$idx]:-}" "${hs[$idx]:-}"
  done <<EOF
$toks
EOF
  return 0
}

# ---------------------------------------------------------------------------------------------
mode=${1:-shell}
case "$mode" in
  shell)
    tool=${f_tool#S}
    case "$f_cmd" in
      S*) command_text=${f_cmd#S} ;;
      M) [ "$tool" = "Monitor" ] && exit 0; deny F1 "no command in the $tool payload" ;;
      *) deny F1 "the command in the $tool payload is not a string" ;;
    esac
    analyze "$command_text" 0 ""
    exit 0 ;;
  --github-mcp)
    # Default-deny: only reads and named writes that cannot publish commits or open/merge PRs.
    tool=${f_tool#S}
    case "$f_tool" in S*) ;; *) deny F1 "no tool name in the payload" ;; esac
    op=${tool##*__}
    case "$op" in
      get_* | list_* | search_*) exit 0 ;;
      add_issue_comment | create_issue | update_issue | add_comment_to_pending_review | \
        create_pending_pull_request_review | submit_pending_pull_request_review | request_copilot_review) exit 0 ;;
    esac
    deny T1 "GitHub MCP $op could publish (only reads and named non-publishing writes are allowed)" ;;
  --codex)
    # A Codex agent with network access could push or open PRs on its own: deny full access,
    # config overrides of the sandbox or network, and the same settings in CODEX_HOME/config.toml.
    sb=$(printf '%s' "$input" | keel_json_get tool_input.sandbox 2>/dev/null)
    case $? in 0 | 1 | 3) ;; *) deny F1 "codex payload is not valid JSON" ;; esac
    cfg=$(printf '%s' "$input" | keel_json_get -r tool_input.config 2>/dev/null) || cfg=
    KEEL_NET_RE='"network_access"[[:space:]]*:[[:space:]]*true'
    case "$cfg" in *'"sandbox_mode"'*) deny T2 "codex config overrides the sandbox mode" ;; esac
    [[ "$cfg" =~ $KEEL_NET_RE ]] && deny T2 "codex config enables network access"
    case "$sb" in
      danger-full-access) deny T2 "codex with danger-full-access can publish" ;;
      read-only | workspace-write) exit 0 ;;
      '') ;;
      *) deny T2 "unknown codex sandbox '$sb'" ;;
    esac
    toml="${CODEX_HOME:-$HOME/.codex}/config.toml"
    if [ -e "$toml" ]; then
      [ -r "$toml" ] || deny T2 "cannot read $toml to learn codex's default sandbox"
      KEEL_TOML_SB_RE='^[[:space:]]*sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"'
      KEEL_TOML_NET_RE='^[[:space:]]*network_access[[:space:]]*=[[:space:]]*true'
      while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ $KEEL_TOML_SB_RE ]] && deny T2 "codex's default sandbox in $toml is danger-full-access"
        [[ "$line" =~ $KEEL_TOML_NET_RE ]] && deny T2 "codex's $toml enables network access"
      done < "$toml"
    fi
    exit 0 ;;
  *)
    deny F2 "unknown guard mode $mode" ;;
esac
