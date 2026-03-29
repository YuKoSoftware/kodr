# Phase 32: LSP Split - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Split the monolithic `src/lsp.zig` (3303 lines, 82 functions) into 8+ focused files with no behavior change. LSP features must work identically — `./testall.sh` is the safety gate. No single file should exceed ~600 lines.

</domain>

<decisions>
## Implementation Decisions

### File Grouping Strategy
- **D-01:** Split by the existing section headers in lsp.zig. The file already has 18 clearly labeled sections that map naturally to focused files. Group related sections into files that stay under ~600 lines.
- **D-02:** The main `lsp.zig` keeps the `serve()` function (server loop), imports, and top-level dispatch. All handler functions and utilities move to dedicated files.

### State Sharing Pattern
- **D-03:** Pass parameters explicitly — no wrapper struct needed. Unlike codegen.zig (which had a `CodeGen` struct), lsp.zig handlers already receive `allocator`, `symbols`, `doc_store`, `id`, `root` as function parameters. Keep this pattern.
- **D-04:** Shared types (`Diagnostic`, `SymbolInfo`, `AnalysisResult`, `CompletionItemKind`, constants like `MAX_HEADER_LINE`) go in a dedicated types/shared module that all LSP files import.

### Handler Grouping
- **D-05:** Group handlers by LSP feature category:
  - **Navigation handlers:** hover, definition, references, document highlight
  - **Editing handlers:** completion, rename, code actions, formatting
  - **View/hints handlers:** document symbols, workspace symbols, inlay hints, signature help, folding ranges, semantic tokens
- **D-06:** Helper functions move to the file where they're most used. Shared text utilities (getWordAtPosition, getDotContext, isIdentChar) go in a text utils module. Symbol lookup functions go in a symbol module.

### Infrastructure Files
- **D-07:** JSON infrastructure (helpers, response builders) stays together in one file — these are pure utility functions with no LSP-specific logic.
- **D-08:** Transport (readMessage, writeMessage) and URI helpers can stay in the main lsp.zig or move to a small transport module — planner decides based on line counts.
- **D-09:** Analysis (runAnalysis, extractSymbols, extractLocals, toDiagnostics) goes in its own file — this is the bridge between the compiler passes and LSP.

### Scope
- **D-10:** Pure refactor. No function signatures change, no behavior changes, no new LSP features. If a function is being moved, it must produce identical behavior.
- **D-11:** Unit tests at the bottom of lsp.zig move to their new file locations alongside the code they test.

### Claude's Discretion
- Exact file names (e.g., `lsp_nav.zig`, `lsp_edit.zig`, `lsp_view.zig` vs `lsp/nav.zig` etc.)
- Whether to use a `src/lsp/` subdirectory or flat `src/lsp_*.zig` files — planner should follow the pattern established by codegen split (Phase 29)
- Exact function-to-file assignments — planner should analyze call graphs to minimize cross-file dependencies
- Whether type formatting (formatType, formatFuncSig, etc.) stays with analysis or moves to its own module

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Target File
- `src/lsp.zig` — The file being refactored (3303 lines, 82 functions, 18 labeled sections)

### Prior Art (same pattern)
- `.planning/phases/29-codegen-split/29-CONTEXT.md` — Codegen split decisions (same refactor pattern)
- `.planning/phases/29-codegen-split/29-01-PLAN.md` — Codegen split execution plan (reference for approach)
- `.planning/phases/29-codegen-split/29-01-SUMMARY.md` — Codegen split results and lessons learned

### Compiler Architecture
- `docs/COMPILER.md` — Compiler pipeline architecture, LSP's role
- `src/parser.zig` — AST types consumed by LSP (Node, NodeKind)
- `src/declarations.zig` — Declaration types consumed by LSP (FuncSig, StructSig, EnumSig)
- `src/types.zig` — ResolvedType consumed by LSP type formatting
- `src/errors.zig` — Reporter, OrhonError, SourceLoc consumed by LSP diagnostics

### Requirements
- `.planning/REQUIREMENTS.md` — SPLIT-01 (lsp.zig split into 8+ files), SPLIT-02 (zero behavior change gate)

### Codebase Maps
- `.planning/codebase/STRUCTURE.md` — Project file structure
- `.planning/codebase/CONVENTIONS.md` — Naming and organization conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Current Structure (3303 lines, 82 functions)
- **Lines 1-23:** Imports (13 compiler modules + std)
- **Lines 25-72:** JSON-RPC Transport (readMessage, writeMessage)
- **Lines 74-113:** JSON Helpers (jsonStr, jsonObj, jsonInt, jsonArray, jsonBool, jsonId)
- **Lines 115-237:** JSON Response Builders (buildInitializeResult, buildEmptyArrayResponse, buildDiagnosticsMsg, etc.)
- **Lines 239-295:** Type definitions (Diagnostic, SymbolInfo, AnalysisResult structs + free functions)
- **Lines 296-336:** URI Helpers (getDocSource, uriToPath, pathToUri, findProjectRoot)
- **Lines 337-443:** Type Formatting (formatType, formatFuncSig, formatStructSig, formatEnumSig)
- **Lines 444-860:** Analysis (runAnalysis — 160 lines, extractSymbols — 175 lines, extractLocals — 70 lines, helpers)
- **Lines 911-1016:** Response builders for Phase 2 handlers (buildHoverResponse, buildDefinitionResponse, buildDocumentSymbolsResponse)
- **Lines 1017-1092:** Text utilities (getWordAtPosition, isIdentChar, getDotContext)
- **Lines 1094-1232:** Symbol lookup (findSymbolByName, findVisibleSymbolByName, findSymbolInContext, isOnModuleLine, isModuleName, builtinDetail)
- **Lines 1233-1615:** Server loop (lspLog, serve() — 360 lines of dispatch)
- **Lines 1616-1654:** runAndPublishWithDiags helper
- **Lines 1655-1779:** Navigation handlers (handleHover, handleDefinition, handleDocumentSymbols)
- **Lines 1780-2098:** Completion handlers (handleCompletion + 10 helper functions)
- **Lines 2099-2184:** References handler
- **Lines 2185-2320:** Rename handler + collectOrhFiles
- **Lines 2321-2437:** Signature help handler
- **Lines 2438-2498:** Formatting handler
- **Lines 2499-2571:** Workspace symbol handler
- **Lines 2572-2665:** Inlay hints handler
- **Lines 2666-2744:** Code actions handler
- **Lines 2745-2822:** Parameter label extraction helpers
- **Lines 2823-2886:** Document highlight handler
- **Lines 2887-2996:** Folding ranges handler
- **Lines 2997-3139:** Semantic tokens handler
- **Lines 3140-3303:** Tests

### Established Patterns (from Phase 29)
- Codegen split used flat `src/codegen_*.zig` files (not a subdirectory)
- Helper/shared module imported by all split files
- Main file kept struct definition + entry point + dispatch
- `usingnamespace` pattern or explicit re-exports for Zig module resolution

### Key Difference from Codegen Split
- lsp.zig has no central struct — `serve()` uses local variables and passes them to handlers
- Handlers are standalone functions receiving `(allocator, root, id, symbols, ...)` — already clean interfaces
- This makes the split simpler: just move functions to new files and update imports

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. Follow the codegen split pattern from Phase 29.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 32-lsp-split*
*Context gathered: 2026-03-29*
