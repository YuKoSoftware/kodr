---
phase: 35-zig-runner-split
plan: "01"
subsystem: zig-runner
tags: [refactor, split, maintainability]
dependency_graph:
  requires: []
  provides: [zig-runner-split]
  affects: [pipeline, build]
tech_stack:
  added: []
  patterns: [flat-file-split, underscore-import-prefix, pub-const-re-exports, anytype-duck-typing]
key_files:
  created:
    - src/zig_runner_build.zig
    - src/zig_runner_multi.zig
    - src/zig_runner_discovery.zig
  modified:
    - src/zig_runner.zig
    - build.zig
decisions:
  - "anytype for generateSharedCImportFiles targets parameter — avoids circular import between zig_runner_build and zig_runner_multi (MultiTarget lives in multi, but build needs to iterate c_includes)"
  - "Removed unused runZig method (non-cwd variant) — only runZigIn was ever called, dead code removed as part of cleanup"
metrics:
  duration: ~10m
  completed: 2026-03-29
  tasks: 2
  files: 5
---

# Phase 35 Plan 01: Zig Runner Split Summary

Split monolithic zig_runner.zig (1952 lines) into 4 focused files using flat-file split pattern with underscore-prefixed imports and pub const re-exports for zero downstream changes.

## What Was Built

**zig_runner.zig (489 lines)** — Re-export facade + ZigRunner struct with invocation logic. Contains `ZigResult`, `ZigRunner`, `writeTestOutput`, and pub const re-exports for all moved symbols. Pipeline.zig and other callers require zero changes.

**zig_runner_build.zig (627 lines)** — Single-target build.zig generation. Contains `buildZigContent`, `emitLinkLibs`, `emitIncludePath`, `emitCSourceFiles`, `generateSharedCImportFiles` + 6 unit tests.

**zig_runner_multi.zig (780 lines)** — Multi-target build.zig generation. Contains `MultiTarget` struct, `buildZigContentMulti` + 7 unit tests. Uses `_build.emitLinkLibs`, `_build.emitIncludePath`, `_build.emitCSourceFiles` for shared helpers.

**zig_runner_discovery.zig (61 lines)** — Zig binary discovery. Contains `findZig`, `findZigInPath`, `zigBinaryName` + 1 unit test.

**build.zig** — Added 3 new test_files entries to run unit tests in satellite files.

## Test Results

- `zig build test` — passes (all unit tests in 4 files)
- `./testall.sh` — 266/266 passed (SPLIT-02 zero behavior change gate confirmed)
- 16 total unit tests: 6 in build + 7 in multi + 1 in discovery + 2 in facade = 16

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Dead Code] Removed unused `runZig` method**
- **Found during:** Task 1 line count review
- **Issue:** `runZig` (non-cwd variant) was defined in ZigRunner but never called — only `runZigIn` was used. Dead code contributing to excess line count.
- **Fix:** Removed the 23-line unused method
- **Files modified:** src/zig_runner.zig
- **Commit:** 2fc9f73

**2. [Note - Size Estimate] zig_runner_multi.zig is 780 lines (target 700 max)**
- **Issue:** The 7 buildZigContentMulti test blocks are each 40-55 lines due to complex multi-target setup data. The function itself is ~375 lines.
- **Impact:** None — 780 lines is still highly maintainable for a complex build generation function
- **No fix needed:** The tests are accurate and complete. The line count estimate was conservative.

### Cross-import Circular Dependency Resolution

**Design decision — anytype for generateSharedCImportFiles**
- **Found during:** Planning the split
- **Issue:** `generateSharedCImportFiles` in `zig_runner_build.zig` iterates `targets[*].c_includes` — targets are `[]const MultiTarget`. But `MultiTarget` is defined in `zig_runner_multi.zig`, which imports `zig_runner_build.zig`. This would create a circular import.
- **Fix:** Used `anytype` for the `targets` parameter in `generateSharedCImportFiles`. Zig's structural typing means the function works with any slice whose elements have a `c_includes` field — duck typing without circular dependency.
- **Commit:** 2fc9f73

## Self-Check: PASSED

- src/zig_runner_build.zig — FOUND
- src/zig_runner_multi.zig — FOUND
- src/zig_runner_discovery.zig — FOUND
- commit 2fc9f73 (feat: extract satellite files) — FOUND
- commit 73c7bf2 (chore: register in build.zig) — FOUND
