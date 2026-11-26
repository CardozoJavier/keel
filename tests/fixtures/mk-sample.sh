#!/bin/bash
# mk-sample.sh <dir> [fixture]: copy a fixture project (default sample-maven) into <dir> as a fresh
# git repository on main with one commit, and print its path. Used by evals and trials.
set -eu
dest=${1:?usage: mk-sample.sh <dir> [fixture]}
fixture=${2:-sample-maven}
src="$(cd "$(dirname "$0")" && pwd)/$fixture"
[ -d "$src" ] || { echo "no fixture: $src" >&2; exit 1; }
rm -rf "$dest"
mkdir -p "$dest"
cp -R "$src/." "$dest/"
printf 'target/\n' > "$dest/.gitignore"
cd "$dest"
git init -q -b main
git config user.email sample@example.invalid
git config user.name sample
git config commit.gpgsign false
git add -A
git commit -q -m "chore: initial sample project"
pwd -P
