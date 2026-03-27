---
phase: 22-throw-statement
plan: 02
subsystem: tests-docs
tags: [tests, docs, example, error-handling, throw]

# Dependency graph
requires:
  - phase: 22-throw-statement
    plan: 01
    provides: throw statement full pipeline implementation
provides:
  - throw example in example module (compiles and tests via orhon build)
  - negative test fixture for throw in void function
  - codegen pattern checks in test/09_language.sh
  - throw error tests in test/11_errors.sh
  - throw Statement documentation in docs/08-error-handling.md
affects: [test suite, example module, documentation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "token_map.zig LITERAL_MAP: every new keyword token must have an entry mapping the string literal to its TokenKind"

key-files:
  created:
    - test/fixtures/fail_throw.orh
  modified:
    - src/templates/example/error_handling.orh
    - src/peg/token_map.zig
    - test/09_language.sh
    - test/11_errors.sh
    - docs/08-error-handling.md

key-decisions:
  - "Use const (not var) for result in divide_with_throw — throw does not reassign the variable, so const is correct and avoids a warning"
  - "Token map fix is part of this plan's commit — required for throw grammar to match at all"

# Metrics
duration: 20min
completed: 2026-03-27
---

# Phase 22 Plan 02: throw Statement Tests and Documentation Summary

**throw feature verified end-to-end: example module compiles, codegen pattern checked, negative tests catch invalid usage, docs document the syntax and semantics.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-03-27
- **Tasks:** 2
- **Files modified:** 5 (+ 1 created)

## Accomplishments

- Example module demonstrates `divide_with_throw` — compiles cleanly, test "throw propagation" passes
- Negative fixture `test/fixtures/fail_throw.orh` exercises throw in void function (ERR-03)
- test/09_language.sh checks generated Zig for `|_err| return _err` pattern (ERR-01) and `catch unreachable` narrowing (ERR-02)
- test/11_errors.sh `rejects throw in void function` confirms propagation checker error fires
- docs/08-error-handling.md has a `## throw Statement` section with syntax, requirements, semantics, and before/after example
- Full test suite: 256 tests, all pass (up from 253)

## Task Commits

1. **Task 1: Add throw to example module and create negative test fixture** — `5033ed8`
2. **Task 2: Add test checks, update docs, fix token_map** — `ecc049c`

## Files Created/Modified

- `src/templates/example/error_handling.orh` — Added `divide_with_throw()` and `test "throw propagation"`
- `test/fixtures/fail_throw.orh` — Created negative fixture with `void_throw()` error case
- `src/peg/token_map.zig` — Added missing `"throw"` → `.kw_throw` LITERAL_MAP entry
- `test/09_language.sh` — Added two codegen checks: `|_err| return _err` and `catch unreachable`
- `test/11_errors.sh` — Added `neg_throw` section testing throw in void function
- `docs/08-error-handling.md` — Added `## throw Statement` section

## Decisions Made

- `const result` instead of `var result` in the example — throw doesn't reassign the variable, so `const` is correct and avoids a warning
- token_map fix included in Task 2 commit — it was a blocking bug directly caused by Plan 01's omission

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Missing kw_throw in token_map.zig LITERAL_MAP**

- **Found during:** Task 2 verification (testall.sh)
- **Issue:** Plan 01 added `kw_throw` to the lexer and `throw_stmt` to the PEG grammar, but forgot to add `"throw" → .kw_throw` to `src/peg/token_map.zig`. The LITERAL_MAP maps string literals in grammar rules to their `TokenKind` — without this entry, the PEG engine couldn't match `'throw'` and the grammar rule never fired.
- **Symptom:** `zig build test` reported `peg - validate templates/example/error_handling.orh` FAIL; orhon build reported "unexpected 'throw'"
- **Fix:** Added `.{ "throw", .kw_throw }` to LITERAL_MAP in `src/peg/token_map.zig`
- **Files modified:** `src/peg/token_map.zig`
- **Commit:** `ecc049c`

**2. [Rule 1 - Bug] Example uses const instead of var**

- **Found during:** Task 1 (review after token_map fix)
- **Issue:** Plan spec said `var result` but throw does not reassign the variable — using `var` triggers a "use const instead" warning
- **Fix:** Changed `var result` to `const result` in `divide_with_throw`
- **Files modified:** `src/templates/example/error_handling.orh`
- **Commit:** `ecc049c`

## Known Stubs

None — all throw functionality is fully wired. The example compiles, tests pass, docs are accurate.

## Self-Check: PASSED

All files exist and commits are verified:
- `5033ed8` — feat(22-02): add throw example and negative test fixture
- `ecc049c` — feat(22-02): add throw tests, docs, and fix token_map
- All 256 tests pass
