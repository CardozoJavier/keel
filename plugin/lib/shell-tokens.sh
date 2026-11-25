# shellcheck shell=bash
# keel_shell_tokens < command-text: tokenize a shell command line for push guard layer B.
# One POSIX awk pass (BSD awk compatible). Output records, one per line, tab-separated:
#   C <idx> <words>    a simple command; words are \037-separated, each prefixed with
#                      L (literal) or U (contains an unresolved $-expansion or substitution);
#                      newlines inside words are written as \036
#   H <idx> <body>     here-document body attached to command <idx> (newlines as \036)
#   S <idx> <text>     here-string attached to command <idx>
# Contents of $( ), backticks and <( ) are tokenized as further commands (queued, same output).
# Here-document bodies are data: they are never tokenized as commands, and they are skipped
# inside $( ) as well, so a commit message like "don't" can't unbalance the parse.
# Exit 3 on unterminated quotes or substitutions (the caller fails closed).

KEEL_TOKENS_AWK='
BEGIN { RS = "\001"; SEP = "\037"; NLE = "\036"; nq = 0; ncmd = 0 }
{ input = (NR == 1) ? $0 : input RS $0 }
END {
  q[nq++] = input
  for (qi = 0; qi < nq; qi++) scan(q[qi])
  exit 0
}
function fail() { exit 3 }
function idx_from(s, ch, p,   i) { if (p > length(s)) return 0; i = index(substr(s, p), ch); return i ? p + i - 1 : 0 }
function isblank(c) { return c == " " || c == "\t" }
function addc(c) { w = w c; inword = 1 }
function endword() {
  if (inword) {
    gsub(/\n/, NLE, w)
    if (skipnext) skipnext = 0
    else if (herestr) { herestr = 0; print "S\t" (ncmd + 1) "\t" w }
    else words[nw++] = (wflag ? "U" : "L") w
  }
  w = ""; inword = 0; wflag = 0
}
function endcmd(   i, line) {
  endword()
  if (nw > 0) {
    ncmd++
    line = words[0]
    for (i = 1; i < nw; i++) line = line SEP words[i]
    print "C\t" ncmd "\t" line
  }
  nw = 0; skipnext = 0; herestr = 0
}
# read_delim(s, p): parse a here-document delimiter word at p; sets RD (unquoted text) and returns
# the position after it.
function read_delim(s, p,   n, c, t) {
  n = length(s); RD = ""
  while (p <= n && isblank(substr(s, p, 1))) p++
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "'"'"'") { t = idx_from(s, "'"'"'", p + 1); if (!t) fail(); RD = RD substr(s, p + 1, t - p - 1); p = t + 1; continue }
    if (c == "\"") { t = idx_from(s, "\"", p + 1); if (!t) fail(); RD = RD substr(s, p + 1, t - p - 1); p = t + 1; continue }
    if (c == "\\") { RD = RD substr(s, p + 1, 1); p += 2; continue }
    if (isblank(c) || c == "\n" || c == ";" || c == "&" || c == "|" || c == "<" || c == ">" || c == "(" || c == ")") break
    RD = RD c; p++
  }
  return p
}
# skip_bodies(s, p, delims, strips, n): p is just after a newline; skip n here-document bodies.
function skip_bodies(s, p, dl, st, n,   i, len, t, line) {
  len = length(s)
  for (i = 0; i < n; i++) {
    while (p <= len) {
      t = idx_from(s, "\n", p); line = t ? substr(s, p, t - p) : substr(s, p)
      p = t ? t + 1 : len + 1
      if (st[i]) sub(/^\t+/, "", line)
      if (line == dl[i]) break
    }
  }
  return p
}
# close_paren(s, p): p is just after "("; return the index of the matching ")" or 0.
function close_paren(s, p,   depth, c, n, t, nd, dl, st, prev) {
  depth = 1; n = length(s); nd = 0; prev = "("
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "\\") { p += 2; prev = "x"; continue }
    if (c == "'"'"'") { t = idx_from(s, "'"'"'", p + 1); if (!t) return 0; p = t + 1; prev = "x"; continue }
    if (c == "\"") { t = close_dq(s, p + 1); if (!t) return 0; p = t + 1; prev = "x"; continue }
    if (c == "`") { t = close_bt(s, p + 1); if (!t) return 0; p = t + 1; prev = "x"; continue }
    if (c == "#" && (prev == " " || prev == "\t" || prev == "\n" || prev == ";" || prev == "(" || prev == "|" || prev == "&")) {
      t = idx_from(s, "\n", p); if (!t) return 0; p = t; prev = "x"; continue
    }
    if (c == "<" && substr(s, p + 1, 1) == "<" && substr(s, p + 2, 1) != "<") {
      p += 2
      st[nd] = 0
      if (substr(s, p, 1) == "-") { st[nd] = 1; p++ }
      p = read_delim(s, p); dl[nd++] = RD; prev = "x"; continue
    }
    if (c == "\n" && nd > 0) { p = skip_bodies(s, p + 1, dl, st, nd); nd = 0; prev = "\n"; continue }
    if (c == "(") depth++
    else if (c == ")") { depth--; if (depth == 0) return p }
    prev = c; p++
  }
  return 0
}
function close_dq(s, p,   c, n, t) {
  n = length(s)
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "\\") { p += 2; continue }
    if (c == "\"") return p
    if (c == "$" && substr(s, p + 1, 1) == "(") { t = close_paren(s, p + 2); if (!t) return 0; p = t + 1; continue }
    if (c == "`") { t = close_bt(s, p + 1); if (!t) return 0; p = t + 1; continue }
    p++
  }
  return 0
}
function close_bt(s, p,   c, n) {
  n = length(s)
  while (p <= n) { c = substr(s, p, 1); if (c == "\\") { p += 2; continue }; if (c == "`") return p; p++ }
  return 0
}
# dollar(s, p): handle "$" at p (outside or inside double quotes); return the next position.
function dollar(s, p,   d, t, name, c, e, out) {
  d = substr(s, p + 1, 1)
  if (d == "'"'"'") {
    out = ""; t = p + 2
    while (t <= length(s)) {
      c = substr(s, t, 1)
      if (c == "\\") {
        e = substr(s, t + 1, 1)
        if (e == "n") out = out "\n"; else if (e == "t") out = out "\t"; else out = out e
        t += 2; continue
      }
      if (c == "'"'"'") { addc(out); inword = 1; return t + 1 }
      out = out c; t++
    }
    fail()
  }
  if (d == "(") {
    if (substr(s, p + 2, 1) == "(") { t = close_paren(s, p + 2); if (!t) fail(); addc("$((...))"); wflag = 1; return t + 1 }
    t = close_paren(s, p + 2); if (!t) fail()
    q[nq++] = substr(s, p + 2, t - p - 2)
    addc("$(...)"); wflag = 1; return t + 1
  }
  if (d == "{") { t = idx_from(s, "}", p + 2); if (!t) fail(); addc(substr(s, p, t - p + 1)); wflag = 1; return t + 1 }
  if (d ~ /[A-Za-z_]/) {
    name = ""; t = p + 1
    while (t <= length(s) && substr(s, t, 1) ~ /[A-Za-z0-9_]/) { name = name substr(s, t, 1); t++ }
    addc("$" name); wflag = 1; return t
  }
  if (d ~ /[0-9?#@*$!-]/ && d != "") { addc("$" d); wflag = 1; return p + 2 }
  addc("$"); return p + 1
}
# dq(s, p, end): contents of a double-quoted string from p to end-1.
function dq(s, p, end,   c, d, t) {
  while (p < end) {
    c = substr(s, p, 1)
    if (c == "\\") {
      d = substr(s, p + 1, 1)
      if (d == "$" || d == "`" || d == "\"" || d == "\\") { addc(d); p += 2; continue }
      if (d == "\n") { p += 2; continue }
      addc(c); p++; continue
    }
    if (c == "$") { p = dollar(s, p); continue }
    if (c == "`") { t = close_bt(s, p + 1); if (!t) fail(); q[nq++] = substr(s, p + 1, t - p - 1); addc("$(...)"); wflag = 1; p = t + 1; continue }
    addc(c); p++
  }
  inword = 1
}
# redir(s, p): a redirection operator at p; return the next position.
function redir(s, p,   c, d, t, strip) {
  c = substr(s, p, 1); d = substr(s, p + 1, 1)
  if (c == "<" && d == "<" && substr(s, p + 2, 1) == "<") { endword(); herestr = 1; return p + 3 }
  if (c == "<" && d == "<") {
    if (inword && w ~ /^[0-9]+$/) { w = ""; inword = 0 } else endword()
    p += 2; strip = 0
    if (substr(s, p, 1) == "-") { strip = 1; p++ }
    p = read_delim(s, p)
    hd_delim[nh] = RD; hd_strip[nh] = strip; hd_cmd[nh] = ncmd + 1; nh++
    return p
  }
  if ((c == "<" || c == ">") && d == "(") {
    endword()
    t = close_paren(s, p + 2); if (!t) fail()
    q[nq++] = substr(s, p + 2, t - p - 2)
    addc("$(...)"); wflag = 1; endword(); return t + 1
  }
  if (inword && w ~ /^[0-9]+$/) { w = ""; inword = 0 } else endword()
  p++
  d = substr(s, p, 1)
  if (d == ">" || d == "|") p++
  if (d == "&" || substr(s, p, 1) == "&") {
    if (d == "&") p++; else p++
    while (substr(s, p, 1) ~ /[0-9-]/ && substr(s, p, 1) != "") p++
    return p
  }
  skipnext = 1
  return p
}
# heredocs(s, p): p is just after a newline; consume pending here-document bodies.
function heredocs(s, p,   i, len, t, line, body, raw) {
  len = length(s)
  for (i = 0; i < nh; i++) {
    body = ""; first = 1
    while (p <= len) {
      t = idx_from(s, "\n", p); raw = t ? substr(s, p, t - p) : substr(s, p)
      p = t ? t + 1 : len + 1
      line = raw
      if (hd_strip[i]) sub(/^\t+/, "", line)
      if (line == hd_delim[i]) break
      body = first ? line : body NLE line; first = 0
    }
    print "H\t" hd_cmd[i] "\t" body
  }
  nh = 0
  return p
}
function scan(s,   n, p, c, d, t) {
  n = length(s); p = 1; w = ""; inword = 0; wflag = 0; nw = 0; skipnext = 0; herestr = 0; nh = 0
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "\\") {
      d = substr(s, p + 1, 1)
      if (d == "\n") { p += 2; continue }
      if (d != "") addc(d)
      p += 2; continue
    }
    if (c == "'"'"'") { t = idx_from(s, "'"'"'", p + 1); if (!t) fail(); addc(substr(s, p + 1, t - p - 1)); inword = 1; p = t + 1; continue }
    if (c == "\"") { t = close_dq(s, p + 1); if (!t) fail(); dq(s, p + 1, t); p = t + 1; continue }
    if (c == "$") { p = dollar(s, p); continue }
    if (c == "`") { t = close_bt(s, p + 1); if (!t) fail(); q[nq++] = substr(s, p + 1, t - p - 1); addc("$(...)"); wflag = 1; p = t + 1; continue }
    if (c == "#" && !inword) { t = idx_from(s, "\n", p); if (!t) break; p = t; continue }
    if (isblank(c)) { endword(); p++; continue }
    if (c == "\n") { endcmd(); p = heredocs(s, p + 1); continue }
    if (c == ";") { endcmd(); p++; continue }
    if (c == "&") {
      if (substr(s, p + 1, 1) == ">") { endword(); skipnext = 1; p += 2; if (substr(s, p, 1) == ">") p++; continue }
      endcmd(); p += (substr(s, p + 1, 1) == "&") ? 2 : 1; continue
    }
    if (c == "|") { endcmd(); d = substr(s, p + 1, 1); p += (d == "|" || d == "&") ? 2 : 1; continue }
    if (c == "(" || c == ")") { endcmd(); p++; continue }
    if ((c == "{" || c == "}") && !inword) {
      d = substr(s, p + 1, 1)
      if (d == "" || isblank(d) || d == "\n" || d == ";") { endcmd(); p++; continue }
    }
    if (c == "<" || c == ">") { p = redir(s, p); continue }
    addc(c); p++
  }
  endcmd()
  if (nh > 0) heredocs(s, n + 1)
}'

keel_shell_tokens() {
  LC_ALL=C awk "$KEEL_TOKENS_AWK"
}
