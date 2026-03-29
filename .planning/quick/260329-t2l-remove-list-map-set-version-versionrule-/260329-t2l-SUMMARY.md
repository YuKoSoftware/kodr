---
phase: quick
plan: 260329-t2l
subsystem: compiler-core
tags: [cleanup, builtins, dead-code]
dependency_graph:
  requires: []
  provides: [cleaner-builtins]
  affects: [builtins.zig]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified: [src/builtins.zig]
decisions:
  - Kept List/Map/Set in BUILTIN_TYPES — resolver depends on isBuiltinType() for generic type recognition
  - Kept Version — used in build metadata codegen paths
  - Removed only VersionRule and Dependency — truly dead code with zero references
metrics:
  duration: ~13 minutes
  completed: 2026-03-29
---

# Quick Task 260329-t2l: Remove Dead Types from BUILTIN_TYPES Summary

Removed dead types VersionRule and Dependency from BUILTIN_TYPES in builtins.zig, reduced array from 12 to 10 entries.

## What Was Done

### Task 1: Trim BUILTIN_TYPES and update tests
- Removed `VersionRule` and `Dependency` from the BUILTIN_TYPES array (zero references outside builtins.zig)
- Added negative test assertions confirming these types are no longer builtins
- Commit: `9cb6602`

### Task 2: Full test suite validation
- All 269 tests pass across all 11 test stages
- No regressions from the removal

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan incorrectly assumed List/Map/Set could be removed**
- **Found during:** Task 1 (full test suite revealed failures)
- **Issue:** The plan assumed List, Map, Set are resolved through std::collections bridge imports. In reality, the resolver (`resolver.zig` line 992) uses `isBuiltinType()` to recognize these as valid generic types. Removing them caused "unknown generic type 'List'" errors in 161 tests.
- **Fix:** Kept List, Map, Set in BUILTIN_TYPES. Only removed VersionRule and Dependency (truly dead code).
- **Files modified:** src/builtins.zig

**2. [Rule 1 - Bug] Plan incorrectly assumed Version could be removed**
- **Found during:** Task 1 investigation
- **Issue:** Version is actively used in codegen_stmts.zig, codegen_exprs.zig, and module.zig for `#version = Version(1,0,0)` build metadata handling. It is not dead code.
- **Fix:** Kept Version in BUILTIN_TYPES.
- **Files modified:** src/builtins.zig

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 9cb6602 | Remove dead types VersionRule and Dependency from BUILTIN_TYPES |

## Known Stubs

None.

## Self-Check: PASSED
