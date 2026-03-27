---
phase: 24-cimport-unification
plan: 01
subsystem: compiler
tags: [cimport, c-interop, peg-grammar, codegen, bridge]

# Dependency graph
requires:
  - phase: 23-pattern-guards
    provides: "Working compiler at v0.15 with PEG grammar and full pipeline"
provides:
  - "#cimport PEG grammar rule with required block syntax (cimport_block, cimport_entry)"
  - "Metadata struct extended with cimport_include and cimport_source fields"
  - "Builder parses #cimport blocks, reports unknown keys (D-05) and missing include (D-06)"
  - "Declarations validation: #cimport only in bridge modules"
  - "Unified main.zig collection loop replaces four old linkC/cInclude/csource/linkCpp loops"
  - "Duplicate #cimport detection across modules (D-08 / CIMP-03)"
  - "zig_runner single-target path emits c_includes, c_source_files, needs_cpp, shared cImport modules"
  - "Old directives (#linkC, #cInclude, #csource, #linkCpp) are parse errors"
affects:
  - 24-cimport-unification plan 02 (Tamga migration)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single directive per C library: #cimport \"lib\" { include: \"h\", source?: \"f.cpp\" }"
    - "cimport_block PEG sub-rules for block parsing inside buildMetadata"
    - "Unified collection using Zig anonymous struct + function pointer to deduplicate multi/single-target loops"

key-files:
  created:
    - test/fixtures/fail_old_linkc.orh
  modified:
    - src/orhon.peg
    - src/parser.zig
    - src/peg/builder.zig
    - src/declarations.zig
    - src/main.zig
    - src/zig_runner.zig
    - test/11_errors.sh

key-decisions:
  - "D-01 (hard remove): Old directives removed from grammar entirely — parse errors immediately"
  - "D-06 (mandatory block): include: key always required, bare #cimport 'lib' form is invalid"
  - "D-08 (one per project): Duplicate #cimport for same lib name is compile error with both module names"
  - "Source-only detection: cimport_source present without system lib skips linkSystemLibrary"
  - "C++ auto-detection: .cpp/.cc/.cxx extension on source: value sets needs_cpp automatically"
  - "Single collection helper: anonymous struct + nested fn replaces four separate metadata scan loops in main.zig multi-target"

patterns-established:
  - "cimport_block parse pattern: builder navigates cap.children[1].children for cimport_entry nodes"
  - "Builder error reporting: ctx.reportError() with arena-allocated message for compile errors from syntax analysis"
  - "generateSharedCImportFiles invoked for single-target path too when c_includes.len > 0"

requirements-completed: [CIMP-01, CIMP-02, CIMP-03, CIMP-04]

# Metrics
duration: 25min
completed: 2026-03-27
---

# Phase 24 Plan 01: #cimport Unification — Compiler Pipeline Summary

**Unified C library import directive: `#cimport "lib" { include: "h" }` replaces four old directives across grammar, parser, builder, declarations, main.zig collection, and zig_runner build generation**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-27T18:46:47Z
- **Completed:** 2026-03-27T18:59:10Z
- **Tasks:** 2
- **Files modified:** 7 (+ 1 created)

## Accomplishments

- PEG grammar: `metadata_body` now has `cimport` rule with mandatory `cimport_block` — old four alternatives removed
- Parser: `Metadata` struct extended with `cimport_include` and `cimport_source` optional fields
- Builder: `buildMetadata()` handles `#cimport` blocks, reports unknown keys (D-05) and missing `include:` (D-06) via `ctx.reportError()`
- Declarations: bridge-presence validation updated from `#linkC` to `#cimport`; both unit tests renamed/updated
- main.zig multi-target: four separate collection loops replaced with one unified `#cimport` loop with duplicate detection (D-08)
- main.zig single-target: similarly replaced with `#cimport` collection including `c_includes`, `c_sources`, and `needs_cpp`
- zig_runner: `buildZigContent` and `generateBuildZig` extended with three new params; shared @cImport module generation and C source file emission added; disk write of wrapper `.zig` files triggered from `generateBuildZigWithTests`
- Negative test: `fail_old_linkc.orh` + `11_errors.sh` block verifying old `#linkC` is rejected
- Test suite: 260/260 pass (was 259; +1 new negative test)

## Task Commits

1. **Task 1: Grammar, parser types, and builder** - `19f8c01` (feat)
2. **Task 2: Declarations, main.zig, zig_runner — validation, collection, and build generation** - `fe72c29` (feat)

## Files Created/Modified

- `src/orhon.peg` - Replaced `metadata_body` alternatives with `#cimport` + new `cimport_block`/`cimport_entry` rules
- `src/parser.zig` - `Metadata` struct extended with `cimport_include` and `cimport_source` fields
- `src/peg/builder.zig` - `buildMetadata()` handles `#cimport` block parsing and validation
- `src/declarations.zig` - Bridge validation updated to `#cimport`; unit tests renamed and updated
- `src/main.zig` - Multi-target and single-target metadata collection loops unified for `#cimport`
- `src/zig_runner.zig` - `buildZigContent`/`generateBuildZig` extended with c_includes/c_source_files/needs_cpp params
- `test/fixtures/fail_old_linkc.orh` - Negative test fixture (new)
- `test/11_errors.sh` - New test block for old `#linkC` rejection (CIMP-04)

## Decisions Made

None beyond what was pre-decided in CONTEXT.md (D-01 through D-10 followed exactly).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed missing `runTests` call site in zig_runner.zig**
- **Found during:** Task 2 (unit test run after changes)
- **Issue:** `runTests()` calls `generateBuildZigWithTests()` directly with 7 args; plan only mentioned `generateBuildZig` call site in main.zig
- **Fix:** Updated `runTests()` to pass three new parameters (`&.{}`, `&.{}`, `false`)
- **Files modified:** `src/zig_runner.zig`
- **Verification:** `zig build test` passes
- **Committed in:** `fe72c29` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed three additional `buildZigContent` test call sites**
- **Found during:** Task 2 (unit test compilation)
- **Issue:** Tests for `buildZigContent - exe/static/dynamic` had 8 args; new signature requires 11
- **Fix:** Added `&.{}, &.{}, false` to each test call site
- **Files modified:** `src/zig_runner.zig`
- **Verification:** `zig build test` passes
- **Committed in:** `fe72c29` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Both were call-site updates necessitated by signature change. No scope creep.

## Issues Encountered

None beyond the call-site fixes above.

## Next Phase Readiness

- Plan 24-01 complete: full compiler pipeline accepts `#cimport`, rejects old directives
- Plan 24-02 ready: migrate Tamga framework files to new `#cimport` syntax
- No blockers

---
*Phase: 24-cimport-unification*
*Completed: 2026-03-27*
