# Phase 35: Zig Runner Split - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Split the monolithic `src/zig_runner.zig` (1952 lines, 16 tests) into 4 focused files with no behavior change. zig_runner.zig should be reduced to ~400 lines: ZigRunner struct and invocation logic only. All 266 tests must pass. No single file should exceed ~600 lines.

</domain>

<decisions>
## Implementation Decisions

### File Split Strategy
- **D-01:** Split into 4 files by responsibility: runner core (ZigRunner struct + invocation), single-target build.zig generation, multi-target build.zig generation, and Zig binary discovery. This matches the ROADMAP.md success criteria exactly.
- **D-02:** Follow the flat `zig_runner_*.zig` naming pattern consistent with Phases 29/32/33/34 (`codegen_*.zig`, `lsp_*.zig`, `mir_*.zig`). Not a subdirectory.

### File Breakdown
- **D-03:** Runner core — `zig_runner.zig` keeps: ZigRunner struct (init, deinit), buildAll, build, buildLib, runTests, generateBuildZig, writeTestOutput. This is the orchestration layer that calls into the build gen files.
- **D-04:** Single-target build gen — `buildZigContent()` and its helper functions (emitLinkLibs, emitIncludePath, generateSharedCImportFiles, emitCSourceFiles) move to a dedicated file (~560 lines). These helpers are also imported by the multi-target file.
- **D-05:** Multi-target build gen — `buildZigContentMulti()` and the `MultiTarget` struct move to a dedicated file (~593 lines). Imports shared helpers from the single-target file.
- **D-06:** Zig discovery — `findZig()`, `findZigInPath()`, `zigBinaryName()` move to a small dedicated file (~45 lines). Called only by ZigRunner.init().

### Helper Sharing Pattern
- **D-07:** Shared build-gen helpers (emitLinkLibs, emitIncludePath, emitCSourceFiles, generateSharedCImportFiles) live in the single-target build gen file. The multi-target file imports them. This avoids a separate helpers file for just 4 functions.

### State Sharing Pattern
- **D-08:** Pass parameters explicitly — consistent with all prior split phases. Build gen functions already take `allocator` and data as parameters. No wrapper structs needed.

### Scope
- **D-09:** Pure refactor. No function signatures change, no behavior changes, no new features. Generated build.zig output must be identical.
- **D-10:** Unit tests move to the file containing the function they test. buildZigContent tests go with single-target, buildZigContentMulti tests go with multi-target, findZig test goes with discovery, formatTestOutput test stays with runner.

### Claude's Discretion
- Exact file names beyond the `zig_runner_*` prefix (e.g., `zig_runner_build.zig` vs `zig_runner_single.zig`)
- Whether `zig_runner.zig` uses `pub usingnamespace` or explicit re-exports for backward compatibility
- Exact placement of edge-case helpers that serve both build gen files

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Target File
- `src/zig_runner.zig` — The file being refactored (1952 lines, ~18 functions, 16 tests)

### Prior Art (same refactor pattern)
- `.planning/phases/29-codegen-split/29-CONTEXT.md` — Codegen split decisions (established the pattern)
- `.planning/phases/29-codegen-split/29-01-SUMMARY.md` — Codegen split results and lessons
- `.planning/phases/33-mir-split/33-CONTEXT.md` — MIR split decisions (underscore-prefix for imports)
- `.planning/phases/33-mir-split/33-01-SUMMARY.md` — MIR split lessons
- `.planning/phases/34-main-split/34-CONTEXT.md` — Main split decisions (latest iteration)

### Compiler Architecture
- `docs/COMPILER.md` — Compiler pipeline architecture, zig_runner's role (pass 12)
- `src/main.zig` — Primary caller of ZigRunner (via pipeline.zig after Phase 34 split)
- `src/pipeline.zig` — Pipeline orchestration that invokes ZigRunner
- `src/cache.zig` — Cache module used by build gen (writeGeneratedZig, GENERATED_DIR)
- `src/module.zig` — Module types consumed by build gen

### Codebase Maps
- `.planning/codebase/STRUCTURE.md` — Project file structure
- `.planning/codebase/CONVENTIONS.md` — Naming and organization conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Current Structure (1952 lines)
- **Lines 1-473:** ZigRunner struct (init, deinit, buildAll, build, buildLib, runTests, generateBuildZig) + ZigResult + writeTestOutput
- **Lines 477-1043:** `buildZigContent()` — single-target build.zig generation + helper functions (emitLinkLibs, emitIncludePath, generateSharedCImportFiles, emitCSourceFiles) + MultiTarget struct definition
- **Lines 1047-1640:** `buildZigContentMulti()` — multi-target build.zig generation (~593 lines)
- **Lines 1645-1690:** `findZig()`, `findZigInPath()`, `zigBinaryName()` — Zig binary discovery (~45 lines)
- **Lines 1692-1952:** 16 unit tests (~260 lines)

### Reusable Assets
- Prior split pattern from codegen/lsp/mir/main phases — well-tested approach
- `pub usingnamespace @import(...)` pattern for backward-compatible re-exports (used in codegen, mir, lsp splits)

### Established Patterns
- Flat `prefix_*.zig` naming: `codegen_decls.zig`, `codegen_expr.zig`, `lsp_handlers.zig`, `mir_types.zig`
- Main file keeps struct + re-exports, satellite files get `*Self` parameter or import the struct
- Underscore-prefix for module imports to avoid shadowing (lesson from Phase 33)

### Integration Points
- `src/pipeline.zig` imports `zig_runner.zig` — must continue to work unchanged
- `build.zig` lists `zig_runner.zig` in test_files — new files must be added
- `src/main.zig` may reference zig_runner types — check for ZigResult usage

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. Follow established split patterns from phases 29/32/33/34.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 35-zig-runner-split*
*Context gathered: 2026-03-29*
