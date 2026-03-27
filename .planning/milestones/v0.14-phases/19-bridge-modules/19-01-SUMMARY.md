---
phase: 19-bridge-modules
plan: 01
subsystem: codegen
tags: [zig-build, bridge-modules, named-modules, build-graph, createModule]

requires:
  - phase: none
    provides: existing bridge module architecture with file-path imports

provides:
  - Bridge .zig sidecars registered as named Zig modules in generated build.zig
  - Bridge-to-bridge imports wired via addImport for cross-module type sharing
  - linkC libraries applied to bridge modules instead of lib/exe targets
  - Codegen emits named-module imports for bridge re-exports

affects: [tamga, multi-module-projects, bridge-declarations]

tech-stack:
  added: []
  patterns: [named-zig-modules-for-bridges, bridge-module-build-graph]

key-files:
  created: []
  modified:
    - src/zig_runner.zig
    - src/codegen.zig
    - src/main.zig
    - test/05_compile.sh

key-decisions:
  - "Bridge modules registered via Zig build system createModule/addImport instead of file-path @import"
  - "Single-target path collects all bridge modules (root + non-root) for build.zig generation"
  - "Multi-target path uses extra_bridge_modules parameter for non-root bridge modules"
  - "linkC libraries applied to bridge modules, not to lib/exe artifact targets"

patterns-established:
  - "Named bridge modules: buildZigContent/Multi create bridge_X modules for each module with has_bridges=true"
  - "Extra bridge modules: non-root modules with bridges passed as separate slice to build generators"

requirements-completed: [REQ-19]

duration: 18min
completed: 2026-03-26
---

# Phase 19 Plan 01: Bridge Named Modules Summary

**Bridge .zig sidecar files registered as named Zig modules via createModule/addImport, eliminating file-path imports and cross-module duplicate module errors**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-26T18:10:36Z
- **Completed:** 2026-03-26T18:29:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Bridge .zig files are registered as named Zig modules in generated build.zig for both single and multi-target builds
- Bridge-to-bridge imports wired via addImport so cross-module bridge type sharing works without file-path conflicts
- #linkC libraries applied to bridge modules (not lib/exe targets) keeping C linking scoped correctly
- Codegen emits @import("module_bridge") instead of @import("module_bridge.zig") for named module resolution
- All 251 existing tests pass without regression

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand MultiTarget and collect bridge/linkC data** - `db06fe1` (feat)
2. **Task 2: Rewrite buildZigContentMulti for named bridge modules** - `bf9a697` (feat)

## Files Created/Modified
- `src/zig_runner.zig` - MultiTarget struct with link_libs/has_bridges fields; buildZigContent and buildZigContentMulti create named bridge modules; new unit test for bridge module generation
- `src/codegen.zig` - generateBridgeReExport uses named module import (no .zig extension)
- `src/main.zig` - Collects link_libs, has_bridges, and bridge module names for both single and multi-target paths
- `test/05_compile.sh` - Updated sidecar test assertion for named module import format

## Decisions Made
- Bridge modules registered via Zig build system createModule/addImport instead of file-path @import -- eliminates "file exists in two modules" errors when bridge modules import types from other bridges
- Single-target path collects ALL modules with bridges (root and non-root) since a single exe may depend on non-root modules that have bridge declarations
- Multi-target path uses extra_bridge_modules parameter for non-root bridge modules that aren't represented as MultiTarget entries
- linkC libraries applied to bridge modules, not lib/exe artifact targets -- keeps C linking scoped to the bridge that declares the dependency

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Single-target buildZigContent also needed bridge module support**
- **Found during:** Task 2 (full test suite run)
- **Issue:** Codegen change to named imports affected both single and multi-target paths, but plan only addressed multi-target. Single-target builds failed with "no module named 'X_bridge'"
- **Fix:** Added bridge_modules parameter to buildZigContent, generateBuildZig, and runTests; collect all bridge modules (root + non-root) in main.zig single-target path
- **Files modified:** src/zig_runner.zig, src/main.zig
- **Verification:** All 251 tests pass
- **Committed in:** bf9a697 (Task 2 commit)

**2. [Rule 3 - Blocking] Non-root modules with bridges need registration in multi-target path**
- **Found during:** Task 2 (multimodule test failures)
- **Issue:** Multi-target buildZigContentMulti only registered bridges for root modules (MultiTarget entries), but non-root modules like console also have bridges
- **Fix:** Added extra_bridge_modules parameter to buildAll and buildZigContentMulti; collect non-root bridge module names in main.zig multi-target loop
- **Files modified:** src/zig_runner.zig, src/main.zig
- **Verification:** All 251 tests pass including 07_multimodule
- **Committed in:** bf9a697 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes were necessary for the codegen change to work across all build paths. No scope creep -- these are direct consequences of the named-module approach.

## Issues Encountered
None beyond the deviations above.

## Known Stubs
None -- all functionality is fully wired.

## Next Phase Readiness
- Bridge modules are now first-class named Zig modules in the build graph
- Tamga project can use bridge-to-bridge imports without "file exists in modules" errors
- Ready for any future phases that add new bridge modules or cross-bridge dependencies

---
*Phase: 19-bridge-modules*
*Completed: 2026-03-26*
