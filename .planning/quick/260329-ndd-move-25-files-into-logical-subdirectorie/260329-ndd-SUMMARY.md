---
phase: quick
plan: 260329-ndd
subsystem: project-structure
tags: [refactor, organization, zero-behavior-change]
dependency_graph:
  requires: []
  provides: [codegen-subdir, lsp-subdir, mir-subdir, zig_runner-subdir, peg-orhon.peg]
  affects: [build.zig, pipeline.zig, main.zig, peg.zig, peg/grammar.zig]
tech_stack:
  added: []
  patterns: [satellite-files-in-subdir, hub-file-reexport, relative-parent-imports]
key_files:
  created:
    - src/codegen/ (directory)
    - src/lsp/ (directory)
    - src/mir/ (directory)
    - src/zig_runner/ (directory)
  modified:
    - src/codegen/codegen.zig (moved + imports updated)
    - src/codegen/codegen_decls.zig (moved + imports updated)
    - src/codegen/codegen_exprs.zig (moved + imports updated)
    - src/codegen/codegen_match.zig (moved + imports updated)
    - src/codegen/codegen_stmts.zig (moved + imports updated)
    - src/lsp/lsp.zig (moved + imports updated)
    - src/lsp/lsp_analysis.zig (moved + imports updated)
    - src/lsp/lsp_edit.zig (moved + imports updated)
    - src/lsp/lsp_json.zig (moved, no import changes)
    - src/lsp/lsp_nav.zig (moved, no import changes)
    - src/lsp/lsp_semantic.zig (moved + imports updated)
    - src/lsp/lsp_types.zig (moved + imports updated)
    - src/lsp/lsp_utils.zig (moved + imports updated)
    - src/lsp/lsp_view.zig (moved, no import changes)
    - src/mir/mir.zig (moved, sibling re-exports only — no change)
    - src/mir/mir_annotator.zig (moved + imports updated)
    - src/mir/mir_lowerer.zig (moved + imports updated)
    - src/mir/mir_node.zig (moved + imports updated)
    - src/mir/mir_registry.zig (moved, sibling only — no change)
    - src/mir/mir_types.zig (moved + imports updated)
    - src/peg/orhon.peg (moved from src/ root)
    - src/zig_runner/zig_runner.zig (moved + imports updated)
    - src/zig_runner/zig_runner_build.zig (moved + imports updated)
    - src/zig_runner/zig_runner_discovery.zig (moved + imports updated)
    - src/zig_runner/zig_runner_multi.zig (moved + imports updated)
    - src/pipeline.zig (updated 3 imports to subdirectory paths)
    - src/main.zig (updated lsp import to lsp/lsp.zig)
    - src/peg.zig (updated @embedFile to peg/orhon.peg)
    - src/peg/grammar.zig (updated @embedFile from ../orhon.peg to orhon.peg)
    - build.zig (updated test_files, removed satellite files from standalone test compilation)
decisions:
  - "Satellite files in codegen/, lsp/, mir/, zig_runner/ not in build.zig test_files — same pattern as peg/ satellites: @import('../X.zig') breaks standalone compilation. Hub files and root-level files cover all tests transitively."
metrics:
  duration: ~10min
  completed: "2026-03-29T14:03:28Z"
  tasks: 3
  files: 30
---

# Phase quick Plan 260329-ndd: Move 25 Files Into Logical Subdirectories Summary

**One-liner:** Reorganized src/ from flat 50-file layout into codegen/, lsp/, mir/, zig_runner/ subdirectories plus orhon.peg into peg/, continuing the pattern established by peg/ and std/.

## What Was Done

Moved 25 source files from the flat `src/` root into 4 new logical subdirectories:

| Directory | Files |
|-----------|-------|
| `src/codegen/` | codegen.zig + 4 satellites (decls, exprs, match, stmts) |
| `src/lsp/` | lsp.zig + 8 satellites (analysis, edit, json, nav, semantic, types, utils, view) |
| `src/mir/` | mir.zig + 5 satellites (annotator, lowerer, node, registry, types) |
| `src/zig_runner/` | zig_runner.zig + 3 satellites (build, discovery, multi) |
| `src/peg/` | orhon.peg (moved from src/ root) |

All `@import` paths in moved files updated to use `../X.zig` for root-level files (sibling imports unchanged). All external importers updated: `pipeline.zig`, `main.zig`, `peg.zig`, `peg/grammar.zig`. `build.zig` test_files updated.

## Decisions Made

**Satellite files removed from build.zig test_files:** When Zig compiles a satellite file as a standalone test root, `@import("../parser.zig")` fails with "import of file outside module path". This is the same constraint documented in Phase 36 for the peg/ satellites. All subdirectory files (both hubs and satellites) removed from test_files. Their unit tests run transitively via `pipeline.zig` (imports codegen, mir, zig_runner) and `peg.zig` (imports peg/ subtree). This is consistent with the existing approach.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hub files also fail as standalone test roots**
- **Found during:** Task 3
- **Issue:** Hub files (lsp.zig, mir.zig, etc.) that import their siblings (which in turn import `../X.zig` files) also fail standalone compilation — not just the pure satellite files
- **Fix:** Removed all 4 hub files from build.zig test_files (mir.zig, codegen.zig, zig_runner.zig, lsp.zig) in addition to their satellites
- **Files modified:** build.zig
- **Commit:** 2172a1f

## Pre-existing Failures

The test `08_codegen — interpolation propagates OOM (no catch unreachable)` was already failing before this task. Confirmed by running 08_codegen.sh against the pre-change binary. Not introduced by this refactor.

## Known Stubs

None — this is a pure structural reorganization with zero behavior change.

## Self-Check: PASSED

- src/codegen/ contains 5 files: confirmed
- src/lsp/ contains 9 files: confirmed
- src/mir/ contains 6 files: confirmed
- src/zig_runner/ contains 4 files: confirmed
- src/peg/orhon.peg exists: confirmed
- No stale codegen/lsp/mir/zig_runner/orhon.peg files in src/ root: confirmed
- 265/266 tests pass (1 pre-existing failure): confirmed
- Commits 452647e, 2172a1f exist: confirmed
