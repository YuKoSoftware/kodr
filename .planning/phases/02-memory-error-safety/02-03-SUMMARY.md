---
phase: 02-memory-error-safety
plan: 03
subsystem: compiler
tags: [parser, peg, grammar, pointer, mir, codegen]

# Dependency graph
requires: []
provides:
  - "Ptr(T).cast(addr) and RawPtr(T).cast(addr) grammar and AST support"
  - "ptr_cast_expr PEG rule producing ptr_expr nodes directly"
  - "tester.orh migrated to .cast() method-style constructors"
  - "example/data_types.orh migrated to .cast() method-style constructor"
affects: [09_language, 10_runtime, example_module]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ptr_cast_expr is a dedicated primary_expr alternative — cast keyword conflict avoided without touching method_call rule"
    - "New grammar rules for keyword-named methods use dedicated primary_expr alternatives, not method_call extension"

key-files:
  created: []
  modified:
    - src/orhon.peg
    - src/peg/builder.zig
    - test/fixtures/tester.orh
    - src/templates/example/data_types.orh

key-decisions:
  - "Dedicated ptr_cast_expr grammar rule instead of extending method_call — cast is a reserved keyword, adding it to method_call would have broader scope implications"
  - "buildPtrCastExpr produces ptr_expr AST node — no MIR or codegen changes needed, existing ptr_expr pipeline handles it"

patterns-established:
  - "Keyword-as-method-name: use dedicated primary_expr grammar rule, not method_call extension"

requirements-completed: [MEM-04]

# Metrics
duration: 18min
completed: 2026-03-24
---

# Phase 02 Plan 03: .cast() Pointer Constructor Summary

**ptr_cast_expr grammar rule added — Ptr(T).cast(addr) and RawPtr(T).cast(addr) produce ptr_expr AST nodes; tester and example module migrated to new syntax**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-24T17:06:41Z
- **Completed:** 2026-03-24T17:25:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `ptr_cast_expr` PEG grammar rule supporting `Ptr(T).cast(addr)` / `RawPtr(T).cast(addr)` / `VolatilePtr(T).cast(addr)` syntax
- `buildPtrCastExpr` in `builder.zig` converts the new syntax to a `ptr_expr` AST node — zero MIR or codegen changes required
- Migrated all 3 pointer constructor sites in `tester.orh` and 1 site in `example/data_types.orh` to `.cast()` style
- Old `Ptr(T, addr)` syntax preserved for backward compatibility

## Task Commits

1. **Task 1: Add .cast() method-style constructor recognition** - `0093da2` (feat)
2. **Task 2: Migrate tester.orh and example module to .cast() syntax** - `5a86971` (feat)

## Files Created/Modified

- `src/orhon.peg` - Added `ptr_cast_expr` rule and registered it in `primary_expr` before `ptr_expr`
- `src/peg/builder.zig` - Added `buildPtrCastExpr` builder function and dispatch entry
- `test/fixtures/tester.orh` - Migrated 3 sites: RawPtr(i32, &x) x2, Ptr(i32, &x) x1
- `src/templates/example/data_types.orh` - Migrated 1 site: Ptr(i32, &x)

## Decisions Made

- Used a dedicated `ptr_cast_expr` grammar rule rather than extending `method_call` to accept the `cast` keyword. The `cast` keyword is a compiler builtin — adding it to `method_call` would be broader than needed and could have unintended side effects. A specific rule is more precise and self-documenting.
- `buildPtrCastExpr` produces a `ptr_expr` AST node directly, so the existing MIR annotator, MIR lowerer, and codegen paths for `ptr_expr` work without any changes.

## Deviations from Plan

None - plan executed exactly as written. The MIR annotator changes described in the plan (intercepting call_expr patterns) turned out to be unnecessary because the grammar-level fix produces `ptr_expr` nodes directly.

## Issues Encountered

- `cast` is a reserved keyword (`kw_cast` token), so `Ptr(i32).cast(&x)` cannot parse via the existing `method_call` rule which only accepts `IDENTIFIER`. Solved by adding a dedicated grammar production `ptr_cast_expr` that explicitly references the `cast` keyword token.

## Next Phase Readiness

- All pointer constructor sites in tester and example use `.cast()` syntax
- Old syntax backward compatible — no existing `.orh` code will break
- Pre-existing test failures in 09_language and 10_runtime stages are unrelated to this plan (they involve List/Map collection constructors generating `i32.new()` invalid Zig)

---
*Phase: 02-memory-error-safety*
*Completed: 2026-03-24*
