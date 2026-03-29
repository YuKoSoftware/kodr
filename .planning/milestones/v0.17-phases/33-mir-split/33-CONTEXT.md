# Phase 33: MIR Split - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Split the monolithic `src/mir.zig` (2356 lines, 5 major structs) into 6+ focused files with no behavior change. All 266 tests must pass. No single file should exceed ~600 lines.

</domain>

<decisions>
## Implementation Decisions

### File Grouping Strategy
- **D-01:** Split by struct boundary — each major struct gets its own file. MirAnnotator, MirLowerer, UnionRegistry, and MirNode each move to dedicated files. Type definitions share a types module.
- **D-02:** The main `mir.zig` keeps the public re-exports so downstream importers (`@import("mir.zig")`) continue to work unchanged. No changes to codegen.zig or other consumers.

### Type Sharing Pattern
- **D-03:** Shared types module (`mir_types.zig` or similar) holds: TypeClass, Coercion, NodeInfo, NodeMap, MirKind, LiteralKind, IfNarrowing, and the `classifyType()` function. All split files import from this module.
- **D-04:** The `RT` alias (`types.ResolvedType`) is defined once in the types module and re-exported.

### MirNode Placement
- **D-05:** MirNode gets its own file with `populateData()` and `astToMirKind()` helper functions that are tightly coupled to it.

### File Naming
- **D-06:** Follow the flat naming pattern from Phase 29/32: `src/mir_*.zig` files (not a subdirectory). Consistent with `src/codegen_*.zig` and `src/lsp_*.zig`.

### Scope
- **D-07:** Pure refactor. No function signatures change, no behavior changes, no new MIR features. Generated output must be identical.
- **D-08:** Unit tests move to their new file locations alongside the code they test.

### Claude's Discretion
- Exact file names beyond the `mir_*` prefix
- Whether `mir.zig` uses `pub usingnamespace` or explicit re-exports for backward compatibility
- Exact helper function placement when a function is used by multiple structs — put it where it's most called

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Target File
- `src/mir.zig` — The file being refactored (2356 lines, 5 major structs, 20+ tests)

### Prior Art (same refactor pattern)
- `.planning/phases/29-codegen-split/29-CONTEXT.md` — Codegen split decisions
- `.planning/phases/29-codegen-split/29-01-PLAN.md` — Codegen split execution plan
- `.planning/phases/29-codegen-split/29-01-SUMMARY.md` — Codegen split results and lessons
- `.planning/phases/32-lsp-split/32-CONTEXT.md` — LSP split decisions (latest iteration)

### Compiler Architecture
- `docs/COMPILER.md` — Compiler pipeline architecture, MIR's role (pass 10)
- `src/codegen.zig` — Primary consumer of MIR types (NodeMap, NodeInfo, TypeClass)
- `src/parser.zig` — AST types consumed by MIR (Node, NodeKind)
- `src/declarations.zig` — Declaration types consumed by MIR (DeclTable, FuncSig)
- `src/types.zig` — ResolvedType consumed by MIR type classification

### Requirements
- `.planning/REQUIREMENTS.md` — SPLIT-03 (mir.zig split), SPLIT-02 (zero behavior change gate)

### Codebase Maps
- `.planning/codebase/STRUCTURE.md` — Project file structure
- `.planning/codebase/CONVENTIONS.md` — Naming and organization conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Current Structure (2356 lines)
- **Lines 1-15:** Imports + RT alias
- **Lines 16-76:** Type definitions (TypeClass, Coercion, NodeInfo, NodeMap) + classifyType()
- **Lines 78-153:** UnionRegistry (75 lines) — canonical union type deduplication
- **Lines 155-757:** MirAnnotator (600 lines) — walks AST + type_map, produces NodeMap annotations
- **Lines 758-980:** MirNode + LiteralKind + MirKind + IfNarrowing (220 lines) — MIR tree data structures
- **Lines 983-1480:** MirLowerer (500 lines) — lowers AST to MIR tree
- **Lines 1482-1671:** Helper functions populateData() + astToMirKind() (190 lines)
- **Lines 1673-2356:** Tests (680 lines, 20+ test blocks)

### Established Patterns (from Phase 29 and 32)
- Flat `src/*_*.zig` naming (codegen_decls.zig, lsp_nav.zig, etc.)
- Shared types/helpers module imported by all split files
- Main file keeps struct definition + entry point + public re-exports
- Tests move with the code they test

### Key Consumers
- `src/codegen.zig` + `src/codegen_*.zig` — imports NodeMap, NodeInfo, TypeClass, classifyType, MirAnnotator
- `src/main.zig` — creates MirAnnotator, calls annotate()
- `src/lsp.zig` + `src/lsp_*.zig` — may reference MIR types for analysis

### Approximate Split (6 files)
1. `mir_types.zig` (~100 lines) — TypeClass, Coercion, NodeInfo, NodeMap, classifyType, MirKind, LiteralKind, IfNarrowing
2. `mir_registry.zig` (~80 lines) — UnionRegistry
3. `mir_annotator.zig` (~600 lines) — MirAnnotator + its tests
4. `mir_node.zig` (~220 lines) — MirNode struct + accessor methods
5. `mir_lowerer.zig` (~500 lines) — MirLowerer + populateData + astToMirKind + its tests
6. `mir.zig` (~50 lines) — public re-exports for backward compatibility

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. Follow the codegen/LSP split patterns from Phases 29 and 32.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 33-mir-split*
*Context gathered: 2026-03-29*
