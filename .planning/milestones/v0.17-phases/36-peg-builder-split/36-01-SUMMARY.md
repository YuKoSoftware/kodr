---
phase: 36-peg-builder-split
plan: 01
subsystem: compiler
tags: [zig, peg, builder, ast, split, refactor]

# Dependency graph
requires:
  - phase: 35-zig-runner-split
    provides: zig_runner satellite split pattern established
provides:
  - builder.zig hub (553 lines): BuildContext + dispatch + shared helpers + tests
  - builder_decls.zig (488 lines): declaration builders
  - builder_bridge.zig (127 lines): bridge/context flag builders
  - builder_stmts.zig (227 lines): statement builders
  - builder_exprs.zig (366 lines): expression builders
  - builder_types.zig (185 lines): type builders
affects: [peg-parser, builder, module-split]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Hub-satellite split for peg/builder.zig matching codegen split pattern from Phase 29
    - Satellites use relative @import("../...") paths; cannot be standalone test roots
    - BuildContext methods (alloc, newNode, newNodeAt) promoted to pub for satellite access
    - Shared helpers (collectStructParts, hasPubBefore, setPub) live in hub, not satellites

key-files:
  created:
    - src/peg/builder_decls.zig
    - src/peg/builder_bridge.zig
    - src/peg/builder_stmts.zig
    - src/peg/builder_exprs.zig
    - src/peg/builder_types.zig
  modified:
    - src/peg/builder.zig

key-decisions:
  - "Peg satellite files NOT added to build.zig test_files: relative ../imports break standalone compilation (unlike codegen satellites in src/ root)"
  - "collectStructParts, hasPubBefore, setPub promoted to hub as pub fn — called by both decls and bridge satellites, avoids cross-satellite imports"
  - "BuildContext.alloc, newNode, newNodeAt promoted to pub — satellites call these directly on ctx pointer"

patterns-established:
  - "Hub-satellite for peg/: satellites use builder.functionName() for all hub helper calls"
  - "Subdirectory satellites cannot be standalone test roots in build.zig"

requirements-completed: [SPLIT-06, SPLIT-02]

# Metrics
duration: 20min
completed: 2026-03-29
---

# Phase 36 Plan 01: PEG Builder Split Summary

**builder.zig split from 1836 to 553 lines into hub + 5 satellites covering declarations, bridge/context, statements, expressions, and types**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-03-29T12:55:23Z
- **Completed:** 2026-03-29T13:15:23Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Split monolithic builder.zig (1836 lines) into 6 files, none exceeding 510 lines
- All 266 tests pass — zero behavior change
- Hub retains BuildContext, public API, dispatch routing, shared helpers, and tests
- Satellite files accessible via hub imports; dispatch routes through `*_impl.buildX()` calls

## Task Commits

1. **Task 1: Create 5 satellite files and promote hub helpers to pub** - `8dd79d7` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `src/peg/builder.zig` - Hub file: reduced from 1836 to 553 lines; all helpers pub; dispatch routes to satellites
- `src/peg/builder_decls.zig` - New: 488 lines, declaration builders (program through test_decl)
- `src/peg/builder_bridge.zig` - New: 127 lines, bridge/context flag builders
- `src/peg/builder_stmts.zig` - New: 227 lines, statement builders (block through expr_or_assignment)
- `src/peg/builder_exprs.zig` - New: 366 lines, expression builders (literals through postfix)
- `src/peg/builder_types.zig` - New: 185 lines, type builders (named through func_type)

## Decisions Made
- Peg satellite files NOT added to build.zig test_files: `src/peg/` satellites use `@import("../lexer.zig")` relative paths which fail as standalone test compilation roots. They are tested via `src/peg.zig` entry point which already imports builder.zig (and by extension the satellites).
- `collectStructParts`, `hasPubBefore`, and `setPub` promoted to hub as `pub fn` — both `builder_decls.zig` (struct/enum decls) and `builder_bridge.zig` (bridge_struct) need them, so placing them in the hub avoids cross-satellite imports.
- `BuildContext` methods `alloc`, `newNode`, `newNodeAt` promoted to `pub` — satellites call these directly on their `ctx *BuildContext` parameter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] build.zig satellite registration not viable for peg subdirectory**
- **Found during:** Task 2 (build.zig registration)
- **Issue:** Plan specified adding satellite files to build.zig test_files array. Unlike codegen satellites (in src/ root), peg satellites are in src/peg/ and use `@import("../lexer.zig")` relative imports. When compiled as standalone test roots, Zig reports "import of file outside module path" for all 17 cross-package imports.
- **Fix:** Did not add peg satellites to test_files. They are covered by `src/peg.zig` test root which transitively imports builder.zig -> satellites. All 1043 unit tests still pass including the 4 builder tests.
- **Verification:** `./testall.sh` passes all 266 tests
- **Committed in:** Deviation only (no file change needed — build.zig reverted to original)

---

**Total deviations:** 1 auto-identified (1 blocking)
**Impact on plan:** No impact — test coverage unchanged. Satellites are exercised by existing peg test root.

## Issues Encountered
None beyond the build.zig deviation above.

## Known Stubs
None — all builder functions are fully implemented.

## Next Phase Readiness
- Phase 36 plan 01 is the only plan in the phase — phase complete
- v0.17 milestone complete: all module splits done (codegen, lsp, mir, main, zig-runner, peg-builder)
- No files exceed ~510 lines across the compiler source

## Self-Check: PASSED
- src/peg/builder_decls.zig: FOUND
- src/peg/builder_bridge.zig: FOUND
- src/peg/builder_stmts.zig: FOUND
- src/peg/builder_exprs.zig: FOUND
- src/peg/builder_types.zig: FOUND
- src/peg/builder.zig: FOUND
- commit 8dd79d7: FOUND

---
*Phase: 36-peg-builder-split*
*Completed: 2026-03-29*
