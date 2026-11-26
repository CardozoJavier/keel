# keel push guard environment: layer A0 (git-level) and layer A (shims first on PATH).
# contracts/push-guard.md. Sourced from the SessionStart env file before every Bash command, so it
# must work in POSIX sh, bash and zsh. Requires KEEL_ROOT. Idempotent: sourcing it again (or from
# keel-verify/keel-evidence for the commands they spawn) adds nothing. Existing GIT_CONFIG_*
# entries are kept; keel's five entries are appended after them.
if [ -n "${KEEL_ROOT:-}" ] && [ -d "$KEEL_ROOT/shims" ]; then
  KEEL_SHIMS="$KEEL_ROOT/shims"
  export KEEL_ROOT KEEL_SHIMS
  case ":${PATH:-}:" in
    ":$KEEL_SHIMS:"*) ;;
    *) PATH="$KEEL_SHIMS${PATH:+:$PATH}"; export PATH ;;
  esac
  __keel_n=${GIT_CONFIG_COUNT:-0}
  case "$__keel_n" in '' | *[!0-9]*) __keel_n=0 ;; esac
  __keel_i=0
  __keel_have=0
  while [ "$__keel_i" -lt "$__keel_n" ]; do
    eval "__keel_k=\${GIT_CONFIG_KEY_$__keel_i:-}"
    [ "$__keel_k" = "hook.keel-nopush.event" ] && __keel_have=1
    __keel_i=$((__keel_i + 1))
  done
  if [ "$__keel_have" -eq 0 ]; then
    __keel_i=$__keel_n
    export "GIT_CONFIG_KEY_$__keel_i=hook.keel-nopush.event" "GIT_CONFIG_VALUE_$__keel_i=pre-push"
    __keel_i=$((__keel_n + 1))
    export "GIT_CONFIG_KEY_$__keel_i=hook.keel-nopush.command" "GIT_CONFIG_VALUE_$__keel_i='$KEEL_ROOT/hooks/deny-push'"
    __keel_i=$((__keel_n + 2))
    export "GIT_CONFIG_KEY_$__keel_i=hook.keel-nopush.enabled" "GIT_CONFIG_VALUE_$__keel_i=true"
    __keel_i=$((__keel_n + 3))
    export "GIT_CONFIG_KEY_$__keel_i=url.keel-blocked-push://.pushInsteadOf" "GIT_CONFIG_VALUE_$__keel_i="
    # Let the always-failing helper run even where git restricts transports (submodule foreach
    # sets GIT_PROTOCOL_FROM_USER=0), so the block reports keel's message.
    __keel_i=$((__keel_n + 4))
    export "GIT_CONFIG_KEY_$__keel_i=protocol.keel-blocked-push.allow" "GIT_CONFIG_VALUE_$__keel_i=always"
    GIT_CONFIG_COUNT=$((__keel_n + 5))
    export GIT_CONFIG_COUNT
  fi
  unset __keel_n __keel_i __keel_have __keel_k
fi
