---
phase: 01-compiler-bug-fixes
plan: 01
subsystem: ownership-checker, zig-runner, codegen
tags: [bug-fix, ownership, test-runner, codegen, tdd]
requires: []
provides: [BUG-03-fix, BUG-04-fix]
affects: [src/ownership.zig, src/zig_runner.zig, src/codegen.zig, test/fixtures/tester.orh, src/templates/example/data_types.orh]
tech-stack:
  added: []
  patterns: [TDD red-green, writer-abstraction, auto-import-injection]
key-files:
  created: []
  modified:
    - src/ownership.zig
    - src/zig_runner.zig
    - src/codegen.zig
    - test/fixtures/tester.orh
    - src/templates/example/data_types.orh
decisions:
  - "Const values are implicitly copyable — is_const field added to VarState rather than a separate copy-type mechanism"
  - "Auto-inject _orhon_str and _orhon_collections imports in generated Zig files when not explicitly imported — safe because build.zig always provides these modules"
  - "Fixture syntax updated to 2-arg RawPtr/Ptr constructor instead of implementing .cast() grammar extension"
metrics:
  duration: ~40 minutes
  completed: "2026-03-24T16:16:00Z"
  tasks_completed: 2
  files_changed: 5
---

# Phase 01 Plan 01: Ownership False-Positive and Test Output Fix Summary

Fix ownership false-positive on const values (BUG-03) and broken `orhon test` output caused by fixture syntax errors and missing stdlib auto-imports (BUG-04).

## Tasks Completed

### Task 1: Fix const values treated as moved on by-value pass (BUG-03)

**Commit:** `c35c3ac feat(01-01): fix const values treated as moved on by-value pass (BUG-03)`

Added `is_const: bool` field to `VarState` in `src/ownership.zig`. The ownership checker's `checkExpr` identifier branch was marking all non-primitive, non-borrowed identifiers as moved. Const values are implicitly copyable in Orhon (like Rust's `Copy` trait for simple types) and should never be marked moved.

Changes:
- `VarState` struct: added `is_const: bool` field
- `define()`: initializes `is_const = false` (function params, for-loop captures are not const)
- `defineTyped()`: added `is_const` parameter, stored in `VarState`
- `checkStatement`: detects `const_decl` and `compt_decl` → sets `is_const = true`
- `checkExpr` identifier branch: guard changed from `!is_primitive` to `!is_primitive and !is_const`
- 2 new unit tests: "const value reuse allowed" and "var value still moves"

### Task 2: Fix orhon test output format mismatch (BUG-04)

**Commit:** `b99c538 fix(01-01): fix orhon test output and auto-import stdlib modules (BUG-04)`

Root cause was multi-layered:
1. `tester.orh` and `data_types.orh` used unsupported `.cast()` method syntax (`RawPtr(i32).cast(&x)`) — updated to documented 2-arg constructor form (`RawPtr(i32, &x)`)
2. Generated Zig files didn't import `_orhon_str` and `_orhon_collections` when those modules weren't explicitly imported in the Orhon source — caused "undeclared identifier 'str'" and "undeclared identifier 'collections'" errors
3. `formatTestOutput` was not directly unit-testable (wrote to stderr directly)

Changes:
- `src/zig_runner.zig`: Extracted `writeTestOutput` free function accepting generic writer — `formatTestOutput` now delegates to it; added 2 unit tests
- `src/codegen.zig`: Auto-inject `const str = @import("_orhon_str");` and `const collections = @import("_orhon_collections");` at generated file header when user hasn't explicitly imported them
- `test/fixtures/tester.orh`: Updated 3 `.cast()` usages to 2-arg form
- `src/templates/example/data_types.orh`: Updated 1 `.cast()` usage to 2-arg form

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Auto-import stdlib modules in codegen**
- **Found during:** Task 2 investigation
- **Issue:** Generated Zig files referenced `str.X()` and `collections.X` without importing them when user code didn't have explicit `import std::str` or `import std::collections`. The build.zig always provides `_orhon_str` and `_orhon_collections` as named modules, but generated `.zig` files weren't importing them.
- **Fix:** Added auto-import logic in `codegen.zig` `generateFile()` after processing explicit imports — when `str_import_alias` or `collections_import_alias` is still null, emit the import with default alias names.
- **Files modified:** `src/codegen.zig`
- **Commit:** `b99c538`

**2. [Rule 1 - Bug] Fixture syntax used unimplemented .cast() grammar**
- **Found during:** Task 2 investigation
- **Issue:** `tester.orh` and `data_types.orh` used `RawPtr(T).cast(&x)` which the PEG grammar doesn't support (`.cast` is tokenized as `kw_cast`, not `IDENTIFIER`, so it can't appear in method_call rule)
- **Fix:** Updated to documented 2-arg constructor form `RawPtr(T, &x)` and `Ptr(T, &x)`
- **Files modified:** `test/fixtures/tester.orh`, `src/templates/example/data_types.orh`
- **Commit:** `b99c538`

**3. [Rule 2 - Testability] Extracted writeTestOutput for unit testing**
- **Found during:** Task 2 TDD phase
- **Issue:** `formatTestOutput` wrote directly to stderr, making it untestable
- **Fix:** Extracted `writeTestOutput(allocator, stderr, all_passed, writer)` free function; `formatTestOutput` now wraps it with the stderr writer
- **Files modified:** `src/zig_runner.zig`
- **Commit:** `b99c538`

## Decisions Made

1. **Const values are implicitly copyable** — `is_const` added to `VarState` rather than introducing a separate `CopyType` category. This keeps the ownership model simple: const = always copyable, primitives = always copyable, everything else = move semantics.

2. **Auto-inject stdlib imports** — Rather than requiring all Orhon programs to explicitly import `std::str` and `std::collections` to use built-in string/collection operations, the codegen now auto-imports them. This matches user expectations (string methods "just work") and is safe since build.zig always provides these modules.

3. **Fixture syntax updated, not grammar extended** — The `.cast()` grammar extension would require updating `method_call` rule in `orhon.peg` to allow keyword tokens as method names. This is a non-trivial grammar change with potential ambiguity implications. Using the documented 2-arg constructor form is simpler and matches the spec.

## Verification Results

- `zig build test --summary all`: **697/697 tests passed** (up from 675/679 — pre-existing peg failures resolved as side effect)
- `bash test/05_compile.sh`: **17/17 passed** (was partially failing)
- `bash test/01_unit.sh`: PASS
- `bash test/02_build.sh`: PASS

## Known Stubs

None — all functionality is fully implemented.

## Deferred Issues

- `test/09_language.sh` "tester module compiles" fails due to pre-existing codegen bugs:
  - `i32.new()` collection constructors generate invalid Zig (`type 'i32' has no members`)
  - `[*]i32` array initialization syntax error for RawPtr index operations
  - These are separate codegen bugs (different from BUG-04) tracked in docs/TODO.md

## Self-Check: PASSED

All files confirmed present:
- `.planning/phases/01-compiler-bug-fixes/01-01-SUMMARY.md` — FOUND
- `src/ownership.zig` — FOUND
- `src/zig_runner.zig` — FOUND
- `src/codegen.zig` — FOUND

All commits confirmed:
- `c35c3ac` feat(01-01): fix const values treated as moved — FOUND
- `b99c538` fix(01-01): fix orhon test output — FOUND
