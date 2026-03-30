---
phase: 07-full-test-suite-gate
plan: 01
subsystem: testing
tags: [peg-builder, string-interpolation, mir, codegen, test-assertions]

# Dependency graph
requires:
  - phase: 06-polish-completeness
    provides: Interpolation codegen paths (generateInterpolatedString, generateInterpolatedStringMir) already implemented
provides:
  - PEG builder string interpolation: @{expr} in string literals now creates interpolated_string AST nodes
  - Full interpolation pipeline: builder -> MIR -> codegen produces correct Zig with allocPrint + defer free
  - Correct null union test assertions: ?T, == null, .? patterns (replaces OrhonNullable, .none, .some)
  - ./testall.sh green: all 236 tests pass, 0 failures, 11/11 stages
affects: [future-language-features, interpolation-expressions]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Builder-level string interpolation post-processing: no grammar change needed, scan STRING_LITERAL for @{ markers"
    - "InterpolatedPart arena-dupe: literal slices duped into arena allocator for lifetime safety"
    - "MIR temp_var hoisting: lowerBlock creates temp_var + injected_defer before statements with interpolation"
    - "Error-conditioned catch: interpolation catch pattern depends on funcReturnTypeClass() — catch unreachable for non-error functions"

key-files:
  created: []
  modified:
    - src/peg/builder.zig
    - src/mir.zig
    - src/codegen.zig
    - test/09_language.sh

key-decisions:
  - "Interpolation at builder level not grammar level — lexer correctly captures @{expr} as part of STRING_LITERAL token text; post-processing in buildStringLiteral is cleanest fix"
  - "catch unreachable vs catch |err| return err — check funcReturnTypeClass() to choose; non-error-returning functions (i32 etc) use unreachable; error-union functions propagate"
  - "MIR lowerBlock must copy interp_parts + expr children to temp_var node — temp_var is manually constructed, not going through lowerNode annotateNode path"
  - "markInterpolationReplacement sets injected_name on .interpolation MirNode — codegen .interpolation case checks injected_name first, emits var name if set (not allocPrint again)"

patterns-established:
  - "Interpolation: simple identifier expressions only (@{name}, @{x}) — complex exprs out of scope"

requirements-completed: [GATE-01]

# Metrics
duration: 13min
completed: 2026-03-25
---

# Phase 7 Plan 1: Full Test Suite Gate Summary

**PEG builder string interpolation wired end-to-end: @{expr} in .orh strings now produces interpolated_string AST nodes, MIR hoists allocPrint temp vars, codegen emits correct Zig — ./testall.sh 236/236 pass**

## Performance

- **Duration:** 13 min
- **Started:** 2026-03-25T08:43:38Z
- **Completed:** 2026-03-25T08:56:57Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Fixed 3 stale null union test assertions in test/09_language.sh (OrhonNullable/.none/.some → ?i32/== null/.?)
- Implemented string interpolation detection in buildStringLiteral — @{expr} creates InterpolatedPart slices
- Fixed 3 pre-existing MIR/codegen bugs exposed by the first real interpolated_string AST nodes
- All 236 tests pass across 11 test stages (previously 6 failures)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix 3 stale null union test assertions** - `ab229d3` (fix)
2. **Task 2: Add string interpolation to PEG builder** - `4c09fb5` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `test/09_language.sh` - Updated 3 null union assertions to check ?i32, == null, .? patterns
- `src/peg/builder.zig` - buildStringLiteral now detects @{...} and creates interpolated_string AST nodes
- `src/mir.zig` - lowerBlock: copy interp_parts + expr children to temp_var MirNode (bug fix)
- `src/codegen.zig` - .interpolation case: check injected_name first; catch pattern conditioned on funcReturnTypeClass()

## Decisions Made
- Interpolation implemented at builder level (not grammar level) — lexer already correctly preserves @{} in token text
- `catch unreachable` used instead of `catch |err| return err` when enclosing function has no error return type
- `markInterpolationReplacement` sets `injected_name` on `.interpolation` MirNode to signal temp-var replacement; codegen now respects this

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MIR lowerBlock did not copy interp_parts to temp_var node**
- **Found during:** Task 2 (string interpolation PEG builder)
- **Issue:** `lowerBlock` creates `temp_var` MirNode manually without going through `lowerNode`/`annotateNode`. So `interp_parts` and `children` (expr sub-nodes) were never set. Codegen emitted `const _orhon_interp_0 = ;` (empty RHS).
- **Fix:** Extract `interp.parts` from the AST node and lower expr children before creating temp_var; set `interp_parts` and `children` on the temp_var MirNode.
- **Files modified:** src/mir.zig
- **Verification:** Generated code shows correct `std.fmt.allocPrint(...)` call
- **Committed in:** 4c09fb5 (Task 2 commit)

**2. [Rule 1 - Bug] Codegen .interpolation case ignored injected_name — called generateInterpolatedStringMir again**
- **Found during:** Task 2 (string interpolation PEG builder)
- **Issue:** `markInterpolationReplacement` sets `injected_name` on the `.interpolation` MirNode to indicate the value is already in a temp var. But `generateExprMir` for `.interpolation` called `generateInterpolatedStringMir` unconditionally, producing a second (hoisted) `_interp_N` var alongside the existing `_orhon_interp_N`.
- **Fix:** Check `injected_name` first in the `.interpolation` case; emit the var name directly if set.
- **Files modified:** src/codegen.zig
- **Verification:** Generated code shows `const msg = _orhon_interp_0` (not double-allocation)
- **Committed in:** 4c09fb5 (Task 2 commit)

**3. [Rule 1 - Bug] interpolation codegen used `catch |err| return err` unconditionally — fails in non-error-returning functions**
- **Found during:** Task 2 (string interpolation PEG builder)
- **Issue:** `generateInterpolatedStringMirInline` and `generateInterpolatedStringMir` always emitted `catch |err| return err`, which is only valid when the enclosing function returns `anyerror!T`. Functions returning plain types like `i32` get a Zig compile error: "expected type 'i32', found 'error{OutOfMemory}'".
- **Fix:** Call `funcReturnTypeClass()` to check if we're in an error-returning function; emit `catch unreachable` for non-error functions and `catch |err| return err` for error-union functions.
- **Files modified:** src/codegen.zig
- **Verification:** test_interpolation() i32 and test_interpolation_int() i32 compile and pass
- **Committed in:** 4c09fb5 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 - Bug, pre-existing bugs exposed by the new interpolation AST nodes)
**Impact on plan:** All 3 auto-fixes were necessary for correctness. The MIR and codegen interpolation paths existed but were never exercised — these were latent bugs that only manifested once the PEG builder started producing interpolated_string nodes.

## Issues Encountered
None beyond the 3 auto-fixed bugs above.

## Next Phase Readiness
- Phase 07 gate achieved: ./testall.sh exits 0 with 236 tests, 0 failures
- v0.10 milestone complete — all phases 1-7 done
- String interpolation is now fully functional end-to-end for simple identifier expressions
- Complex interpolation expressions (@{a + b}, @{obj.field}) are not supported (out of scope, known limitation)

## Known Stubs
None — all functionality is fully wired. String interpolation works at runtime with correct output.

## Self-Check: PASSED
- `src/peg/builder.zig` contains `interpolated_string` and `InterpolatedPart` and `@{`
- `test/09_language.sh` contains `?i32`, `== null`, `.?` and does NOT contain `OrhonNullable`, `.none`, `.some`
- Commits ab229d3 and 4c09fb5 exist in git log
- ./testall.sh: 236/236 passed

---
*Phase: 07-full-test-suite-gate*
*Completed: 2026-03-25*
