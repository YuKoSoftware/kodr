---
phase: quick-260330-ck9
plan: 01
subsystem: zig_runner, interface, tests
tags: [library-output, bin-layout, unix-conventions]
dependency_graph:
  requires: []
  provides: [lib/ directory for library artifacts]
  affects: [src/zig_runner/zig_runner.zig, src/interface.zig, test/06_library.sh, test/07_multimodule.sh]
tech_stack:
  added: []
  patterns: [lib/ for .a/.so/.orh, bin/ for executables]
key_files:
  created: []
  modified:
    - src/zig_runner/zig_runner.zig
    - src/interface.zig
    - test/06_library.sh
    - test/07_multimodule.sh
decisions:
  - Both bin/ and lib/ created unconditionally in buildAll() (mixed-target projects have both)
  - In buildWithType(), bin/ or lib/ created conditionally based on is_lib
metrics:
  duration: ~5 minutes
  completed: 2026-03-30
---

# Phase quick-260330-ck9 Plan 01: Move Library Output to lib/ Summary

**One-liner:** Moved .a/.so library artifacts and .orh interface files from bin/ to lib/, leaving executables in bin/, following standard Unix conventions.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Change library and interface output paths from bin/ to lib/ | 93b2b96 | src/zig_runner/zig_runner.zig, src/interface.zig |
| 2 | Update library test expectations for lib/ paths | 8221589 | test/06_library.sh |

## Decisions Made

- **buildAll() creates both directories unconditionally:** Since multi-target projects contain a mix of executables and libraries, both `bin/` and `lib/` are created before the copy loop. This avoids per-target conditional logic in the loop body.
- **buildWithType() uses conditional makePath:** Single-target builds only create the relevant output directory (lib/ for libraries, bin/ for executables), keeping the working directory clean.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] test/07_multimodule.sh also checked bin/ for library files**
- **Found during:** Task 2 verification (./testall.sh run)
- **Issue:** 07_multimodule.sh had 3 checks for library files in bin/ (libmathlib.so, mathlib.orh, libutils.a) that would fail after the source change.
- **Fix:** Updated all 3 path checks to use lib/ instead of bin/.
- **Files modified:** test/07_multimodule.sh
- **Commit:** 70616d9

## Test Results

All 269 tests passed after changes:
- 06_library.sh: 12/12 passed
- 07_multimodule.sh: 13/13 passed
- ./testall.sh: 269/269 passed

## Self-Check: PASSED
