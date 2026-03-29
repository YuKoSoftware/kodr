# Phase 29: Codegen Split - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Split the monolithic `src/codegen.zig` (4354 lines, 98 functions) into 2-3 focused files with shared helpers. Zero behavior changes — generated Zig output must be byte-for-byte identical. 262 tests are the safety net.

</domain>

<decisions>
## Implementation Decisions

### File Split Strategy
- **D-01:** Split by construct type: declarations (structs, enums, bitfields, consts, compt), expressions (all generateExpr/generateExprMir + related), statements (control flow, blocks, loops, match). The main `codegen.zig` keeps the `CodeGen` struct definition, `init`/`deinit`, `generate()` entry point, and top-level dispatch.
- **D-02:** AST and MIR variants of the same construct stay together in the same file (e.g., `generateFunc` and `generateFuncMir` both go in the declarations file). They're logically paired and will eventually converge.

### Helper Extraction
- **D-03:** Extract emit helpers (`emit`, `emitFmt`, `emitIndent`, `emitLine`, `emitLineFmt`, `emitTypePath`, `emitTypeMirPath`, `flushPreStmts`) and type mapping (`typeToZig`, `allocTypeStr`) to a shared module that all codegen files import.
- **D-04:** The `CodeGen` struct definition remains in `codegen.zig`. Helper files receive `*CodeGen` as a parameter, or helpers are methods on the struct that Zig resolves via `@import` + `pub usingnamespace` pattern. Planner decides the exact Zig mechanism.

### Scope
- **D-05:** This is a pure refactor. No function signatures change, no codegen behavior changes, no new features. If a function is being moved, it must produce identical output.
- **D-06:** Utility/query functions (`getNodeInfo`, `getTypeClass`, `isEnumVariant`, `isStringExpr`, `isErrorConstant`, etc.) go with the helpers or stay with the struct — wherever they're most used. Planner decides based on call-site analysis.

### Claude's Discretion
- Exact file names (e.g., `codegen_decls.zig`, `codegen_expr.zig`, `codegen_stmt.zig` vs other names)
- Exact function grouping boundaries — planner should analyze call graphs to minimize cross-file dependencies
- Whether to use `usingnamespace` pattern or explicit function re-exports

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Compiler Architecture
- `docs/COMPILER.md` — Compiler pipeline architecture, pass descriptions, codegen's role (pass 11)
- `src/codegen.zig` — The file being refactored (4354 lines, 98 functions)
- `src/mir.zig` — MIR types consumed by codegen (NodeMap, MirNode, NodeInfo, TypeClass)
- `src/parser.zig` — AST types consumed by codegen (Node, NodeKind, FuncDecl, VarDecl, etc.)

### Codebase Maps
- `.planning/codebase/STRUCTURE.md` — Project file structure
- `.planning/codebase/CONVENTIONS.md` — Naming and organization conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Current Structure (4354 lines)
- **Lines 1-62:** Imports and CodeGen struct definition (30+ fields)
- **Lines 63-293:** Query methods, init/deinit, emit helpers, typeToZig-related
- **Lines 295-455:** `generate()` entry point, top-level dispatch, import handling
- **Lines 456-1395:** Declaration generators (func, struct, enum, bitfield, const, var, compt, test)
- **Lines 1414-1650:** Statement generators (block, statements, stmt decls)
- **Lines 1650-2693:** Expression generators (AST path)
- **Lines 2693-3880:** MIR expression generators + match/interpolation/collection
- **Lines 3880-4354:** Compiler func generators, ptr coercion, fill default args, typeToZig

### Function Pairs (AST + MIR)
These function pairs exist side-by-side and generate identical output:
- `generateFunc` / `generateFuncMir`
- `generateExpr` / `generateExprMir`
- `generateInterpolatedString` / `generateInterpolatedStringMir`
- `generateCollectionExpr` / `generateCollectionExprMir`
- `generateCompilerFunc` / `generateCompilerFuncMir`
- `generatePtrCoercion` / `generatePtrCoercionMir`
- `collectAssigned` / `collectAssignedMir`
- Multiple others (wrapping, saturating, overflow arithmetic)

### Key Dependencies
- All functions are methods on `CodeGen` struct
- `emit*` helpers are called from every function
- `typeToZig` is called from declarations, expressions, and statements
- `getNodeInfo`/`getTypeClass` query methods used throughout

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The goal is purely structural: make the file manageable so future features (blueprints, closures) are easier to add.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 29-codegen-split*
*Context gathered: 2026-03-28*
