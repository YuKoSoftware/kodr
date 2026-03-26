---
phase: 16-is-operator-qualified-types
plan: 01
subsystem: compiler
tags: [peg, grammar, parser, codegen, mir, is-operator, cross-module]

# Dependency graph
requires: []
provides:
  - "is operator accepts dotted type paths (module.Type) on RHS via PEG grammar"
  - "Builder produces field_expr chain for multi-segment is paths"
  - "Codegen emits @TypeOf(val) == mod.Type for qualified is checks (AST and MIR paths)"
  - "emitTypePath and emitTypeMirPath helpers for type-path emission without semantic transforms"
  - "IsTestType fixture struct and cross-module is tests in tester_main.orh"
  - "Stage 09 assertion: qualified is → @TypeOf codegen"
affects: [phase-17-unit-type, phase-18-type-alias, Tamga framework]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "emitTypePath/emitTypeMirPath: walk field_expr/field_access chains without semantic transforms"
    - "MIR-path is-check: field_access RHS handled alongside identifier RHS"

key-files:
  created: []
  modified:
    - "src/orhon.peg"
    - "src/peg/builder.zig"
    - "src/codegen.zig"
    - "test/fixtures/tester.orh"
    - "test/fixtures/tester_main.orh"
    - "test/09_language.sh"

key-decisions:
  - "Cross-module is tests placed in tester_main.orh (not tester.orh) since tester.zig cannot self-reference module name 'tester'"
  - "emitTypePath/emitTypeMirPath helpers emit type paths without semantic transforms (no handle.value, ptr.*, etc.)"
  - "MIR-path is-check needed field_access branch alongside existing identifier branch"
  - "Type inference (const x = tester.IsTestType(...)) used to avoid cross-module type annotation bug in var decls"

patterns-established:
  - "Type path emission pattern: separate helper functions that walk field_expr/field_access chains without applying runtime semantic transforms"
  - "is-check branches in both AST-path (generateExpr .binary_expr) and MIR-path (generateExprMir .binary) must stay in sync"

requirements-completed: [TAMGA-02]

# Metrics
duration: 45min
completed: 2026-03-26
---

# Phase 16 Plan 01: is Operator Qualified Types Summary

**Grammar, builder, and codegen changes enabling `ev is module.Type` cross-module type checks, emitting `@TypeOf(val) == mod.Type` Zig via new emitTypePath/emitTypeMirPath helpers; all 243 tests pass.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-03-26T06:00:00Z
- **Completed:** 2026-03-26T06:45:00Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- Extended PEG grammar `compare_expr` to accept `IDENTIFIER ('.' IDENTIFIER)*` on is RHS
- Builder now collects dotted token sequences and builds left-to-right `field_expr` chains
- Added `emitTypePath` (AST-path) and `emitTypeMirPath` (MIR-path) helpers that walk field chains without semantic transforms
- Added `field_expr`/`field_access` branches in both AST-path and MIR-path is-check codegen blocks
- Cross-module is tests in tester_main.orh produce `PASS is_qualified` and `PASS is_not_qualified` at runtime
- Stage 09 codegen assertion verifies `@TypeOf` pattern appears in generated tester.zig

## Task Commits

1. **Task 1: Grammar + Builder — parse dotted type paths on is RHS** - `daacc04` (feat)
2. **Task 2: Codegen — emit qualified type path for field_expr RHS in is checks** - `fb03502` (feat)
3. **Task 3: Test fixtures + assertions** - `4f9069a` (feat)

## Files Created/Modified

- `src/orhon.peg` - Extended compare_expr rule: `IDENTIFIER ('.' IDENTIFIER)* / 'null'`
- `src/peg/builder.zig` - Dotted-path scanning in buildCompareExpr; builds field_expr chain
- `src/codegen.zig` - emitTypePath, emitTypeMirPath helpers; field_expr/field_access branches in is-check codegen
- `test/fixtures/tester.orh` - Added `pub struct IsTestType` for cross-module is test
- `test/fixtures/tester_main.orh` - Added is_qualified and is_not_qualified cross-module is tests
- `test/09_language.sh` - Added `qualified is → @TypeOf codegen` assertion

## Decisions Made

- **Cross-module is tests in tester_main.orh, not tester.orh:** Zig-generated tester.zig cannot self-reference module name `tester`, so the test `x is tester.IsTestType` must live in main where `tester` is an imported namespace.
- **Type inference for variable declarations:** `const x = tester.IsTestType(...)` instead of annotated `const x: tester.IsTestType = ...` because cross-module type annotations in var decls have a separate pre-existing bug (generates `const x: tester` instead of `const x: tester.IsTestType`). Deferred that bug to future work.
- **Separate type-path helpers:** `emitTypePath` and `emitTypeMirPath` are needed because the normal `generateExpr`/`generateExprMir` for `field_access` applies runtime semantic transforms (thread handle getValue, ptr.*, etc.) that corrupt type names.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed struct literal syntax in fixture**
- **Found during:** Task 3 (test fixtures)
- **Issue:** Plan example used `IsTestType { val: 42 }` which doesn't parse (Orhon uses parenthesized named args `IsTestType(val: 42)`, not brace syntax)
- **Fix:** Changed to `IsTestType(val: 42)` — PEG validation unit test caught the error immediately
- **Files modified:** test/fixtures/tester.orh
- **Verification:** `zig build test` passed after fix
- **Committed in:** 4f9069a (Task 3 commit)

**2. [Rule 1 - Bug] Added MIR-path field_access branch**
- **Found during:** Task 3 (end-to-end test revealed codegen issue)
- **Issue:** Plan specified AST-path codegen fix but the compiler uses MIR-path for most expressions. Without a MIR-path `field_access` branch, the is-check fell through to the generic binary path, producing `/* unknown @type */` and `tester catch unreachable`
- **Fix:** Added `emitTypeMirPath` helper and `rhs_mir.kind == .field_access` branch in `generateExprMir` .binary case
- **Files modified:** src/codegen.zig
- **Verification:** `./testall.sh` all 243 tests pass
- **Committed in:** fb03502 (Task 2 commit, same file)

**3. [Rule 1 - Bug] Cross-module is tests moved to tester_main.orh**
- **Found during:** Task 3 (runtime test failed with `undeclared identifier 'tester'`)
- **Issue:** Plan specified test functions in tester.orh, but `tester.IsTestType` inside tester.zig is invalid Zig (can't self-reference module name)
- **Fix:** Removed test functions from tester.orh (kept only the struct); added inline cross-module is checks directly in tester_main.orh where `tester` is an imported module
- **Files modified:** test/fixtures/tester.orh, test/fixtures/tester_main.orh
- **Verification:** PASS is_qualified and PASS is_not_qualified appear in runtime output
- **Committed in:** 4f9069a (Task 3 commit)

---

**Total deviations:** 3 auto-fixed (3 bugs)
**Impact on plan:** All auto-fixes necessary for correctness. The MIR-path fix was a critical missing piece not anticipated by the plan. No scope creep.

## Issues Encountered

- `any` type annotation for local variables emits `any` in Zig which is not a valid local variable type (only valid as comptime parameter type). The test was redesigned to avoid `any` in local vars. This is a potential future issue if Orhon ever allows `any`-typed locals.
- Cross-module type annotation in var decls has a pre-existing bug: `const x: tester.IsTestType` generates `const x: tester` (loses the field). This was avoided by using type inference. Deferred to `deferred-items.md`.

## Known Stubs

None - all new functionality is fully wired and produces correct runtime output.

## Next Phase Readiness

- `is module.Type` is fully working for cross-module qualified type checks
- Tamga framework can now use `ev is sdl.KeyboardEvent` pattern
- Phase 17 (Unit type in return position) can proceed independently

---
*Phase: 16-is-operator-qualified-types*
*Completed: 2026-03-26*
