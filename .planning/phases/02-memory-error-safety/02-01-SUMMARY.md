---
phase: 02-memory-error-safety
plan: 01
subsystem: codegen
tags: [zig, codegen, error-propagation, string-interpolation, OOM]

requires: []
provides:
  - "Fixed catch unreachable in generateInterpolatedString (AST path)"
  - "Fixed catch unreachable in generateInterpolatedStringMir (MIR path)"
  - "Regression test in test/08_codegen.sh for interpolation OOM safety"
affects: [future-interpolation-work, codegen]

tech-stack:
  added: []
  patterns:
    - "Interpolation allocPrint now emits 'catch |err| return err' — OOM propagates up the call chain"
    - "Codegen source-level regression tests check emitted patterns directly via grep on src/codegen.zig"

key-files:
  created: []
  modified:
    - src/codegen.zig
    - test/08_codegen.sh

key-decisions:
  - "Test verifies codegen source directly (grep on src/codegen.zig) rather than generated output — the interpolation AST nodes are currently unreachable via the PEG builder, so no generated output to check"
  - "Fixed both interpolation code paths proactively — AST path (generateInterpolatedString) and MIR path (generateInterpolatedStringMir)"

patterns-established:
  - "Regression guard: when fixing an emit pattern in codegen, add a grep-based test in 08_codegen.sh checking the source file"

requirements-completed: [MEM-01, MEM-02]

duration: 15min
completed: 2026-03-24
---

# Phase 02 Plan 01: Fix Interpolation catch unreachable Summary

**Replaced `catch unreachable` with `catch |err| return err` in both interpolation codegen functions, preventing OOM panics, with a source-level regression test.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-24T17:00:00Z
- **Completed:** 2026-03-24T17:15:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Fixed `generateInterpolatedString` (AST path, line 2584) to emit `catch |err| return err`
- Fixed `generateInterpolatedStringMir` (MIR path, line 2983) to emit `catch |err| return err`
- Added regression test in `test/08_codegen.sh` that verifies both fixes persist

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix interpolation catch unreachable in codegen.zig** - `6999068` (fix)
2. **Task 2: Add codegen regression test for interpolation safety** - `e2a5626` (test)

**Plan metadata:** to be added after state update (docs commit)

## Files Created/Modified
- `src/codegen.zig` - Changed two `catch unreachable` emits to `catch |err| return err` in both interpolation functions
- `test/08_codegen.sh` - Added "interpolation propagates OOM" test that greps src/codegen.zig for 2+ occurrences of the safe pattern

## Decisions Made
- Test strategy: The PEG builder's `buildStringLiteral` never creates `interpolated_string` AST nodes — the `@{...}` syntax inside string literals is lexed as part of the string token, not parsed into structured interpolation nodes. This means no generated Zig output currently contains the allocPrint calls. Testing the codegen source directly (grep on `src/codegen.zig`) is the correct approach — it verifies the fix persists and will catch regression if the pattern is accidentally reverted.
- Scope: Only changed the two interpolation emit sites. The 15 remaining `catch unreachable` in codegen.zig are intentional — thread handle allocation (4 sites), error union .value unwraps (6 sites), and doc comments (2 sites).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test strategy adjusted for unreachable code path**
- **Found during:** Task 2 (Add codegen regression test)
- **Issue:** The plan's test template used a freshly built project to check generated Zig for `catch |err| return err`. Investigation showed that `buildStringLiteral` in `src/peg/builder.zig` always creates `string_literal` nodes, never `interpolated_string` nodes — the `@{...}` syntax is currently not parsed into the interpolated_string AST variant. No generated `.zig` file will contain the allocPrint calls until the PEG builder is updated to handle interpolation.
- **Fix:** Changed test from "build a project and check generated output" to "grep src/codegen.zig for the safe pattern count". This correctly validates the fix and will catch regression.
- **Files modified:** test/08_codegen.sh
- **Verification:** `bash test/08_codegen.sh` exits 0, all 9 tests pass including new interpolation test
- **Committed in:** e2a5626

---

**Total deviations:** 1 auto-fixed (test strategy adjustment)
**Impact on plan:** The core fix (task 1) was implemented exactly as specified. The test approach was adjusted to work within the actual state of the codebase. No scope creep.

## Issues Encountered
- The PEG builder never creates `interpolated_string` AST nodes — the code paths being fixed are currently dormant. The `catch unreachable` fix is still correct and important to make proactively, as it will apply when the PEG builder is eventually updated to handle `@{...}` interpolation syntax.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- MEM-01 and MEM-02 requirements complete: interpolation allocPrint now propagates OOM errors
- The broader interpolation feature (PEG builder creating interpolated_string nodes) is a separate concern not in scope for this phase
- Plans 02-02 and 02-03 are independent and can proceed

---
*Phase: 02-memory-error-safety*
*Completed: 2026-03-24*
