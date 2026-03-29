# Phase 34: Main Split - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Split the monolithic `src/main.zig` (2328 lines) into 6+ focused files with no behavior change. main.zig should be reduced to ~115 lines: allocator setup + command dispatch only. All 266 tests must pass. No single file should exceed ~600 lines.

</domain>

<decisions>
## Implementation Decisions

### File Grouping Strategy
- **D-01:** Split by logical domain — each major responsibility area in main.zig becomes its own file. The main `main.zig` keeps only: allocator setup, CLI args struct, `main()` entry point, and command dispatch.
- **D-02:** Follow the flat naming pattern from Phases 29/32/33: `src/cli.zig`, `src/pipeline.zig`, `src/init.zig`, etc. (not a subdirectory). Consistent with `src/codegen_*.zig`, `src/lsp_*.zig`, `src/mir_*.zig`.

### File Breakdown
- **D-03:** CLI parsing — `CliArgs`, `Command` enum, `parseArgs()`, `printUsage()`, `printHelp()`, `BuildTarget` move to a CLI module.
- **D-04:** Pipeline orchestration — `runPipeline()` and its internal helpers (`collectBridgeNames`, per-module pass loop) move to a pipeline module. This is the largest chunk (~800 lines).
- **D-05:** Project init — `initProject()` and template writing logic move to an init module. All `@embedFile` constants for templates (example.orh, tester.orh, etc.) move with it.
- **D-06:** Stdlib bundler — `ensureStdFiles()`, `writeStdFile()`, and the `@embedFile` constants for stdlib `.orh`/`.zig` pairs move to a stdlib bundler module.
- **D-07:** Interface generation — `generateInterface()`, `emitInterfaceDecl()`, `emitFuncSig()`, `formatType()`, `formatExprSimple()` move to an interface generation module.
- **D-08:** Command runners — `runAnalysis()`, `runDebug()`, `runGendoc()`, `emitZigProject()`, `moveArtifactsToSubfolder()`, `addToPath()` group with pipeline or get their own commands module. Planner decides based on coupling analysis.

### Embed File Placement
- **D-09:** `@embedFile` constants move with their consumer function. Template embeds go with init, stdlib embeds go with the stdlib bundler. This keeps each module self-contained and avoids a separate "constants" file for embedded content.

### State Sharing Pattern
- **D-10:** Pass parameters explicitly — no wrapper struct needed. main.zig functions already receive `allocator`, `cli`, `reporter` as parameters. Keep this pattern in the split files.

### Scope
- **D-11:** Pure refactor. No function signatures change, no behavior changes, no new features. Generated output must be identical.
- **D-12:** Unit tests at the bottom of main.zig move to their new file locations alongside the code they test.

### Claude's Discretion
- Exact file names (e.g., `cli.zig` vs `cli_args.zig`, `pipeline.zig` vs `compiler.zig`)
- Whether command runners (analysis, debug, gendoc) stay in pipeline or get a separate `commands.zig`
- Exact function-to-file assignments when a function is used by multiple domains — put it where it's most called
- How `main.zig` imports and delegates to the split files (direct function calls vs re-exports)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Target File
- `src/main.zig` — The file being refactored (2328 lines, ~30 functions, 6 labeled sections)

### Prior Art (same refactor pattern)
- `.planning/phases/29-codegen-split/29-CONTEXT.md` — Codegen split decisions (established the pattern)
- `.planning/phases/29-codegen-split/29-01-PLAN.md` — Codegen split execution plan
- `.planning/phases/29-codegen-split/29-01-SUMMARY.md` — Codegen split results and lessons
- `.planning/phases/32-lsp-split/32-CONTEXT.md` — LSP split decisions (parameter passing pattern)
- `.planning/phases/33-mir-split/33-CONTEXT.md` — MIR split decisions (latest iteration)
- `.planning/phases/33-mir-split/33-01-SUMMARY.md` — MIR split lessons (underscore-prefix for imports)

### Compiler Architecture
- `docs/COMPILER.md` — Compiler pipeline architecture, main.zig's role as entry point
- `src/parser.zig` — AST types used by interface generation
- `src/errors.zig` — Reporter used across pipeline
- `src/module.zig` — Module resolution used by pipeline
- `src/zig_runner.zig` — Zig invocation used by pipeline

</canonical_refs>

<code_context>
## Existing Code Insights

### Current Structure (2328 lines)
- **Lines 1-24:** Imports (20 module imports)
- **Lines 25-250:** CLI — Command enum, BuildTarget, CliArgs, parseArgs(), printUsage(), printHelp()
- **Lines 250-355:** @embedFile constants for templates + initProject()
- **Lines 355-492:** @embedFile constants for stdlib + ensureStdFiles(), writeStdFile()
- **Lines 492-600:** addToPath() utility
- **Lines 600-715:** main() entry point — allocator setup, CLI parse, command dispatch
- **Lines 716-900:** runAnalysis(), runDebug(), runGendoc() command runners
- **Lines 899-1715:** runPipeline() — the core compilation pipeline (~800 lines)
- **Lines 1715-1750:** collectBridgeNames() helper
- **Lines 1749-1980:** Interface generation — formatType(), formatExprSimple(), emitFuncSig(), emitInterfaceDecl()
- **Lines 1981-2065:** emitZigProject(), moveArtifactsToSubfolder()
- **Lines 2066-2328:** Unit tests

### Established Patterns from Prior Splits
- Flat file naming: `src/codegen_*.zig`, `src/lsp_*.zig`, `src/mir_*.zig`
- Main file keeps struct/entry + dispatch, satellite files get functions
- `pub usingnamespace` or explicit re-exports for backward compatibility
- Unit tests move with the code they test
- Phase 33 lesson: underscore-prefix module imports to avoid shadowing

### Integration Points
- `build.zig` references `src/main.zig` as the root source — no change needed (Zig resolves @import chains)
- All `@import` statements from other files point to pass modules (codegen, mir, etc.), not main.zig — no external consumers to update

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following the established split pattern from Phases 29/32/33.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 34-main-split*
*Context gathered: 2026-03-29*
