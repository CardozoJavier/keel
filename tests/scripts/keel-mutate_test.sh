#!/bin/bash
# keel-mutate (contracts/mutation-runner.md §keel-mutate), fast tier: scope, test selection,
# preconditions (exit 10), red/flaky (exit 11), fail-closed checks (exit 12), the B′ invocation and
# the mutants.tsv output, against a fake mvn. tests/slow/mutation_test.sh runs real Maven and PIT.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
M="$KEEL_PLUGIN_ROOT/bin/keel-mutate"
FX="$KEEL_REPO_ROOT/tests/fixtures"
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

fakebin=$(t_tmp); repo_m2=$(t_tmp)
cat > "$fakebin/mvn" <<'FAKE'
#!/bin/bash
# fake mvn for keel-mutate: answers the pinned goals keel-mutate uses; FAKE_* steer it
printf '%s\n' "$*" >> "$FAKE_ARGS"
# getarg <prefix> <args...>: the value of the first argument starting with <prefix> (a function, because
# bash 3.2 can't parse a case pattern inside $( ))
getarg() { local p=$1 a; shift; for a in "$@"; do case "$a" in "$p"*) printf '%s' "${a#"$p"}"; return ;; esac; done; }
case " $* " in
  *maven-dependency-plugin:3.8.1:list*)
    out=$(getarg -DoutputFile= "$@")
    { echo "The following files have been resolved:"
      [ -z "${FAKE_NO_ENGINE:-}" ] && echo "   org.junit.platform:junit-platform-engine:jar:1.11.4:test -- module org.junit.platform.engine"
    } > "$out"; exit 0 ;;
  *maven-dependency-plugin:3.8.1:get*)
    art=$(getarg -Dartifact= "$@")
    g=${art%%:*}; rest=${art#*:}; a=${rest%%:*}; v=${rest#*:}
    mkdir -p "$FAKE_REPO/$(printf '%s' "$g" | tr . /)/$a/$v" && touch "$FAKE_REPO/$(printf '%s' "$g" | tr . /)/$a/$v/$a-$v.jar"; exit 0 ;;
  *maven-help-plugin:3.5.1:evaluate*)
    case " $* " in *" -pl "*) [ -n "${FAKE_NO_REACTOR:-}" ] && { echo "[ERROR] Could not find the selected project in the reactor"; exit 1; } ;; esac
    printf 'WARNING: noise\n%s' "$FAKE_REPO"; exit 0 ;;
  *maven-help-plugin:3.5.1:effective-pom*)
    out=$(getarg -Doutput= "$@")
    { echo "<project>"; [ -n "${FAKE_HOST_PIT:-}" ] && echo "<plugin><artifactId>pitest-maven</artifactId></plugin>"; echo "</project>"; } > "$out"; exit 0 ;;
  *pitest-maven:1.30.2:mutationCoverage*)
    [ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
    rd=$(getarg -DreportsDirectory= "$@")
    printf '%s\n' "${FAKE_PIT_LOG:-PIT >> INFO : Largest test (x) covered 5 blocks}"
    if [ "${FAKE_XML:-}" != none ]; then mkdir -p "$rd"; cp "$FAKE_XML" "$rd/mutations.xml"; fi
    exit "${FAKE_PIT_EXIT:-0}" ;;
  *" test "*)
    n=$(cat "$FAKE_STATE/test-runs" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_STATE/test-runs"
    set -- ${FAKE_TEST_EXITS:-0 0}; shift $((n - 1)) 2>/dev/null || true
    exit "${1:-0}" ;;
esac
echo "fake mvn: unexpected: $*" >&2; exit 99
FAKE
chmod +x "$fakebin/mvn"
export PATH="$fakebin:$PATH" FAKE_REPO="$repo_m2" FAKE_XML="$FX/pit/weak-mutations.xml"

# a git copy of maven-weak: base has only the build files, HEAD adds the class and its test
mkrepo() {
  local r; r=$(mk_repo)
  cp "$FX/maven-weak/pom.xml" "$FX/maven-weak/.gitignore" "$r/"
  git -C "$r" add -A; git -C "$r" commit -q -m base
  cp -R "$FX/maven-weak/src" "$r/"
  git -C "$r" add -A; git -C "$r" commit -q -m feature
  printf '%s\n' "$r"
}
run() { # run <repo> <args...>: keel-mutate in <repo>, fresh fake state; sets out and rc
  local r=$1; shift
  export FAKE_ARGS; FAKE_ARGS=$(t_tmp)/args; export FAKE_STATE; FAKE_STATE=$(t_tmp)
  out=$(cd "$r" && "$M" "$@" 2>&1); rc=$?
}

# --- feature mode on the weak fixture ----------------------------------------------------------------
r=$(mkrepo); base=$(git -C "$r" rev-parse HEAD~1); o="$r/.git/keel/x/mut/1"
run "$r" --out "$o" --base "$base"
assert_eq 0 "$rc" "feature mode exits 0 (out: $out)"
t="$o/mutants.tsv"
assert_eq "$(printf 'key\tclass\tmethod\tline\tmutator\tstatus\tin_scope\tkilling\tsucceeding')" "$(head -1 "$t" 2>/dev/null)" "mutants.tsv header"
assert_eq 7 "$(tail -n +2 "$t" | grep -c .)" "one row per mutant"
assert_eq 7 "$(tail -n +2 "$t" | awk -F'\t' '$7 == "yes"' | grep -c .)" "a new file: every mutant in scope"
assert_eq 7 "$(tail -n +2 "$t" | cut -f1 | grep -cE '^[0-9a-f]{40}$')" "keys are SHA-1"
want=$(printf '%s' 'weak.FeeCalculator|feeMinor|(J)J|org.pitest.mutationtest.engine.gregor.mutators.MathMutator|11' | git hash-object --stdin)
assert_eq "$want" "$(tail -n +2 "$t" | awk -F'\t' '$4 == 8 && $5 ~ /MathMutator$/ { print $1 }')" "the key is sha1(class|method|desc|mutator|indexes), no line"
pit=$(grep 'mutationCoverage' "$FAKE_ARGS")
assert_contains "$pit" "-f pom.xml" "PIT runs per module with -f"
assert_contains "$pit" 'test-compile org.pitest:pitest-maven:1.30.2:mutationCoverage' "the B′ invocation compiles tests first"
assert_contains "$pit" '-DtargetClasses=weak.FeeCalculator,weak.FeeCalculator$*' "targets the class and its inner classes"
assert_contains "$pit" "-DtargetTests=weak.FeeCalculatorTest" "targets the selected unit tests"
assert_contains "$pit" "-DfullMutationMatrix=true" "full matrix"
assert_contains "$pit" "-DoutputFormats=XML" "XML output"
assert_contains "$pit" "-DreportsDirectory=$o/" "raw reports under --out"
assert_contains "$pit" "pitest-junit5-plugin-1.2.3.jar" "the JUnit 5 plugin jar is added"
assert_contains "$pit" "junit-platform-launcher-1.11.4.jar" "the launcher matching the platform version is added"
assert_not_contains "$pit" " -q" "the PIT run is not quiet (fail-closed checks read its log)"
assert_eq 0 "$(grep -cw install "$FAKE_ARGS")" "never install"
assert_contains "$(grep ' test ' "$FAKE_ARGS" | head -1)" "-Dtest=weak.FeeCalculatorTest" "the red check runs the selection"
assert_eq 2 "$(grep -c ' test ' "$FAKE_ARGS")" "the selection runs twice (red, then flaky)"
assert_eq "" "$(git -C "$r" status --porcelain)" "nothing tracked or untracked changes in the repo"
assert_contains "$(cat "$o/command.txt" 2>/dev/null)" "mutationCoverage" "the exact command is recorded for test-quality.md"
assert_eq "$t" "$(kv "$out" MUTANTS_TSV)" "prints MUTANTS_TSV="

# from a subdirectory, and only line 11 changed since the base
echo '// touch' >> "$r/src/main/java/weak/FeeCalculator.java"; git -C "$r" commit -qam touch
sed -i '' 's/return Math.max(fee, 30);/return Math.max(fee, 30); \/\/ floor/' "$r/src/main/java/weak/FeeCalculator.java"; git -C "$r" commit -qam floor
base2=$(git -C "$r" rev-parse HEAD~1)
run "$r/src" --out "$r/.git/keel/x/mut/2" --base "$base2"
assert_eq 0 "$rc" "runs from a subdirectory"
assert_eq "11" "$(tail -n +2 "$r/.git/keel/x/mut/2/mutants.tsv" | awk -F'\t' '$7 == "yes" { print $4 }' | sort -u | tr '\n' ' ' | sed 's/ $//')" "only mutants on changed lines are in scope"

# --- preconditions: exit 10 ---------------------------------------------------------------------------
run "$r" --out "$r/.git/keel/x/mut/3" --base HEAD
assert_eq 10 "$rc" "no changed Java class: exit 10"; assert_contains "$out" "nothing to analyze" "reason"
np=$(mk_repo); git -C "$np" commit -q --allow-empty -m base; mkdir -p "$np/src/main/java/a"; echo 'package a; class A {}' > "$np/src/main/java/a/A.java"; git -C "$np" add -A; git -C "$np" commit -qm a
run "$np" --out "$np/.git/keel/x/mut" --base HEAD~1
assert_eq 10 "$rc" "no ancestor pom.xml: exit 10"; assert_contains "$out" "not a Maven project" "reason"
FAKE_NO_ENGINE=1 run "$r" --out "$o.ne" --base "$base"
assert_eq 10 "$rc" "no JUnit Platform: exit 10"; assert_contains "$out" "JUnit Platform not found" "reason"
FAKE_HOST_PIT=1 run "$r" --out "$o.hp" --base "$base"
assert_eq 10 "$rc" "host configures PIT: exit 10"; assert_contains "$out" "host configures PIT" "reason"

# --- red and flaky: exit 11 ---------------------------------------------------------------------------
FAKE_TEST_EXITS="1" run "$r" --out "$o.red" --base "$base"
assert_eq 11 "$rc" "selected tests fail: exit 11"; assert_contains "$out" "RESULT=red" "red"
FAKE_TEST_EXITS="0 1" run "$r" --out "$o.flaky" --base "$base"
assert_eq 11 "$rc" "pass then fail: exit 11"; assert_contains "$out" "RESULT=flaky" "flaky"

# --- fail-closed: exit 12 -----------------------------------------------------------------------------
FAKE_PIT_EXIT=1 run "$r" --out "$o.f1" --base "$base"
assert_eq 12 "$rc" "check 1: Maven fails"
FAKE_XML=none run "$r" --out "$o.f1b" --base "$base"
assert_eq 12 "$rc" "check 1: no mutations.xml"
FAKE_PIT_LOG="JUnit 5 is on the classpath but the pitest junit 5 plugin is not installed" run "$r" --out "$o.f2" --base "$base"
assert_eq 12 "$rc" "check 2: the JUnit 5 plugin is missing"
nocov=$(t_tmp)/nocov.xml; sed -E 's#<coveringTests>[^<]*</coveringTests>#<coveringTests></coveringTests>#; s#<killingTests>[^<]*</killingTests>#<killingTests></killingTests>#; s#status=.KILLED.#status='"'"'NO_COVERAGE'"'"'#' "$FX/pit/weak-mutations.xml" > "$nocov"
FAKE_XML="$nocov" FAKE_PIT_LOG="PIT >> INFO : Ran 0 tests" run "$r" --out "$o.f3" --base "$base"
assert_eq 12 "$rc" "check 3: tests selected but nothing covered and no test ran (R5's silent false negative)"
assert_contains "$out" "silent" "says why"
runerr=$(t_tmp)/runerr.xml; sed -E "s/status='(SURVIVED|NO_COVERAGE)'/status='RUN_ERROR'/" "$FX/pit/weak-mutations.xml" > "$runerr"
FAKE_XML="$runerr" run "$r" --out "$o.f4" --base "$base"
assert_eq 12 "$rc" "check 4: RUN_ERROR above 10% of viable mutants"
start=$(date +%s)
FAKE_SLEEP=20 run "$r" --out "$o.f5" --base "$base" --budget 3
assert_eq 12 "$rc" "check 5: the budget is enforced"
assert_contains "$out" "budget" "says budget"
assert_eq yes "$([ $(( $(date +%s) - start )) -lt 15 ] && echo yes)" "the watchdog stops the run early"

# --- selection: NO_TEST, integration tests, baseline failures, --tests, audit mode ----------------------
r2=$(mkrepo); b2=$(git -C "$r2" rev-parse HEAD~1)
mkdir -p "$r2/src/main/java/weak/other"
printf 'package weak.other;\n\npublic final class Untested {\n    public int one() {\n        return 1;\n    }\n}\n' > "$r2/src/main/java/weak/other/Untested.java"
printf 'package weak;\n\n@org.springframework.boot.test.context.SpringBootTest\nclass FeeCalculatorSpringTest {\n    FeeCalculator c;\n}\n' > "$r2/src/test/java/weak/FeeCalculatorSpringTest.java"
printf 'package weak;\n\nclass FeeCalculatorIT {\n    FeeCalculator c;\n}\n' > "$r2/src/test/java/weak/FeeCalculatorIT.java"
printf 'package weak;\n\nclass ReportTest {\n    void x() { new FeeCalculator().feeMinor(1); }\n}\n' > "$r2/src/test/java/weak/ReportTest.java"
git -C "$r2" add -A; git -C "$r2" commit -qm more
run "$r2" --out "$r2/.git/keel/x/mut/1" --base "$b2"
assert_eq 0 "$rc" "selection run exits 0 (out: $out)"
pit=$(grep mutationCoverage "$FAKE_ARGS")
assert_contains "$pit" "weak.ReportTest" "a test that references the class by name is selected"
assert_not_contains "$pit" "FeeCalculatorIT" "*IT tests are excluded"
assert_not_contains "$pit" "FeeCalculatorSpringTest" "@SpringBootTest tests are excluded"
assert_contains "$pit" "weak.other.Untested" "test classes changed in the feature are candidates for every changed class (its mutants show as NO_COVERAGE)"
# a class changed alone, with no test that names or references it: NO_TEST rows, no PIT run
r3=$(mkrepo)
mkdir -p "$r3/src/main/java/weak/other"
printf 'package weak.other;\n\npublic final class Untested {\n    public int one() {\n        return 1;\n    }\n}\n' > "$r3/src/main/java/weak/other/Untested.java"
git -C "$r3" add -A; git -C "$r3" commit -qm untested
run "$r3" --out "$r3/.git/keel/x/mut/1" --base HEAD~1
assert_eq 0 "$rc" "a class with no selected test still exits 0 (out: $out)"
assert_eq 0 "$(grep -c mutationCoverage "$FAKE_ARGS")" "it is not sent to PIT"
assert_contains "$(cat "$r3/.git/keel/x/mut/1/command.txt")" "PIT not run" "command.txt says why there is no command"
nt=$(tail -n +2 "$r3/.git/keel/x/mut/1/mutants.tsv" | awk -F'\t' '$6 == "NO_TEST"')
assert_eq "weak.other.Untested" "$(printf '%s\n' "$nt" | cut -f2 | sort -u)" "it gets NO_TEST rows instead"
assert_eq yes "$(printf '%s\n' "$nt" | awk -F'\t' '$7 == "yes" && $1 ~ /^[0-9a-f]{40}$/' | grep -q . && echo yes)" "in scope, with a SHA-1 key"
want=$(printf '%s' 'weak.other.Untested|NO_TEST|src/main/java/weak/other/Untested.java:1+7' | git hash-object --stdin)
assert_eq "$want" "$(printf '%s\n' "$nt" | cut -f1)" "the NO_TEST key is sha1(class|NO_TEST|file:start+count)"
mkdir -p "$r2/specs/001-x"; printf '# Tasks\n<!-- keel:baseline\ncmd: mvn verify\nfailing: weak.ReportTest#x\n-->\n' > "$r2/specs/001-x/tasks.md"
run "$r2" --out "$r2/.git/keel/x/mut/2" --base "$b2" --feature 001-x
assert_not_contains "$(grep mutationCoverage "$FAKE_ARGS")" "weak.ReportTest" "a test class failing at baseline is removed from the selection"
assert_contains "$(cat "$r2/.git/keel/x/mut/2/excluded-tests.txt" 2>/dev/null)" "weak.ReportTest" "and reported as excluded"
run "$r2" --out "$r2/.git/keel/x/mut/3" --base "$b2" --tests weak.FeeCalculatorTest --classes weak.FeeCalculator
assert_contains "$(grep mutationCoverage "$FAKE_ARGS")" "-DtargetTests=weak.FeeCalculatorTest " "--tests overrides the selection"
assert_eq 0 "$(tail -n +2 "$r2/.git/keel/x/mut/3/mutants.tsv" | grep -c Untested)" "--classes restricts the classes"
run "$r2" --out "$r2/.git/keel/x/mut/4" --module .
assert_eq 0 "$rc" "audit mode exits 0"
assert_eq 0 "$(tail -n +2 "$r2/.git/keel/x/mut/4/mutants.tsv" | awk -F'\t' '$7 != "yes"' | grep -c .)" "audit mode: everything in scope"
run "$r2" --out "$r2/.git/keel/x/mut/5"
assert_eq 1 "$rc" "neither --base nor --module: usage error"

# --- multi-module: reactor mode (-pl <module> -am) when the root reactor builds the module, so sibling
# SNAPSHOTs come from the reactor and nothing needs installing; -f <module>/pom.xml otherwise (R7.6)
mm=$(mk_repo)
printf '<project><modules><module>app</module></modules></project>\n' > "$mm/pom.xml"
mkdir -p "$mm/app"; cp "$FX/maven-weak/pom.xml" "$mm/app/pom.xml"; printf 'target/\n' > "$mm/.gitignore"
git -C "$mm" add -A; git -C "$mm" commit -q -m base
cp -R "$FX/maven-weak/src" "$mm/app/"; git -C "$mm" add -A; git -C "$mm" commit -q -m feature
run "$mm" --out "$mm/.git/keel/x/mut/1" --base HEAD~1
assert_eq 0 "$rc" "a submodule in a reactor (out: $out)"
pit=$(grep mutationCoverage "$FAKE_ARGS")
assert_contains "$pit" "-pl app -am" "reactor mode builds the module with its upstream modules"
assert_contains "$pit" "-DfailWhenNoMutations=false" "upstream modules without targets don't fail the run"
assert_contains "$(grep ' test ' "$FAKE_ARGS" | head -1)" "-pl app -am" "the red check runs in reactor mode too"
assert_contains "$(grep 'dependency-plugin:3.8.1:list' "$FAKE_ARGS")" "-pl app -am" "and the classpath check"
FAKE_NO_REACTOR=1 run "$mm" --out "$mm/.git/keel/x/mut/2" --base HEAD~1
assert_eq 0 "$rc" "a reactor that can't build the module falls back"
assert_contains "$(grep mutationCoverage "$FAKE_ARGS")" "-f app/pom.xml" "to -f <module>/pom.xml"
assert_not_contains "$(grep mutationCoverage "$FAKE_ARGS")" " -pl " "without -pl"
t_summary
