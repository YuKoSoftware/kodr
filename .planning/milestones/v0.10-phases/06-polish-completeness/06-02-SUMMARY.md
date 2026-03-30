---
phase: 06-polish-completeness
plan: 02
subsystem: documentation
tags: [example-module, rawptr, volatileptr, typeof, bitsize, include, import]

# Dependency graph
requires:
  - phase: 06-polish-completeness
    provides: phase context and gap analysis (D-06, D-07, D-08)
provides:
  - RawPtr(T).cast() working demo in example module
  - VolatilePtr(T) documentation in example module
  - typeOf() compt function demo in example module
  - "#bitsize metadata documentation in example module"
  - include vs import distinction documentation in example module
affects: [language-manual, orhon-init, example-module]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "VolatilePtr and #bitsize documented as comment-only blocks (not runnable in normal programs)"
    - "include vs import shown as comment example alongside live import usage"

key-files:
  created: []
  modified:
    - src/templates/example/data_types.orh
    - src/templates/example/example.orh

key-decisions:
  - "VolatilePtr demonstration is comment-only — hardware register usage cannot be meaningfully tested in normal programs"
  - "#bitsize documentation is comment-only in data_types.orh — the metadata belongs in the anchor file (example.orh), so it is explained as a cross-reference"
  - "include vs import is comment-only — adding actual include alongside existing import would cause symbol conflicts; the explanation is sufficient"

patterns-established:
  - "Example module: use comment-only blocks for hardware/platform features that cannot run in a standard test"
  - "Example module: live code + adjacent comments > pure comment blocks wherever a function can demonstrate the feature"

requirements-completed: [DOCS-01]

# Metrics
duration: 2min
completed: 2026-03-25
---

# Phase 6 Plan 02: Example Module Missing Features Summary

**RawPtr/VolatilePtr demos, typeOf() function, #bitsize docs, and include vs import added to example module — covering all previously missing language features**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-25T07:40:58Z
- **Completed:** 2026-03-25T07:42:30Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `raw_ptr_demo()` function with working `RawPtr(i32).cast(&x)` syntax and a passing test
- Added `VolatilePtr(T)` comment block showing hardware-register usage pattern
- Added `typeof_demo()` compt function demonstrating `typeOf()` compiler intrinsic
- Added `#bitsize` comment block explaining default numeric literal type control
- Added `include` vs `import` distinction documentation alongside the live `import std::console` usage

## Task Commits

Each task was committed atomically:

1. **Task 1: Add RawPtr, VolatilePtr, #bitsize, and typeOf examples to data_types.orh** - `2b8cff0` (feat)
2. **Task 2: Add include vs import demonstration to example.orh** - `9b27feb` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `src/templates/example/data_types.orh` - Added RawPtr section with working function+test, VolatilePtr comment block, typeOf section with compt function, #bitsize comment block
- `src/templates/example/example.orh` - Added import/include distinction comments in the Imports section

## Decisions Made
- VolatilePtr is documented as comment-only because hardware register access cannot run in a standard test binary; showing the syntax clearly is sufficient
- #bitsize is documented as comment-only in data_types.orh because it is anchor-file metadata and adding it to data_types.orh would be meaningless (it lives in example.orh)
- include vs import is comment-only to avoid symbol conflicts with the already-imported std::console

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `test/09_language.sh` had 1 pre-existing failure ("null union codegen") that is unrelated to this plan — confirmed by running the test against main before our changes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Example module now covers all implemented language features documented in planning context
- Phase 06 plan 02 complete; example module compiles and tests pass (modulo pre-existing null union codegen failure)

---
*Phase: 06-polish-completeness*
*Completed: 2026-03-25*
