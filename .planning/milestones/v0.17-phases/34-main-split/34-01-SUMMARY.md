---
phase: 34-main-split
plan: "01"
subsystem: compiler-architecture
tags: [refactor, split, cli, init, stdlib, interface]
dependency_graph:
  requires: []
  provides: [src/cli.zig, src/init.zig, src/std_bundle.zig, src/interface.zig]
  affects: [src/main.zig, build.zig]
tech_stack:
  added: []
  patterns: [underscore-prefixed-imports, pub-const-reexports]
key_files:
  created:
    - src/cli.zig
    - src/init.zig
    - src/std_bundle.zig
    - src/interface.zig
  modified:
    - src/main.zig
    - build.zig
decisions:
  - "addToPath, emitZigProject, moveArtifactsToSubfolder kept in main.zig — move in Plan 02"
  - "cli - build target names test moved to cli.zig; pipeline tests remain in main.zig for Plan 02"
metrics:
  duration: "~20 minutes"
  completed: "2026-03-29"
  tasks: 2
  files: 6
requirements_satisfied: [SPLIT-04, SPLIT-02]
---

# Phase 34 Plan 01: Foundation Module Extraction Summary

**One-liner:** Extracted cli.zig, init.zig, std_bundle.zig, interface.zig from main.zig using underscore-prefixed imports and pub const re-exports; main.zig reduced from 2328 to 1600 lines.

## What Was Built

Four foundation modules extracted from `src/main.zig` as the first wave of the main-split refactor. Each module owns a distinct domain with no cross-dependencies between them.

### src/cli.zig (~220 lines)
- `pub const Command`, `BuildTarget`, `OptLevel` enums
- `pub const CliArgs` struct with `deinit` method
- `pub fn parseArgs()`, `printUsage()`, `printHelp()`
- `test "cli - build target names"` relocated here

### src/init.zig (~100 lines)
- 7 `@embedFile` template constants (main.orh + 6 example module files)
- `pub fn initProject()` — full project scaffolding logic

### src/std_bundle.zig (~160 lines)
- 42 `@embedFile` constants for all stdlib `.orh`/`.zig` pairs
- `STR_ZIG` and `COLLECTIONS_ZIG` marked `pub` for pipeline access
- `pub fn writeStdFile()`, `pub fn ensureStdFiles()`

### src/interface.zig (~230 lines)
- `fn formatType()`, `formatExprSimple()`, `emitFuncSig()`, `emitInterfaceDecl()` (private helpers)
- `pub fn generateInterface()` — generates `.orh` interface files for library builds

### src/main.zig updates
- Added `_cli`, `_init`, `_std_bundle`, `_interface` underscore-prefixed imports
- Added `pub const CliArgs`, `Command`, `BuildTarget` re-exports
- Delegated to new modules at all call sites
- Removed extracted sections; kept `addToPath`, `emitZigProject`, `moveArtifactsToSubfolder` (Plan 02)

## Verification

- `zig build test`: 0 errors, all unit tests pass (including relocated `cli - build target names`)
- `./testall.sh`: All 266 tests pass
- `wc -l src/main.zig`: 1600 lines (down from 2328, -728 lines)

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extract four foundation modules | b98b5fe | src/cli.zig, src/init.zig, src/std_bundle.zig, src/interface.zig, src/main.zig |
| 2 | Update build.zig test_files | ba561fd | build.zig |

## Deviations from Plan

**1. addToPath, emitZigProject, moveArtifactsToSubfolder retained in main.zig**
- **Found during:** Task 1 — initial extraction removed them along with interface section
- **Issue:** These functions are called from main.zig code that stays until Plan 02
- **Fix:** Kept the three functions in main.zig with comments noting they move in Plan 02
- **Files modified:** src/main.zig
- **Commit:** b98b5fe

No other deviations. Plan executed cleanly.

## Known Stubs

None.

## Self-Check: PASSED

- src/cli.zig exists: FOUND
- src/init.zig exists: FOUND
- src/std_bundle.zig exists: FOUND
- src/interface.zig exists: FOUND
- Commit b98b5fe exists: FOUND
- Commit ba561fd exists: FOUND
