# shellcheck shell=bash
# keel_json_get [-r] <dotted.path> < json
# Pure bash/awk JSON reader for hook payloads (no jq: keel requires only bash and git).
# Prints the string at <path>, decoded (\" \\ \/ \b \f \n \r \t and ASCII \u00XX; other \u
# escapes are left as written). With -r, prints the raw JSON text of any value instead.
# Exit: 0 found, 1 missing key, 2 invalid JSON or duplicate key, 3 value is not a string.
# The whole document is validated, so a malformed payload never yields a partial answer.

KEEL_JSON_AWK='
function fail(code) { if (!err) err = code; pos = n + 1 }
function ch() { return substr(s, pos, 1) }
function ws(  c) { while (pos <= n) { c = ch(); if (c == " " || c == "\t" || c == "\n" || c == "\r") pos++; else break } }
function hexval(h,  i, v, d) {
  v = 0
  for (i = 1; i <= 4; i++) {
    d = index("0123456789abcdef", tolower(substr(h, i, 1)))
    if (d == 0) return -1
    v = v * 16 + d - 1
  }
  return v
}
function str(  out, c, e, h, v, rest) {
  pos++
  out = ""
  while (!err) {
    if (pos > n) { fail(2); return "" }
    rest = substr(s, pos)
    if (match(rest, /^[^"\\\001-\037]+/)) { out = out substr(rest, 1, RLENGTH); pos += RLENGTH; continue }
    c = ch()
    if (c == "\"") { pos++; return out }
    if (c != "\\") { fail(2); return "" }
    e = substr(s, pos + 1, 1)
    if (e == "\"") out = out "\""
    else if (e == "\\") out = out "\\"
    else if (e == "/") out = out "/"
    else if (e == "b") out = out "\b"
    else if (e == "f") out = out "\f"
    else if (e == "n") out = out "\n"
    else if (e == "r") out = out "\r"
    else if (e == "t") out = out "\t"
    else if (e == "u") {
      h = substr(s, pos + 2, 4)
      v = hexval(h)
      if (length(h) < 4 || v < 0) { fail(2); return "" }
      if (v >= 1 && v < 128) out = out sprintf("%c", v); else out = out "\\u" h
      pos += 6
      continue
    } else { fail(2); return "" }
    pos += 2
  }
  return ""
}
function record(path, type, val, raw) {
  if (path == target) { found = 1; ftype = type; fval = val; fraw = raw }
  if (multi && (path in want)) { mtype[path] = type; mval[path] = val }
}
function value(path,  c, start, v, rest) {
  ws()
  if (pos > n) { fail(2); return }
  c = ch()
  start = pos
  if (c == "{") { object(path); record(path, "object", "", substr(s, start, pos - start)) }
  else if (c == "[") { array(path); record(path, "array", "", substr(s, start, pos - start)) }
  else if (c == "\"") { v = str(); if (!err) record(path, "string", v, substr(s, start, pos - start)) }
  else {
    rest = substr(s, pos)
    if (match(rest, /^(true|false|null)/) || match(rest, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/)) {
      pos += RLENGTH
      record(path, "other", "", substr(rest, 1, RLENGTH))
    } else fail(2)
  }
}
function object(path,  id, key, child) {
  pos++
  id = ++objects
  ws()
  if (ch() == "}") { pos++; return }
  while (!err) {
    ws()
    if (ch() != "\"") { fail(2); return }
    key = str()
    if (err) return
    if ((id SUBSEP key) in seen) { fail(2); return }
    seen[id SUBSEP key] = 1
    ws()
    if (ch() != ":") { fail(2); return }
    pos++
    child = (path == "") ? key : path "." key
    value(child)
    ws()
    if (ch() == ",") { pos++; continue }
    if (ch() == "}") { pos++; return }
    fail(2)
  }
}
function array(path,  i) {
  pos++
  ws()
  if (ch() == "]") { pos++; return }
  i = 0
  while (!err) {
    value(path "[" i "]")
    i++
    ws()
    if (ch() == ",") { pos++; continue }
    if (ch() == "]") { pos++; return }
    fail(2)
  }
}
BEGIN {
  RS = "\001"
  multi = (targets != "")
  if (multi) { nt = split(targets, tl, "|"); for (i = 1; i <= nt; i++) want[tl[i]] = 1 }
}
{ s = (NR == 1) ? $0 : s RS $0 }
END {
  n = length(s)
  pos = 1
  err = 0
  if (n == 0) exit 2
  value("")
  ws()
  if (!err && pos <= n) err = 2
  if (err) exit err
  if (multi) {
    for (i = 1; i <= nt; i++) {
      if (!(tl[i] in mtype)) printf "M"
      else if (mtype[tl[i]] != "string") printf "N"
      else printf "S%s", mval[tl[i]]
      printf "\036"
    }
    exit 0
  }
  if (!found) exit 1
  if (raw == 1) { printf "%s", fraw; exit 0 }
  if (ftype != "string") exit 3
  printf "%s", fval
  exit 0
}'

keel_json_get() {
  local raw=0
  if [ "${1:-}" = "-r" ]; then
    raw=1
    shift
  fi
  LC_ALL=C awk -v target="$1" -v raw="$raw" "$KEEL_JSON_AWK"
}

# keel_json_fields <path>... < json: one validating pass for several paths. Prints, for each path
# in order, "S<decoded string>", "N" (present but not a string) or "M" (missing), each followed by
# \036. Exit 2 on invalid JSON. Callers must reject values containing \036 (fail closed).
keel_json_fields() {
  local IFS='|'
  LC_ALL=C awk -v targets="$*" -v target="" -v raw=0 "$KEEL_JSON_AWK"
}
