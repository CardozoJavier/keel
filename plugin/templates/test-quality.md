# Test Quality: {{FEATURE}}
**Result**: resolved | not-run (<reason>)
**Base**: <sha> | **Tool**: PIT 1.30.2 + pitest-junit5-plugin 1.2.3 + junit-platform-launcher <version>
**Command**: `<the exact invocation from command.txt>` | **Module args**: -f <module>/pom.xml (sibling SNAPSHOTs from ~/.m2: <list or none>)
**Scope**: <n> classes in <modules>; changed lines only; tests: <selected test classes>; excluded tests: <failing at baseline / integration, or none>; not analyzed: <non-Java production files, or none>
**Summary**: <generated> mutants (<in-scope> in scope); killed <k>; coverage gaps <c>; assertion gaps <a>; triaged <t>; excluded <x>

## Gaps (in scope)

| Key | Location | Mutator | Status | Resolution |
|---|---|---|---|---|
| <key, first 7 chars> | <Class:line> | <mutator> | <SURVIVED / NO_COVERAGE / NO_TEST> | test `<Class#method>` (<FR-### or acceptance scenario>) / triaged: equivalent (<why no observable effect>) / triaged: not worth a test (<why>) |

## Redundancy and overlap (not blocking)

- redundant: `<C#t1>` (kills ⊂ `<C#t2>`)
- kills nothing: `<C#t3>`
- overlap: {`<C#t4>`, `<C#t5>`}: action: none | merged (identical behavior)

## Rounds

1. <YYYY-MM-DD>: <n> gaps → <n> tests, <n> triaged (MUT-<n>)

<!-- Result is computed: `resolved` only when keel-classify exits 0 after the last round (every in-scope
     gap killed by a test or triaged); `not-run (<reason>)` when keel-mutate exits 10. A halted mutate
     never writes this file. Raw output stays in .git/keel/<feature>/mut/ and is never committed. -->
