# shellcheck shell=bash
# PIT mutations.xml → TSV (contracts/mutation-runner.md §Output). PIT writes one <mutation> element
# per line (research R5), so this is a line-oriented awk parser, not a general XML parser.
#
#   keel_pit_rows <mutations.xml>
#     → one row per mutation, tab-separated:
#       class method desc mutator indexes line status killing succeeding covering sourceFile
#       (indexes comma-joined; test lists |-joined and normalized)
#     exit 12 when the file is missing or a <mutation> line lacks mutatedClass or status.
#
# Entities (&lt; &gt; &quot; &apos; &amp;) are decoded first. JUnit unique IDs are then
# normalized: [class:C]/[method:m(..)] → C#m; each [nested-class:N] appends $N; test-template and
# test-factory segments → C#m. Any other form is kept raw.

KEEL_PIT_AWK='
function dec(s) {
  gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "'"'"'", s)
  gsub(/&amp;/, "\\&", s)
  return s
}
function el(s, name,   v, op, cl) {
  op = "<" name ">"; cl = "</" name ">"
  if (index(s, "<" name "/>")) return ""
  if (!index(s, op)) return ""
  v = substr(s, index(s, op) + length(op))
  if (!index(v, cl)) return ""
  return substr(v, 1, index(v, cl) - 1)
}
function has(s, name) { return index(s, "<" name ">") || index(s, "<" name "/>") }
function norm(id,   c, rest, seg) {
  if (!match(id, /\[class:[^]]*\]/)) return id
  c = substr(id, RSTART + 7, RLENGTH - 8)
  rest = substr(id, RSTART + RLENGTH)
  while (match(rest, /\[nested-class:[^]]*\]/)) {
    c = c "$" substr(rest, RSTART + 14, RLENGTH - 15)
    rest = substr(rest, RSTART + RLENGTH)
  }
  if (match(rest, /\[(method|test-template|test-factory):[^](]*/)) {
    seg = substr(rest, RSTART, RLENGTH)
    sub(/^\[[a-z-]+:/, "", seg)
    return c "#" seg
  }
  return id
}
function tests(s,   n, a, i, out) {
  s = dec(s)
  if (s == "") return ""
  n = split(s, a, "|"); out = ""
  for (i = 1; i <= n; i++) out = out (i > 1 ? "|" : "") norm(a[i])
  return out
}
index($0, "<mutation ") {
  if (!has($0, "mutatedClass") || !match($0, /status=.[A-Z_]+./)) {
    printf "keel-pit: malformed mutation at line %d: %s\n", NR, substr($0, 1, 120) > "/dev/stderr"
    bad = 1; exit 12
  }
  st = substr($0, RSTART + 8, RLENGTH - 9)
  idx = el($0, "indexes"); gsub(/<\/index><index>/, ",", idx); gsub(/<\/?index>/, "", idx)
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", dec(el($0, "mutatedClass")), dec(el($0, "mutatedMethod")), \
    dec(el($0, "methodDescription")), el($0, "mutator"), idx, el($0, "lineNumber"), st, \
    tests(el($0, "killingTests")), tests(el($0, "succeedingTests")), tests(el($0, "coveringTests")), dec(el($0, "sourceFile"))
}
END { if (bad) exit 12 }
'

keel_pit_rows() {
  [ -f "${1:-}" ] || { printf 'keel-pit: no mutations.xml at %s\n' "${1:-}" >&2; return 12; }
  LC_ALL=C awk "$KEEL_PIT_AWK" "$1"
}
