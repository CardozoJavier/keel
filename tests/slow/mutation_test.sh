#!/bin/bash
# Slow tier (SC-013, SC-014; needs JDK + Maven, downloads PIT on the first run): the real keel-mutate
# and keel-classify on a git copy of tests/fixtures/maven-weak. Every seeded weakness is reported, the
# build files are byte-identical before and after, and raw output exists only under .git/keel/.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
FX="$KEEL_REPO_ROOT/tests/fixtures/maven-weak"
M="$KEEL_PLUGIN_ROOT/bin/keel-mutate"; C="$KEEL_PLUGIN_ROOT/bin/keel-classify"
export KEEL_ROOT="$KEEL_PLUGIN_ROOT"
command -v mvn >/dev/null 2>&1 || { echo "SKIP: no mvn on PATH" >&2; t_summary; exit 0; }

r=$(mk_repo)
cp "$FX/pom.xml" "$FX/.gitignore" "$r/"; git -C "$r" add -A; git -C "$r" commit -q -m base
cp -R "$FX/src" "$r/"; git -C "$r" add -A; git -C "$r" commit -q -m feature
pom_before=$(git -C "$r" hash-object pom.xml)
untracked_before=$(git -C "$r" status --porcelain --ignored | grep -v '^!! target/$' | LC_ALL=C sort)
o="$r/.git/keel/001-weak/mut/1"
out=$(cd "$r" && "$M" --out "$o" --base HEAD~1 --budget 600 2>&1); rc=$?
assert_eq 0 "$rc" "keel-mutate succeeds on real Maven and PIT (out: $out)"
assert_eq 7 "$(printf '%s\n' "$out" | sed -n 's/^MUTANTS=//p')" "7 mutants, as in the fixture's reference run"
cls=$("$C" "$o/mutants.tsv"); crc=$?
assert_eq 1 "$crc" "the seeded gaps block"
while IFS="$(printf '\t')" read -r kind must weakness; do
  [ "$kind" = kind ] && continue
  assert_eq yes "$(printf '%s\n' "$cls" | grep "^$kind	" | grep -qF "$must" && echo yes)" "reported: $weakness ($kind $must)"
done < "$FX/expected.tsv"
assert_eq "$pom_before" "$(git -C "$r" hash-object pom.xml)" "pom.xml is byte-identical (SC-014)"
assert_eq no "$([ -e "$r/.mvn" ] && echo yes || echo no)" "no .mvn/ was created"
assert_eq "$untracked_before" "$(git -C "$r" status --porcelain --ignored | grep -v '^!! target/$' | LC_ALL=C sort)" "no new files outside .git/ and the ignored target/"
assert_eq yes "$([ -f "$o/root/pit/mutations.xml" ] && [ -f "$o/run.log" ] && echo yes)" "raw output lives under .git/keel/"
assert_eq "" "$(git -C "$r" log --format=%s -1 | grep -v '^feature$')" "keel-mutate commits nothing"

# --- multi-module, nothing installed: the changed module depends on a sibling SNAPSHOT (research R7.6) ----
mm=$(mk_repo)
cat > "$mm/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>
  <groupId>example.multi</groupId><artifactId>parent</artifactId><version>1.0.0-SNAPSHOT</version><packaging>pom</packaging>
  <modules><module>lib</module><module>app</module></modules>
  <properties><maven.compiler.release>21</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
  <dependencies><dependency><groupId>org.junit.jupiter</groupId><artifactId>junit-jupiter</artifactId><version>5.11.4</version><scope>test</scope></dependency></dependencies>
  <build><plugins><plugin><groupId>org.apache.maven.plugins</groupId><artifactId>maven-surefire-plugin</artifactId><version>3.2.5</version></plugin></plugins></build>
</project>
POM
mkdir -p "$mm/lib" "$mm/app"; cp -R "$FX/src" "$mm/lib/"
printf '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><parent><groupId>example.multi</groupId><artifactId>parent</artifactId><version>1.0.0-SNAPSHOT</version></parent><artifactId>lib</artifactId></project>\n' > "$mm/lib/pom.xml"
printf '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><parent><groupId>example.multi</groupId><artifactId>parent</artifactId><version>1.0.0-SNAPSHOT</version></parent><artifactId>app</artifactId><dependencies><dependency><groupId>example.multi</groupId><artifactId>lib</artifactId><version>1.0.0-SNAPSHOT</version></dependency></dependencies></project>\n' > "$mm/app/pom.xml"
printf 'target/\n' > "$mm/.gitignore"
git -C "$mm" add -A; git -C "$mm" commit -q -m base
mkdir -p "$mm/app/src/main/java/app" "$mm/app/src/test/java/app"
printf 'package app;\n\nimport weak.FeeCalculator;\n\npublic final class Checkout {\n    private final FeeCalculator fees = new FeeCalculator();\n\n    public long total(long amountMinor) {\n        return amountMinor + fees.feeMinor(amountMinor);\n    }\n}\n' > "$mm/app/src/main/java/app/Checkout.java"
printf 'package app;\n\nimport static org.junit.jupiter.api.Assertions.assertEquals;\n\nimport org.junit.jupiter.api.Test;\n\nclass CheckoutTest {\n    @Test\n    void should_add_fee_when_totalling() {\n        assertEquals(130, new Checkout().total(100));\n    }\n}\n' > "$mm/app/src/test/java/app/CheckoutTest.java"
git -C "$mm" add -A; git -C "$mm" commit -q -m checkout
rm -rf "$HOME/.m2/repository/example/multi"
mo="$mm/.git/keel/001-multi/mut/1"
out=$(cd "$mm" && "$M" --out "$mo" --base HEAD~1 --budget 600 2>&1); rc=$?
assert_eq 0 "$rc" "a submodule whose sibling SNAPSHOT is not installed (out: $out)"
assert_contains "$(cat "$mo/command.txt")" "-pl app -am" "runs in reactor mode"
assert_eq "app.Checkout" "$(tail -n +2 "$mo/mutants.tsv" | cut -f2 | sort -u)" "only the changed module's class is mutated"
assert_eq no "$([ -d "$HOME/.m2/repository/example/multi" ] && echo yes || echo no)" "nothing was installed into ~/.m2"
t_summary
