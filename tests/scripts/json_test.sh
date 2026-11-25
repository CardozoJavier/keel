#!/bin/bash
# Tests for plugin/lib/json.sh (keel_json_get): pure bash/awk JSON string extraction used by the
# push guard. Exit codes: 0 found, 1 missing key, 2 invalid JSON or duplicate key, 3 not a string.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
. "$KEEL_PLUGIN_ROOT/lib/json.sh"

get() { printf '%s' "$1" | keel_json_get "$2"; }
code() { printf '%s' "$1" | keel_json_get $2 >/dev/null 2>&1; echo $?; }

J='{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git status","description":"x"},"cwd":"/r"}'
assert_eq "git status" "$(get "$J" tool_input.command)" "nested string"
assert_eq "Bash" "$(get "$J" tool_name)" "top-level string"
assert_eq "/r" "$(get "$J" cwd)" "cwd"

# whitespace and newlines between tokens
J2='{
  "tool_input" : { "command" : "ls -la" } ,
  "n": -1.5e3, "b": true, "z": null, "arr": [1, {"k": "v"}, [2]]
}'
assert_eq "ls -la" "$(get "$J2" tool_input.command)" "whitespace and other value types are skipped"

# escapes
J3='{"tool_input":{"command":"echo \"a\\\\b\" \/ x\ny\tz"}}'
assert_eq "$(printf 'echo "a\\\\b" / x\ny\tz')" "$(get "$J3" tool_input.command)" "standard escapes decode"
assert_eq "A-B" "$(get '{"c":"A-B"}' c)" "ASCII \\u00XX decodes"
assert_eq 'é 中' "$(get '{"c":"é 中"}' c)" "non-ASCII \\u escapes stay escaped"
assert_eq 'echo "{\"a\":1}"' "$(get '{"c":"echo \"{\\\"a\\\":1}\""}' c)" "braces and nested quotes in a string"
assert_eq "café" "$(get '{"c":"café"}' c)" "raw UTF-8 passes through"

# missing key, invalid JSON, duplicate keys, wrong type
assert_eq 1 "$(code "$J" tool_input.missing)" "missing key exits 1"
assert_eq 2 "$(code '{"c":"unterminated}' c)" "unterminated string exits 2"
assert_eq 2 "$(code '{"c":"x"} trailing' c)" "trailing garbage exits 2"
assert_eq 2 "$(code '{"c" "x"}' c)" "missing colon exits 2"
assert_eq 2 "$(code '' c)" "empty input exits 2"
assert_eq 2 "$(code '{"c":"x","c":"y"}' c)" "duplicate key exits 2"
assert_eq 2 "$(code "$(printf '{"c":"a\tb"}')" c)" "raw control character in a string exits 2"
assert_eq 0 "$(code '{"a":{"k":"1"},"b":{"k":"2"}}' b.k)" "same key in different objects is fine"
assert_eq 3 "$(code '{"c":{"x":1}}' c)" "non-string value exits 3 without -r"
assert_eq '{"sandbox_mode": "read-only"}' "$(get_raw() { printf '%s' "$1" | keel_json_get -r "$2"; }; get_raw '{"config":{"sandbox_mode": "read-only"}}' config)" "-r prints the raw JSON value"

# a command of a few KB parses quickly
big=$(printf 'echo %.0s0123456789' $(seq 1 400))
assert_eq "$big" "$(get "{\"tool_input\":{\"command\":\"$big\"}}" tool_input.command)" "long command"

# keel_json_fields: several paths in one pass (S=string, N=not a string, M=missing; \036-separated)
f=$(printf '%s' "$J" | keel_json_fields tool_name tool_input.command nope tool_input | tr '\036' '|')
assert_eq "SBash|Sgit status|M|N|" "$f" "keel_json_fields reports each path in order"
printf '%s' '{"c":"x"' | keel_json_fields c >/dev/null 2>&1
assert_eq 2 "$?" "keel_json_fields rejects invalid JSON"

t_summary
