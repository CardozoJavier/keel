# shellcheck shell=bash
# Shared body of keel's thin shims (push guard layer A, rule A7): tools that can publish without
# going through git or gh. Each shim sets KEEL_THIN_TOOL and sources this file. bash 3.2.

case "$0" in */*) _keel_shims_dir=${0%/*} ;; *) _keel_shims_dir=. ;; esac
_keel_shims_dir=$(cd -P "$_keel_shims_dir" && pwd) || { echo "keel: blocked publish (AF): cannot locate shim dir" >&2; exit 2; }
. "$_keel_shims_dir/../lib/shim-common.sh" || { echo "keel: blocked publish (AF): shim library missing" >&2; exit 2; }

keel_shim_enter "$KEEL_THIN_TOOL" "$@"
_keel_real=$(keel_shim_real "$KEEL_THIN_TOOL" "$_keel_shims_dir") || exit 127

# _words: the non-flag words of the argv (flags with values are rare for these subcommands).
_keel_w1= _keel_w2=
for _a in "$@"; do
  case "$_a" in
    -*) ;;
    *) if [ -z "$_keel_w1" ]; then _keel_w1=$_a; elif [ -z "$_keel_w2" ]; then _keel_w2=$_a; break; fi ;;
  esac
done
# jj's --repository/-R take a value that must not count as a word
if [ "$KEEL_THIN_TOOL" = "jj" ]; then
  _keel_w1= _keel_w2=
  _skip=0
  for _a in "$@"; do
    if [ "$_skip" -eq 1 ]; then _skip=0; continue; fi
    case "$_a" in
      -R | --repository | --at-op | --at-operation | --config | --config-toml) _skip=1 ;;
      -*) ;;
      *) if [ -z "$_keel_w1" ]; then _keel_w1=$_a; elif [ -z "$_keel_w2" ]; then _keel_w2=$_a; break; fi ;;
    esac
  done
fi

case "$KEEL_THIN_TOOL $_keel_w1 $_keel_w2" in
  "jj git push" | "sl push "* | "sl pr "* | "gt submit "* | "gt ss "* | "gt sync "* | \
    "glab mr create" | "glab mr merge" | "hub push "* | "hub pull-request "*)
    keel_shim_deny A7 "$KEEL_THIN_TOOL" "$@" ;;
esac
exec "$_keel_real" "$@"
