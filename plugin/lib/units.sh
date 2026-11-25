# shellcheck shell=bash
# Work-unit helpers (data-model.md §5): ledger lookups and path classification. Needs common.sh.
# Unit rows: ts step started <BASE> "<unit> <intent> <paths>" | ts step ok|halted|abandoned <ref> "<unit> …"

# keel_unit_rows <feature> <unit>: the unit's ledger rows, oldest first.
keel_unit_rows() {
  "$(keel_root)/bin/keel-ledger" rows "$1" 2>/dev/null | awk -F'\t' -v u="$2" '{ split($5, d, " "); if (d[1] == u) print }'
}
# keel_unit_started <feature> <unit>: the last "started" row (exit 3 if none).
keel_unit_started() {
  local row
  row=$(keel_unit_rows "$1" "$2" | awk -F'\t' '$3 == "started" { last = $0 } END { if (last != "") print last }')
  [ -n "$row" ] || return 3
  printf '%s\n' "$row"
}
keel_unit_base() { keel_unit_started "$1" "$2" | awk -F'\t' '{ print $4 }'; }
keel_unit_intent() { keel_unit_started "$1" "$2" | awk -F'\t' '{ split($5, d, " "); print (d[2] == "" ? "n/a" : d[2]) }'; }
keel_unit_paths() { keel_unit_started "$1" "$2" | awk -F'\t' '{ split($5, d, " "); print d[3] }' | tr ',' '\n'; }
# keel_unit_last_status <feature> <unit>: status of the unit's last row.
keel_unit_last_status() { keel_unit_rows "$1" "$2" | awk -F'\t' '{ s = $3 } END { print s }'; }
# keel_unit_commit <feature> <unit>: the sha of an "ok" row after the last start (exit 1 if open).
keel_unit_commit() {
  local sha
  sha=$(keel_unit_rows "$1" "$2" | awk -F'\t' '$3 == "started" { sha = "" } $3 == "ok" { sha = $4 } END { print sha }')
  [ -n "$sha" ] || return 1
  printf '%s\n' "$sha"
}

# keel_path_kind <path>: production | test | doc | build | meta (data-model.md §7, keel-diff --kind).
keel_path_kind() {
  local p=$1 b=${1##*/}
  case "$p" in
    specs/* | .specify/* | .claude/*) echo meta; return ;;
    *.md | docs/* | */docs/* | LICENSE* | NOTICE*) echo doc; return ;;
  esac
  case "$b" in
    pom.xml | mvnw | mvnw.cmd | build.gradle | build.gradle.kts | settings.gradle | settings.gradle.kts | gradlew | gradlew.bat | \
      package.json | package-lock.json | pnpm-lock.yaml | yarn.lock | Makefile | go.mod | go.sum | Cargo.toml | Cargo.lock | \
      pyproject.toml | setup.py | setup.cfg | requirements*.txt) echo build; return ;;
  esac
  case "$p" in .mvn/* | */.mvn/* | .gitignore | */.gitignore | .gitattributes) echo build; return ;; esac
  case "$p" in
    src/test/* | */src/test/* | test/* | */test/* | tests/* | */tests/* | src/it/* | */src/it/*) echo test; return ;;
  esac
  case "$b" in *Test.java | *Tests.java | *IT.java | *_test.* | *.test.* | *.spec.* | *Spec.*) echo test; return ;; esac
  echo production
}
