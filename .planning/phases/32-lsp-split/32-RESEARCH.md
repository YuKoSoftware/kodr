# Phase 32: LSP Split - Research

**Researched:** 2026-03-29
**Domain:** Zig module splitting / LSP server refactoring
**Confidence:** HIGH

## Summary

The LSP split is a straightforward structural refactor of `src/lsp.zig` (3303 lines, 82 functions, 18 labeled sections) into 8+ focused files with no behavior change. The file already has clean section boundaries, and all handler functions are standalone (no central struct like codegen had) -- they receive parameters explicitly. This makes the split mechanically simpler than Phase 29's codegen split.

The key difference from Phase 29: there is no `CodeGen`-style struct to route calls through. Functions are free-standing, so moving them to new files just requires making them `pub` and updating imports. No wrapper stubs are needed. The shared state pattern is: JSON helpers, type definitions, and text utilities are imported by all handler files.

**Primary recommendation:** Use flat `src/lsp_*.zig` naming (matching Phase 29's `codegen_*.zig` pattern), with `lsp.zig` retaining `serve()` + transport + dispatch, and a `lsp_types.zig` shared module for types/JSON infrastructure that all other LSP files import.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Split by the existing section headers in lsp.zig. The file already has 18 clearly labeled sections that map naturally to focused files. Group related sections into files that stay under ~600 lines.
- **D-02:** The main `lsp.zig` keeps the `serve()` function (server loop), imports, and top-level dispatch. All handler functions and utilities move to dedicated files.
- **D-03:** Pass parameters explicitly -- no wrapper struct needed. Unlike codegen.zig (which had a `CodeGen` struct), lsp.zig handlers already receive `allocator`, `symbols`, `doc_store`, `id`, `root` as function parameters. Keep this pattern.
- **D-04:** Shared types (`Diagnostic`, `SymbolInfo`, `AnalysisResult`, `CompletionItemKind`, constants like `MAX_HEADER_LINE`) go in a dedicated types/shared module that all LSP files import.
- **D-05:** Group handlers by LSP feature category: Navigation (hover, definition, references, document highlight), Editing (completion, rename, code actions, formatting), View/hints (document symbols, workspace symbols, inlay hints, signature help, folding ranges, semantic tokens).
- **D-06:** Helper functions move to the file where they are most used. Shared text utilities go in a text utils module. Symbol lookup functions go in a symbol module.
- **D-07:** JSON infrastructure stays together in one file.
- **D-08:** Transport and URI helpers can stay in main lsp.zig or move to a small transport module -- planner decides based on line counts.
- **D-09:** Analysis goes in its own file.
- **D-10:** Pure refactor. No function signatures change, no behavior changes, no new LSP features.
- **D-11:** Unit tests at the bottom of lsp.zig move to their new file locations alongside the code they test.

### Claude's Discretion
- Exact file names (e.g., `lsp_nav.zig`, `lsp_edit.zig`, `lsp_view.zig` vs `lsp/nav.zig`)
- Whether to use `src/lsp/` subdirectory or flat `src/lsp_*.zig` -- follow codegen split pattern (Phase 29)
- Exact function-to-file assignments based on call graph analysis
- Whether type formatting stays with analysis or moves to its own module

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPLIT-01 | lsp.zig split into 8+ files -- types, JSON infra, analysis, navigation handlers, edit handlers, view handlers, text utils, and server loop | File grouping plan below maps all 3303 lines to 9 target files, each under 600 lines |
| SPLIT-02 | Zero behavior change gate -- `./testall.sh` passes all tests before and after each split, unit tests work in new locations | Tests move alongside their code; `build.zig` test_files array updated with new file paths |
</phase_requirements>

## Standard Stack

No new libraries or dependencies. This is a pure structural refactor within existing Zig code.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Zig stdlib | 0.15.2 | All LSP implementation | Only dependency; already in use |

**No installation needed.**

## Architecture Patterns

### Recommended File Structure

Based on analyzing the 3303-line file section by section, here is the proposed split:

```
src/
  lsp.zig           (~430 lines) — serve(), transport, dispatch, lspLog, runAndPublishWithDiags
  lsp_types.zig     (~280 lines) — Diagnostic, SymbolInfo, AnalysisResult, SymbolKind, CompletionItemKind,
                                    SemanticTokenType, SemanticModifier, SemanticToken, TokenClassification,
                                    ParamLabels, CallContext, TrimResult, MAX_HEADER_LINE, MAX_CONTENT_LENGTH,
                                    free functions (freeDiagnostics, freeSymbols), PublishResult
  lsp_json.zig      (~270 lines) — JSON helpers (jsonStr, jsonObj, jsonInt, jsonArray, jsonBool, jsonId),
                                    JSON response builders (writeJsonValue, appendJsonString, appendInt,
                                    buildInitializeResult, buildEmptyArrayResponse, buildEmptyResponse,
                                    buildDiagnosticsMsg, buildHoverResponse, buildDefinitionResponse,
                                    buildDocumentSymbolsResponse, appendDocumentSymbol)
  lsp_utils.zig     (~260 lines) — URI helpers (getDocSource, uriToPath, pathToUri, findProjectRoot),
                                    text utilities (getWordAtPosition, isIdentChar, getDotContext,
                                    getLinePrefix, getDotPrefix, getModuleName, getImportedModules,
                                    isVisibleModule), symbol lookup (findSymbolByName,
                                    findVisibleSymbolByName, findSymbolInContext, isOnModuleLine,
                                    isModuleName, builtinDetail)
  lsp_analysis.zig  (~575 lines) — runAnalysis, extractSymbols, extractLocals, toDiagnostics,
                                    type formatting (formatType, formatFuncSig, formatStructSig,
                                    formatEnumSig)
  lsp_nav.zig       (~280 lines) — handleHover, handleDefinition, handleDocumentHighlight, handleReferences
  lsp_edit.zig      (~600 lines) — handleCompletion + 10 completion helpers (getDotPrefix already in utils),
                                    buildDotCompletionResponse, buildGeneralCompletionResponse,
                                    handleRename, collectOrhFiles, handleFormatting, handleCodeAction
  lsp_view.zig      (~520 lines) — handleDocumentSymbols, handleWorkspaceSymbol, containsIgnoreCase,
                                    handleSignatureHelp, findCallContext, extractParamLabels, trimRange,
                                    handleInlayHint, handleFoldingRange
  lsp_semantic.zig  (~145 lines) — handleSemanticTokens, classifyToken (self-contained, uses lexer only)
```

**Total: 9 files. Each under 600 lines. lsp.zig down from 3303 to ~430 lines.**

### Line Count Analysis (verified from source)

| Section | Lines | Target File |
|---------|-------|-------------|
| Imports | 23 | lsp.zig |
| Transport (readMessage, writeMessage) | 48 | lsp.zig |
| JSON Helpers (jsonStr/jsonObj/jsonInt/jsonArray/jsonBool/jsonId) | 40 | lsp_json.zig |
| JSON Response Builders (7 builders + appendJsonString + appendInt) | 123 | lsp_json.zig |
| Type definitions + free functions | 57 | lsp_types.zig |
| URI Helpers | 41 | lsp_utils.zig |
| Type Formatting | 107 | lsp_analysis.zig |
| Analysis (runAnalysis + extractSymbols + extractLocals + helpers) | 467 | lsp_analysis.zig |
| Phase 2 Response Builders | 106 | lsp_json.zig |
| Text Utilities | 76 | lsp_utils.zig |
| Symbol Lookup | 139 | lsp_utils.zig |
| Server loop (serve + lspLog) | 383 | lsp.zig |
| runAndPublishWithDiags + PublishResult | 39 | lsp.zig |
| Navigation: hover + definition + docSymbols | 125 | lsp_nav.zig |
| Completion (handler + 10 helpers) | 319 | lsp_edit.zig |
| References | 86 | lsp_nav.zig |
| Rename + collectOrhFiles | 136 | lsp_edit.zig |
| Signature Help | 117 | lsp_view.zig |
| Formatting | 61 | lsp_edit.zig |
| Workspace Symbol + containsIgnoreCase | 73 | lsp_view.zig |
| Inlay Hints | 94 | lsp_view.zig |
| Code Actions | 79 | lsp_edit.zig |
| Param Label Extraction | 78 | lsp_view.zig |
| Document Highlight | 64 | lsp_nav.zig |
| Folding Ranges | 110 | lsp_view.zig |
| Semantic Tokens + classifyToken | 143 | lsp_semantic.zig |
| Tests | 164 | distributed to matching files |

### Pattern: Flat File Naming (from Phase 29)

Phase 29 established the `src/codegen_*.zig` pattern -- flat files in `src/`, not a subdirectory. This phase follows the same convention: `src/lsp_*.zig`.

**Rationale:** The `src/peg/` subdirectory pattern is used for the PEG engine (a self-contained subsystem). Code-split files that are peers of the main module use flat naming.

### Pattern: No Wrapper Stubs Needed

Unlike Phase 29 where `CodeGen` struct methods required wrapper stubs for delegation, lsp.zig uses standalone functions with explicit parameters. Moving them just means:

1. Add `pub` to the function
2. Move it to the target file
3. Import the target file in `lsp.zig`
4. Call via `module.functionName()` from `serve()`

```zig
// In lsp.zig — dispatch calls handler from imported module
const lsp_nav = @import("lsp_nav.zig");
// ...
const resp = lsp_nav.handleHover(allocator, root, id, cached_symbols, &doc_store) catch |err| { ... };
```

```zig
// In lsp_nav.zig — handler imports shared utilities
const lsp = @import("lsp.zig");
const lsp_types = @import("lsp_types.zig");
const lsp_json = @import("lsp_json.zig");
const lsp_utils = @import("lsp_utils.zig");
// ...
pub fn handleHover(allocator: std.mem.Allocator, root: std.json.Value, id: std.json.Value, symbols: []const lsp_types.SymbolInfo, doc_store: *const std.StringHashMap([]u8)) ![]u8 {
    // body unchanged
}
```

### Import Dependency Graph

```
lsp_types.zig  <-- imports nothing from lsp_*; imports std, lexer, parser, declarations, types
    ^
    |
lsp_json.zig   <-- imports lsp_types (for Diagnostic, SymbolInfo, SymbolKind)
    ^
    |
lsp_utils.zig  <-- imports lsp_types, lsp_json (for buildEmptyResponse used in builtinDetail)
    ^
    |
lsp_analysis.zig <-- imports lsp_types, lsp_utils (for lspLog via lsp.zig), + compiler passes
    ^
    |--- lsp_nav.zig     <-- imports lsp_types, lsp_json, lsp_utils
    |--- lsp_edit.zig    <-- imports lsp_types, lsp_json, lsp_utils
    |--- lsp_view.zig    <-- imports lsp_types, lsp_json, lsp_utils
    |--- lsp_semantic.zig <-- imports lsp_types, lsp_json (minimal deps)
    |
lsp.zig (serve) <-- imports all of the above; dispatches to handler modules
```

### Key Design Decision: lspLog Location

`lspLog` is called from many files (serve loop, handlers, analysis). Options:
1. **Keep in lsp.zig, make pub** -- handlers import lsp.zig for logging. This is clean because lsp.zig is the entry point and all handler files already import it for types.
2. **Move to lsp_types.zig** -- avoids circular-feeling imports.

**Recommendation:** Put `lspLog` in `lsp.zig` and make it `pub`. Handler files import `lsp.zig` for the log function. No circular dependency issue because Zig resolves imports statically and lsp.zig only calls handler functions, it doesn't import their types.

Actually, there is a subtlety: if `lsp_analysis.zig` imports `lsp.zig` for `lspLog`, and `lsp.zig` imports `lsp_analysis.zig` for `runAnalysis`, this creates a **circular import**. Zig handles circular imports at the module level, but it can cause complications.

**Better recommendation:** Move `lspLog` to `lsp_utils.zig` to avoid any circularity concerns. All files can import `lsp_utils.zig` safely.

### Anti-Patterns to Avoid
- **Circular imports between handler files:** Handler files should never import each other. All shared code goes through `lsp_types.zig`, `lsp_json.zig`, or `lsp_utils.zig`.
- **Breaking function signatures:** Every moved function must keep its exact parameter list and return type. This is a move-only refactor.
- **Forgetting to update build.zig:** New files must be added to the `test_files` array in `build.zig` or their unit tests will not be discovered.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-file function dispatch | Wrapper stubs (like codegen) | Direct `pub fn` + import | LSP has no central struct; stubs are unnecessary overhead |
| Shared state threading | New context struct | Explicit parameter passing | Already the pattern; don't add a struct where one doesn't exist |

**Key insight:** The LSP code is already well-structured for splitting -- standalone functions with explicit params. The split is mostly mechanical: move, make pub, update imports.

## Common Pitfalls

### Pitfall 1: Circular Imports Between lsp.zig and Handler Files
**What goes wrong:** lsp.zig imports lsp_analysis.zig for `runAnalysis`, and lsp_analysis.zig imports lsp.zig for `lspLog`. Zig can technically handle this but it causes confusing compilation errors if types don't resolve cleanly.
**Why it happens:** Functions that both call and are called by the server loop.
**How to avoid:** Put shared utilities (lspLog, JSON helpers, type defs) in leaf modules (lsp_utils.zig, lsp_json.zig, lsp_types.zig) that don't import the main lsp.zig.
**Warning signs:** "dependency loop detected" or "unable to resolve" errors during `zig build`.

### Pitfall 2: Missing pub on Moved Functions
**What goes wrong:** Functions that were file-private in lsp.zig need `pub` when moved to separate files.
**Why it happens:** In a monolithic file, everything is visible. After splitting, only `pub` functions are accessible cross-file.
**How to avoid:** Add `pub` to every function that will be called from another file. This includes helper functions called by handlers AND utility functions called by other utilities.
**Warning signs:** "not accessible" compilation errors.

### Pitfall 3: Tests Referencing Private Functions After Move
**What goes wrong:** Unit tests that tested private helpers (like `isIdentChar`, `findCallContext`) break because they can no longer see the function.
**Why it happens:** Tests were in the same file as the function; after splitting, the test and function are in different files.
**How to avoid:** Move each test to the same file as the function it tests. Tests that exercise `uriToPath` go to `lsp_utils.zig`, tests for `classifyToken` go to `lsp_semantic.zig`, etc.
**Warning signs:** "undeclared identifier" in test blocks.

### Pitfall 4: Forgetting build.zig test_files Update
**What goes wrong:** Unit tests in new files are silently not run.
**Why it happens:** `zig build test` only runs tests in files listed in `build.zig`'s `test_files` array.
**How to avoid:** Add every new `lsp_*.zig` file to the `test_files` array. Remove the old `src/lsp.zig` entry only after confirming all tests moved.
**Warning signs:** Test count drops after split (should be caught by `./testall.sh` if it checks test count, but verify manually).

### Pitfall 5: Type Visibility Across Files
**What goes wrong:** Types like `SymbolInfo`, `Diagnostic`, `CompletionItemKind` are used everywhere. If they stay in `lsp.zig`, every handler file must import lsp.zig, creating potential circular dependencies.
**Why it happens:** Types were defined inline in the monolithic file.
**How to avoid:** Move ALL shared types to `lsp_types.zig` first (wave 1), then split handlers (wave 2). This establishes the shared foundation before anything depends on it.
**Warning signs:** Compile errors about unknown types in handler files.

## Code Examples

### Handler File Template
```zig
// lsp_nav.zig -- LSP navigation handlers (hover, definition, references, highlight)

const std = @import("std");
const lsp_types = @import("lsp_types.zig");
const lsp_json = @import("lsp_json.zig");
const lsp_utils = @import("lsp_utils.zig");

const SymbolInfo = lsp_types.SymbolInfo;

pub fn handleHover(allocator: std.mem.Allocator, root: std.json.Value, id: std.json.Value, symbols: []const SymbolInfo, doc_store: *const std.StringHashMap([]u8)) ![]u8 {
    const params = lsp_json.jsonObj(root, "params") orelse return lsp_json.buildEmptyResponse(allocator, id);
    // ... rest unchanged, just prefix shared calls with module name
}
```

### Main lsp.zig Dispatch Pattern
```zig
// lsp.zig -- LSP server loop and transport
const lsp_nav = @import("lsp_nav.zig");
const lsp_edit = @import("lsp_edit.zig");
const lsp_view = @import("lsp_view.zig");
const lsp_semantic = @import("lsp_semantic.zig");
const lsp_analysis = @import("lsp_analysis.zig");
const lsp_json = @import("lsp_json.zig");
const lsp_types = @import("lsp_types.zig");
const lsp_utils = @import("lsp_utils.zig");

// In serve() dispatch:
} else if (std.mem.eql(u8, method, "textDocument/hover")) {
    if (!initialized) continue;
    const resp = lsp_nav.handleHover(allocator, root, id, cached_symbols, &doc_store) catch |err| {
        lsp_utils.lspLog("hover error: {}", .{err});
        try writeMessage(stdout, try lsp_json.buildEmptyResponse(allocator, id));
        continue;
    };
    defer allocator.free(resp);
    try writeMessage(stdout, resp);
```

### Test Distribution Example
```zig
// In lsp_utils.zig, at the bottom:
test "uriToPath converts file URI" {
    const path = uriToPath("file:///home/user/project/src/main.orh");
    try std.testing.expectEqualStrings("/home/user/project/src/main.orh", path.?);
}

test "isIdentChar recognizes valid chars" {
    try std.testing.expect(isIdentChar('a'));
    // ...
}
```

## Test Distribution Map

| Test Name | Current Line | Target File |
|-----------|-------------|-------------|
| uriToPath converts file URI | 3143 | lsp_utils.zig |
| uriToPath returns null for non-file URI | 3148 | lsp_utils.zig |
| findProjectRoot detects src directory | 3152 | lsp_utils.zig |
| appendJsonString escapes special characters | 3157 | lsp_json.zig |
| readMessage parses LSP header | 3164 | lsp.zig |
| readMessage rejects oversized content-length | 3172 | lsp.zig |
| readMessage accepts valid content-length | 3180 | lsp.zig |
| getWordAtPosition finds identifier | 3189 | lsp_utils.zig |
| getWordAtPosition finds word on second line | 3195 | lsp_utils.zig |
| isIdentChar recognizes valid chars | 3201 | lsp_utils.zig |
| findCallContext finds function name and active param | 3210 | lsp_view.zig |
| findCallContext returns null for no call | 3226 | lsp_view.zig |
| findCallContext handles nested parens | 3231 | lsp_view.zig |
| containsIgnoreCase matches | 3237 | lsp_view.zig |
| extractParamLabels single param | 3245 | lsp_view.zig |
| extractParamLabels multiple params | 3252 | lsp_view.zig |
| extractParamLabels no params | 3260 | lsp_view.zig |
| classifyToken keywords | 3265 | lsp_semantic.zig |
| runAnalysis arena does not leak | 3276 | lsp_analysis.zig |
| runAnalysis can be called twice | 3293 | lsp_analysis.zig |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig built-in `test` blocks, 0.15.2 |
| Config file | `build.zig` (test_files array) |
| Quick run command | `zig build test` |
| Full suite command | `./testall.sh` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPLIT-01 | lsp.zig split into 8+ files, none >600 lines | structural | `wc -l src/lsp*.zig` (all under 600) | Wave 0 (line count check) |
| SPLIT-02 | Zero behavior change | unit + integration | `./testall.sh` | Existing (20 LSP unit tests + 11 test stages) |

### Sampling Rate
- **Per task commit:** `zig build test && ./testall.sh`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure (20 unit tests in lsp.zig + 11 shell test stages) covers all phase requirements. Tests just need to be moved alongside their code.

## Execution Strategy

### Wave 1: Foundation (lsp_types.zig + lsp_json.zig)
Move shared types and JSON infrastructure first. These are leaf modules with no LSP-internal dependencies.

1. Create `lsp_types.zig` with all type definitions, enums, constants, and free functions
2. Create `lsp_json.zig` with all JSON helpers and response builders
3. Update `lsp.zig` to import these and remove moved code
4. Add both files to `build.zig` test_files
5. Verify: `zig build test && ./testall.sh`

### Wave 2: Utilities (lsp_utils.zig)
Move text utilities, URI helpers, symbol lookup, and lspLog.

1. Create `lsp_utils.zig` with URI, text, symbol lookup functions + lspLog
2. Update `lsp.zig` to import and remove moved code
3. Move relevant tests
4. Verify: `zig build test && ./testall.sh`

### Wave 3: Analysis (lsp_analysis.zig)
Move analysis pipeline and type formatting.

1. Create `lsp_analysis.zig` with runAnalysis, extractSymbols, extractLocals, toDiagnostics, formatType/Sig functions
2. Update `lsp.zig` to import
3. Move relevant tests
4. Verify: `zig build test && ./testall.sh`

### Wave 4: Handlers (lsp_nav.zig, lsp_edit.zig, lsp_view.zig, lsp_semantic.zig)
Move all handler functions. These depend on waves 1-3.

1. Create all 4 handler files
2. Update `lsp.zig` serve() dispatch to call via module prefix
3. Move relevant tests
4. Add all files to `build.zig` test_files
5. Verify: `zig build test && ./testall.sh`

## Sources

### Primary (HIGH confidence)
- `src/lsp.zig` -- Direct source code analysis (3303 lines, all section headers, all function signatures)
- `src/codegen.zig` + `src/codegen_decls.zig` -- Phase 29 split pattern (import convention, naming)
- `build.zig` -- test_files array structure
- `.planning/phases/29-codegen-split/29-01-SUMMARY.md` -- Lessons learned from prior split

### Secondary (MEDIUM confidence)
- `.planning/phases/29-codegen-split/29-CONTEXT.md` -- Split strategy decisions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new deps, pure refactor
- Architecture: HIGH -- file structure verified by line-by-line source analysis
- Pitfalls: HIGH -- informed by Phase 29 actual deviations (pub visibility, build.zig, line count surprises)

**Research date:** 2026-03-29
**Valid until:** 2026-04-28 (stable; file structure does not change frequently)
