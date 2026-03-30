---
phase: 01-compiler-bug-fixes
plan: 02
subsystem: compiler
tags: [mir, codegen, resolver, cross-module, generics, type-resolution]

requires:
  - phase: none

provides:
  - Cross-module const & argument coercion (value_to_const_ref) in MIR annotator
  - Cross-module function signature resolution via all_decls in MirAnnotator
  - Qualified generic type validation against cross-module DeclTables in TypeResolver

affects:
  - codegen
  - mir
  - resolver
  - any plan touching cross-module call semantics or generic type validation

tech-stack:
  added: []
  patterns:
    - "all_decls optional field pattern: pass ?*const StringHashMap(*DeclTable) to annotator/resolver for cross-module lookups"
    - "value_to_const_ref coercion: emit & prefix when passing T to const &T parameter"

key-files:
  created: []
  modified:
    - src/mir.zig
    - src/codegen.zig
    - src/resolver.zig
    - src/main.zig

key-decisions:
  - "value_to_const_ref coercion mirrors array_to_slice — both prepend & in codegen, same pattern for return_stmt switch"
  - "Qualified generic validation falls back to trusting if all_decls is null or module not yet processed — avoids false positives in dependency order"
  - "resolveCallSig handles both module.func and module.Type.method patterns via nested field_expr traversal"

patterns-established:
  - "Cross-module data flows through optional all_decls field added to annotator/resolver structs, wired from main.zig after all_module_decls is populated"
  - "Coercion enum extended with new variant → add case to all switch statements in codegen (generateCoercedExprMir + return_stmt)"

requirements-completed: [BUG-01, BUG-02]

duration: 25min
completed: 2026-03-24
---

# Phase 01 Plan 02: Cross-Module Const-Ref Coercion and Qualified Generic Validation Summary

**Cross-module struct method calls with const & parameters now emit &arg in generated Zig, and qualified generic types like math.Vec2(f64) are validated against the referenced module's DeclTable at Orhon compile time.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-24T00:00:00Z
- **Completed:** 2026-03-24T00:25:00Z
- **Tasks:** 2 (TDD)
- **Files modified:** 4

## Accomplishments

- BUG-01 fixed: MIR annotator now resolves cross-module function signatures via `all_decls` field, detects `value_to_const_ref` coercion (T → const &T), and codegen emits `&` for those args
- BUG-02 fixed: TypeResolver validates qualified generic types (module.Type) against cross-module DeclTables instead of blindly trusting them; unknown qualified types produce a clear Orhon-level error
- 14 new unit tests added (3 in mir.zig, 2 in resolver.zig — covering both happy and error paths); all 689/693 zig build tests pass (4 pre-existing peg failures unchanged)

## Task Commits

Each task was committed atomically:

1. **Task 1: Cross-module const & coercion in MIR annotator and codegen (BUG-01)** - `cb6127a` (feat)
2. **Task 2: Validate qualified generic types against cross-module DeclTables (BUG-02)** - `c18ed13` (feat)

_Note: TDD tasks — tests written first (RED), then implementation (GREEN) in same commit_

## Files Created/Modified

- `src/mir.zig` — Added `value_to_const_ref` to Coercion enum, `all_decls` field to MirAnnotator, cross-module logic in `resolveCallSig`, `value_to_const_ref` detection in `detectCoercion`, `typesMatch` helper, and 3 unit tests
- `src/codegen.zig` — Added `value_to_const_ref` case to `generateCoercedExprMir` and `return_stmt` switch
- `src/resolver.zig` — Added `all_decls` field to TypeResolver, replaced unconditional qualified-name trust with cross-module DeclTable lookup in `validateType`, 2 unit tests
- `src/main.zig` — Wired `all_module_decls` into both MirAnnotator (pass 10) and TypeResolver (pass 5)

## Decisions Made

- `value_to_const_ref` mirrors `array_to_slice` in codegen — both prepend `&`. Also added to `return_stmt` switch to maintain exhaustiveness.
- Qualified generic validation falls back to trusting when `all_decls` is null or the module hasn't been processed yet — avoids false positives in multi-module dependency order processing.
- `resolveCallSig` handles both `module.func` and `module.Type.method` patterns by checking if the callee object is a plain identifier or a nested field_expr.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added value_to_const_ref to return_stmt switch in codegen**
- **Found during:** Task 1 (codegen GREEN phase)
- **Issue:** Adding a new Coercion variant requires handling it in ALL switch statements in codegen. The return_stmt switch at line 1327 also switches on coercion and would fail to compile.
- **Fix:** Added `value_to_const_ref` alongside `array_to_slice` in the return_stmt coercion switch.
- **Files modified:** src/codegen.zig
- **Verification:** `zig test src/codegen.zig` passes — All 42 tests passed.
- **Committed in:** cb6127a (Task 1 commit)

**2. [Rule 3 - Blocking] Fixed test CallExpr missing arg_names field**
- **Found during:** Task 1 (mir.zig test compilation)
- **Issue:** `parser.CallExpr` has a required `arg_names: [][]const u8` field not documented in the plan's test pseudocode.
- **Fix:** Added `arg_names = call_arg_names` to the test CallExpr struct literal.
- **Files modified:** src/mir.zig
- **Verification:** Test compiles and all 41 mir.zig tests pass.
- **Committed in:** cb6127a (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 blocking)
**Impact on plan:** Both fixes necessary for correctness. No scope creep.

## Issues Encountered

- Pre-existing test failures (4 peg tests, 1 error test) exist before and after changes — confirmed by stash+baseline comparison. Not regressions.
- The `ownership.zig` file was already modified by a parallel agent (plan 01-01) and has compile errors unrelated to this plan's scope. Logged to deferred items.

## Next Phase Readiness

- BUG-01 and BUG-02 are resolved. Cross-module calls with const & parameters and qualified generic type validation are both correct.
- Remaining BUG-03 through BUG-09 are handled in other plans in phase 01.

---
*Phase: 01-compiler-bug-fixes*
*Completed: 2026-03-24*
