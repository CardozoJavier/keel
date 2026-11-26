#!/bin/bash
# keel-verify (contracts/run-state.md): build/test detection, baseline semantics, fresh-report
# parsing, NEW-failure accounting against the baseline, and the guard environment for the build.
# A fake `mvn` stands in for Maven: it records its argv and writes surefire XML as told.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
V="$KEEL_PLUGIN_ROOT/bin/keel-verify"
L="$KEEL_PLUGIN_ROOT/bin/keel-ledger"
f=001-x
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

fakebin=$(t_tmp)
cat > "$fakebin/mvn" <<'FAKE'
#!/bin/sh
# fake mvn: FAKE_TESTS="pass:C#a fail:C#b" writes target/surefire-reports/TEST-C.xml; FAKE_EXIT; FAKE_LOG
echo "$*" > "${FAKE_ARGS:-/dev/null}"
[ -n "${FAKE_LOG:-}" ] && printf '%s\n' "$FAKE_LOG"
if [ -n "${FAKE_TESTS:-}" ]; then
  mkdir -p target/surefire-reports
  out=target/surefire-reports/TEST-fake.xml
  echo '<?xml version="1.0" encoding="UTF-8"?>' > "$out"
  echo '<testsuite name="fake" tests="2">' >> "$out"
  for t in $FAKE_TESTS; do
    st=${t%%:*}; id=${t#*:}; cls=${id%%#*}; m=${id#*#}
    if [ "$st" = pass ]; then echo "  <testcase name=\"$m\" classname=\"$cls\" time=\"0.01\"/>" >> "$out"
    else printf '  <testcase name="%s" classname="%s" time="0.01">\n    <failure message="boom">x</failure>\n  </testcase>\n' "$m" "$cls" >> "$out"; fi
  done
  echo '</testsuite>' >> "$out"
fi
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$fakebin/mvn"
export PATH="$fakebin:$PATH" KEEL_ROOT="$KEEL_PLUGIN_ROOT"
argsf=$(t_tmp)/args; export FAKE_ARGS="$argsf"

r=$(mk_repo)
printf '<project><dependencies><dependency><groupId>org.junit.jupiter</groupId><artifactId>junit-jupiter</artifactId><scope>test</scope></dependency></dependencies></project>\n' > "$r/pom.xml"
mkdir -p "$r/src/test/java/c"; echo 'class CTest {}' > "$r/src/test/java/c/CTest.java"
git -C "$r" add -A; git -C "$r" commit -q -m init
(cd "$r" && "$L" append $f branch ok "$(git -C "$r" rev-parse HEAD)" $f)
vr() { (cd "$r" && "$V" "$@" 2>&1); }

# --- detect ------------------------------------------------------------------------------------
out=$(vr detect)
assert_eq maven "$(kv "$out" BUILD)" "detect: maven"
assert_eq "mvn verify" "$(kv "$out" TESTCMD)" "detect: mvn verify without a wrapper"
assert_eq junit5 "$(kv "$out" TESTFW)" "detect: junit5 from the POM"
printf '#!/bin/sh\n' > "$r/mvnw"; chmod +x "$r/mvnw"
assert_eq "./mvnw verify" "$(kv "$(vr detect)" TESTCMD)" "detect: wrapper preferred"
rm "$r/mvnw"
assert_eq "make test" "$(kv "$(vr detect --host 'make test')" TESTCMD)" "detect: host command wins"
assert_eq host "$(kv "$(vr detect --host 'make test')" BUILD)" "detect: BUILD=host"
assert_eq junit5 "$(kv "$(vr detect --host 'mvn -q verify')" TESTFW)" "a host command keeps the POM's framework detection"
sb=$(mk_repo); printf '<project><dependencies><dependency><artifactId>spring-boot-starter-test</artifactId></dependency></dependencies></project>\n' > "$sb/pom.xml"
assert_eq junit5 "$(kv "$(cd "$sb" && "$V" detect)" TESTFW)" "spring-boot-starter-test implies JUnit 5"
nj=$(mk_repo); echo '<project/>' > "$nj/pom.xml"
assert_eq none "$(kv "$(cd "$nj" && "$V" detect)" TESTFW)" "a POM without a test framework: TESTFW=none"
assert_eq none "$(kv "$(cd "$nj" && "$V" detect --host 'mvn verify')" TESTFW)" "a host command over a POM without a test framework: TESTFW=none"
e=$(mk_repo); echo '# x' > "$e/README.md"; echo 'target/' > "$e/.gitignore"; echo MIT > "$e/LICENSE"
assert_eq none "$(kv "$(cd "$e" && "$V" detect)" BUILD)" "only docs and dotfiles: BUILD=none"
p=$(mk_repo); echo 'print(1)' > "$p/app.py"
assert_eq undetected "$(kv "$(cd "$p" && "$V" detect)" BUILD)" "sources without a known build: BUILD=undetected"

# --- baseline: green ---------------------------------------------------------------------------
out=$(FAKE_TESTS="pass:c.CTest#a pass:c.CTest#b" vr run $f --label baseline -- mvn verify); rc=$?
assert_eq 0 "$rc" "green baseline exits 0"
assert_eq pass "$(kv "$out" RESULT)" "green baseline passes"
assert_eq 0 "$(kv "$out" FAILING)" "no failures"
assert_eq present "$(kv "$out" TESTS)" "tests present"
assert_contains "$(cat "$argsf")" "-fae -Dmaven.test.failure.ignore=true" "baseline always adds keel's Maven flags"
assert_eq "mvn verify" "$(cat "$r/.git/keel/$f/verify/baseline.cmd")" "baseline.cmd is stored without keel's flags"

# later label, green baseline: no flags; a vanished test is NEW; a changed test file excuses it
out=$(FAKE_TESTS="pass:c.CTest#a" vr run $f --label T001 --kind behavior -- mvn verify)
assert_not_contains "$(cat "$argsf")" "maven.test.failure.ignore" "green baseline: later labels add no flags"
assert_eq fail "$(kv "$out" RESULT)" "a baseline test with no fresh report counts as NEW"
assert_eq 1 "$(kv "$out" NEW)" "NEW=1"
echo 'class CTest { /* renamed b */ }' > "$r/src/test/java/c/CTest.java"
out=$(FAKE_TESTS="pass:c.CTest#a" vr run $f --label T002 --kind behavior -- mvn verify)
assert_eq pass "$(kv "$out" RESULT)" "a test whose file the feature changed is excluded"
git -C "$r" checkout -q -- src/test/java/c/CTest.java
out=$(FAKE_TESTS="pass:c.CTest#a pass:c.CTest#b fail:c.CTest#c" FAKE_EXIT=1 FAKE_LOG="[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:3.2.5:test (default-test) on project x: There are test failures." vr run $f --label T003 --kind behavior -- mvn verify)
assert_eq fail "$(kv "$out" RESULT)" "a new failing test fails"
out=$(FAKE_TESTS="pass:c.CTest#a pass:c.CTest#b" vr run $f --label T004 -- mvn -q verify)
assert_eq pass "$(kv "$out" RESULT)" "a different command skips the missing-report clause and passes"
out=$(FAKE_EXIT=1 FAKE_LOG="[ERROR] Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin:3.13.0:compile (default-compile) on project x: Compilation failure" vr run $f --label T005 -- mvn verify)
assert_eq fail "$(kv "$out" RESULT)" "a compilation failure fails"

# stale reports are ignored; test sources with no fresh reports never pass as "no tests yet"
# (research R7.5: an IDE's ECJ classes in target/ made surefire run 0 tests)
out=$(vr run $f --label T006 --kind non-behavior -- mvn verify); rc=$?
assert_eq none "$(kv "$out" TESTS)" "reports older than the start marker are ignored"
assert_eq 1 "$rc" "test sources but no fresh reports fail"
assert_eq fail "$(kv "$out" RESULT)" "RESULT=fail"
assert_contains "$out" "MISSING=test-reports" "and name the missing test reports"
assert_contains "$out" "mvn clean" "with the stale build output hint"
out=$(vr run $f --label T007 --kind behavior -- mvn verify); rc=$?
assert_eq 1 "$rc" "a behavior unit with test sources but no reports fails the same way"
assert_contains "$out" "MISSING=test-reports" "MISSING=test-reports, not test-command"
nt=$(mk_repo)
printf '<project><dependencies><dependency><groupId>org.junit.jupiter</groupId><artifactId>junit-jupiter</artifactId><scope>test</scope></dependency></dependencies></project>\n' > "$nt/pom.xml"
mkdir -p "$nt/src/main/java/c"; echo 'class C {}' > "$nt/src/main/java/c/C.java"
git -C "$nt" add -A; git -C "$nt" commit -q -m init
(cd "$nt" && "$L" append $f branch ok "$(git -C "$nt" rev-parse HEAD)" $f)
out=$(cd "$nt" && "$V" run $f --label baseline -- mvn verify 2>&1)
assert_eq pass "$(kv "$out" RESULT)" "no test sources yet: the baseline passes"
assert_eq none "$(kv "$out" TESTS)" "with TESTS=none"
out=$(cd "$nt" && "$V" run $f --label T001 --kind behavior -- mvn verify 2>&1); rc=$?
assert_eq 3 "$rc" "behavior unit with no test sources and no reports: exit 3"
assert_contains "$out" "MISSING=test-command" "reports MISSING=test-command"

# --- baseline: red ---------------------------------------------------------------------------------
rr=$(mk_repo); echo '<project/>' > "$rr/pom.xml"; git -C "$rr" add -A; git -C "$rr" commit -q -m i
(cd "$rr" && "$L" append $f branch ok "$(git -C "$rr" rev-parse HEAD)" $f)
out=$(cd "$rr" && FAKE_TESTS="pass:d.DTest#a fail:d.DTest#old" "$V" run $f --label baseline -- mvn verify)
assert_eq pass "$(kv "$out" RESULT)" "red baseline still passes when it compiles"
assert_eq 1 "$(kv "$out" FAILING)" "red baseline records its failing set"
out=$(cd "$rr" && FAKE_TESTS="pass:d.DTest#a fail:d.DTest#old" "$V" run $f --label T001 -- mvn verify)
assert_contains "$(cat "$argsf")" "-Dmaven.test.failure.ignore=true" "red baseline: later labels add keel's flags"
assert_eq pass "$(kv "$out" RESULT)" "a pre-existing failure is not NEW"
out=$(cd "$rr" && FAKE_TESTS="pass:d.DTest#a fail:d.DTest#old fail:d.DTest#new" "$V" run $f --label T002 -- mvn verify)
assert_eq 1 "$(kv "$out" NEW)" "an additional failure is NEW"

# baseline restored from tasks.md after losing .git/keel
mkdir -p "$rr/specs/$f"; printf '# Tasks\n**Analyzed**: 2026-11-26 (baseline 1 failing; build maven; tests present; setup none)\n<!%s keel:baseline\ncmd: mvn verify\nfailing: d.DTest#old\n%s>\n' "--" "--" > "$rr/specs/$f/tasks.md"
rm -rf "$rr/.git/keel/$f/verify"
out=$(cd "$rr" && FAKE_TESTS="pass:d.DTest#a fail:d.DTest#old" "$V" run $f --label T003 -- mvn verify)
assert_eq pass "$(kv "$out" RESULT)" "failing set restored from tasks.md's keel:baseline comment"

# --- nothing to build; guard environment ---------------------------------------------------------
out=$(cd "$e" && "$V" run $f --label baseline -- none)
assert_eq pass "$(kv "$out" RESULT)" "nothing to build passes"
assert_eq none "$(kv "$out" BUILD)" "BUILD=none"
assert_contains "$out" "nothing to build or test" "says so"
out=$(cd "$r" && env -u GIT_CONFIG_COUNT "$V" run $f --label T008 -- sh -c 'echo "count=$GIT_CONFIG_COUNT"')
assert_contains "$out" "count=5" "the build runs with the push guard environment"

# --- record: the Analyzed line and keel:baseline comment, written from the baseline -------------
rec=$(mk_repo); printf '<project/>\n' > "$rec/pom.xml"; git -C "$rec" add -A; git -C "$rec" commit -q -m init
(cd "$rec" && "$L" append $f branch ok "$(git -C "$rec" rev-parse HEAD)" $f)
mkdir -p "$rec/specs/$f"
printf '# Tasks: x\n\n## Phase 1\n\n- [ ] T001 [US1] a in src/main/java/A.java (test: src/test/java/ATest.java)\n' > "$rec/specs/$f/tasks.md"
out=$(cd "$rec" && "$V" record $f --setup none 2>&1); rc=$?
assert_eq 3 "$rc" "record before a passing baseline exits 3"
assert_contains "$out" "MISSING=baseline" "and names the missing baseline"
assert_exit 1 "record rejects a bad --setup" -- sh -c "cd '$rec' && '$V' record $f --setup bogus"
(cd "$rec" && FAKE_TESTS="pass:p.PTest#a fail:p.PTest#should_fail-x fail:p.PTest#odd%name" "$V" run $f --label baseline -- mvn verify >/dev/null 2>&1)
out=$(cd "$rec" && "$V" record $f --setup T001); rc=$?
assert_eq 0 "$rc" "record after the baseline"
t=$(cat "$rec/specs/$f/tasks.md")
assert_contains "$t" "**Analyzed**: $(date +%Y-%m-%d) (baseline 2 failing; build maven; tests present; setup T001)" "the Analyzed line"
assert_contains "$t" "cmd: mvn verify" "the baseline command, without keel's flags"
assert_contains "$t" "failing: p.PTest#should_fail%2Dx" "a - in a test ID is escaped"
assert_contains "$t" "failing: p.PTest#odd%25name" "a % in a test ID is escaped"
assert_eq "# Tasks: x" "$(head -1 "$rec/specs/$f/tasks.md")" "the title stays first"
assert_contains "$t" "- [ ] T001 [US1]" "the tasks are kept"
cp "$rec/specs/$f/tasks.md" "$rec/once.md"
(cd "$rec" && "$V" record $f --setup T001 >/dev/null)
assert_eq "" "$(diff "$rec/once.md" "$rec/specs/$f/tasks.md")" "record is idempotent"
rm -f "$rec/once.md"
rm -rf "$rec/.git/keel/$f/verify"
out=$(cd "$rec" && FAKE_TESTS="pass:p.PTest#a fail:p.PTest#should_fail-x fail:p.PTest#odd%name" "$V" run $f --label T001 -- mvn verify)
assert_eq 0 "$(kv "$out" NEW)" "the recorded failing set round-trips through the restore path"
rec2=$(mk_repo); git -C "$rec2" commit -q --allow-empty -m init; mkdir -p "$rec2/specs/$f"
printf '# Tasks: y\n\n- [ ] T001 a\n' > "$rec2/specs/$f/tasks.md"
(cd "$rec2" && "$V" run $f --label baseline -- none >/dev/null && "$V" record $f --setup none >/dev/null)
assert_contains "$(cat "$rec2/specs/$f/tasks.md")" "(baseline 0 failing; build none; tests none; setup none)" "nothing to build is recorded as build none, tests none"
t_summary
