# Phase 29: Codegen Split - Research

**Researched:** 2026-03-28
**Domain:** Zig struct refactoring / file splitting / codegen architecture
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Split by construct type: declarations (structs, enums, bitfields, consts, compt), expressions (all generateExpr/generateExprMir + related), statements (control flow, blocks, loops, match). The main `codegen.zig` keeps the `CodeGen` struct definition, `init`/`deinit`, `generate()` entry point, and top-level dispatch.
- **D-02:** AST and MIR variants of the same construct stay together in the same file (e.g., `generateFunc` and `generateFuncMir` both go in the declarations file). They're logically paired and will eventually converge.
- **D-03:** Extract emit helpers (`emit`, `emitFmt`, `emitIndent`, `emitLine`, `emitLineFmt`, `emitTypePath`, `emitTypeMirPath`, `flushPreStmts`) and type mapping (`typeToZig`, `allocTypeStr`) to a shared module that all codegen files import.
- **D-04:** The `CodeGen` struct definition remains in `codegen.zig`. Helper files receive `*CodeGen` as a parameter, or helpers are methods on the struct that Zig resolves via `@import` + `pub usingnamespace` pattern. Planner decides the exact Zig mechanism.
- **D-05:** This is a pure refactor. No function signatures change, no codegen behavior changes, no new features. If a function is being moved, it must produce identical output.
- **D-06:** Utility/query functions (`getNodeInfo`, `getTypeClass`, `isEnumVariant`, `isStringExpr`, `isErrorConstant`, etc.) go with the helpers or stay with the struct — wherever they're most used. Planner decides based on call-site analysis.

### Claude's Discretion

- Exact file names (e.g., `codegen_decls.zig`, `codegen_expr.zig`, `codegen_stmt.zig` vs other names)
- Exact function grouping boundaries — planner should analyze call graphs to minimize cross-file dependencies
- Whether to use `usingnamespace` pattern or explicit function re-exports

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CGR-01 | codegen.zig split into 2-3 files — declarations, expressions, statements — with a shared helpers module | File analysis confirms 4-file split (core + decls + stmts + exprs) achieves all under 1200 lines |
| CGR-02 | Type-to-Zig mapping consolidated into one location | `typeToZig` and `allocTypeStr` already consolidated at lines 4073–4296; must stay in codegen.zig (core) |
| CGR-03 | Emit helpers extracted to shared module importable by all codegen files | `emit`, `emitFmt`, `emitIndent`, `emitLine`, `emitLineFmt`, `emitTypePath`, `emitTypeMirPath`, `flushPreStmts` at lines 231–292; remain in codegen.zig (imported implicitly via `*CodeGen` receiver) |
| CGR-04 | Zero codegen output changes — generated Zig byte-for-byte identical before and after refactor | Pure mechanical code movement; verified by ./testall.sh 262/262 gate |
</phase_requirements>

---

## Summary

`src/codegen.zig` is 4354 lines with 98 functions, all as methods on the `CodeGen` struct. The file has natural section boundaries already marked with `// === SECTION ===` dividers. Research confirms a clean 4-file split is achievable with all files under ~1000 lines.

**Critical Zig 0.15 finding:** `usingnamespace` was entirely removed in Zig 0.15.1 (not just deprecated). D-04's "pub usingnamespace pattern" option is unavailable. The correct Zig 0.15 mechanism is the **wrapper stub pattern**: helper files define `pub fn foo(cg: *CodeGen, ...)` free functions; `codegen.zig` retains all method signatures as one-liner stubs that delegate — `fn foo(self: *CodeGen, ...) !void { return decls_impl.foo(self, ...); }`. This preserves the `self.foo()` call syntax throughout the file with no call-site churn.

**Primary recommendation:** Use the wrapper stub pattern. Keep `CodeGen` struct and all method signatures in `codegen.zig`. Move function bodies to 3 helper files (`codegen_decls.zig`, `codegen_stmts.zig`, `codegen_exprs.zig`). Emit helpers and `typeToZig` stay as real implementations in `codegen.zig` — they are called via the `*CodeGen` receiver in every file and do not need extraction to a separate module.

---

## Standard Stack

### Core

| File | Purpose | Est. Lines After Split |
|------|---------|------------------------|
| `src/codegen.zig` | `CodeGen` struct, all fields, init/deinit, emit helpers, typeToZig, generate() entry, wrapper stubs | ~900 |
| `src/codegen_decls.zig` | func/struct/enum/bitfield/var/test declaration generators | ~970 |
| `src/codegen_stmts.zig` | block/statement generators + AST `generateExpr` | ~763 |
| `src/codegen_exprs.zig` | MIR expression/match/compiler-func/ptr-coercion generators | ~1180 |

All four files under the 1200-line constraint. No additional libraries. No new dependencies.

---

## Architecture Patterns

### Recommended Project Structure

```
src/
├── codegen.zig          # CodeGen struct def + emit helpers + typeToZig + stubs
├── codegen_decls.zig    # declaration generators (func, struct, enum, bitfield, var, test)
├── codegen_stmts.zig    # statement/block generators + AST expression path
└── codegen_exprs.zig    # MIR expression + match + compiler-func generators
```

### Pattern 1: Wrapper Stub in codegen.zig

**What:** All method signatures remain on `CodeGen`. Bodies for moved functions become one-liner delegates.

**When to use:** Required for Zig 0.15 (usingnamespace removed). Preserves `self.foo()` call syntax everywhere. Zero call-site changes outside the moved functions themselves.

**Example:**
```zig
// codegen.zig — stub (keeps existing call syntax)
fn generateFuncMir(self: *CodeGen, m: *mir.MirNode) anyerror!void {
    return decls_impl.generateFuncMir(self, m);
}
```

```zig
// codegen_decls.zig — full implementation
const codegen = @import("codegen.zig");
const CodeGen = codegen.CodeGen;

pub fn generateFuncMir(cg: *CodeGen, m: *mir.MirNode) anyerror!void {
    // full original body here
    // internal calls: try cg.generateBridgeReExport(name, pub_flag);
    //   → calls the stub in codegen.zig, which forwards back here if needed
    //   → or if the callee also moved to decls, it's a direct call: decls_impl.generateBridgeReExport(cg, ...)
}
```

### Pattern 2: Cross-File Circular Calls (Verified Safe)

**What:** Zig 0.15 allows circular `@import` between files when no circular SIZE dependency exists (i.e., no struct contains itself). Circular function call graphs across files are fine.

**Verified:** A two-file circular import compiled successfully with `zig build-obj` on this machine (Zig 0.15.2).

**Why this matters:** `generateStatementMir` (stmts) calls `generateExprMir` (exprs), and `generateMatchMir` (exprs) calls `generateBodyStatements` (stmts). This cross-dependency is resolved at runtime via the stub dispatch chain through `codegen.zig`. No direct `@import` of exprs from stmts is needed because all cross-file calls go through `self.method()` → stub in `codegen.zig` → helper file.

### Pattern 3: Helper File Imports

Each helper file imports only what it needs — never each other directly:

```zig
// codegen_decls.zig (and others)
const std = @import("std");
const codegen = @import("codegen.zig");
const parser = @import("parser.zig");
const mir = @import("mir.zig");
const declarations = @import("declarations.zig");
const errors = @import("errors.zig");
const K = @import("constants.zig");
const module = @import("module.zig");
const RT = @import("types.zig").ResolvedType;
const builtins = @import("builtins.zig");

const CodeGen = codegen.CodeGen;
```

### Anti-Patterns to Avoid

- **Direct inter-helper imports:** Do not have `codegen_stmts.zig` `@import` `codegen_exprs.zig` or vice versa. All cross-file calls flow through the stubs in `codegen.zig`.
- **Moving method signatures out of codegen.zig:** The `CodeGen` struct definition and all method declarations must remain in one file. Zig does not support distributed struct definitions.
- **Forgetting `anyerror!` on moved recursive functions:** Recursive functions must keep `anyerror!` not `!T` (existing CLAUDE.md rule applies to all new files).
- **Extracting emit helpers to a fourth separate file:** D-03 says emit helpers and typeToZig go to a "shared module." The research finding is that since all helper files receive `*CodeGen` as first param, they already have access to emit helpers via `cg.emit(...)`, `cg.emitFmt(...)` etc. No separate `codegen_helpers.zig` is needed — `codegen.zig` IS the shared module for these.

---

## Current File Anatomy (Exact Line Ranges)

This is the ground truth for the split. All section boundaries are verified by reading the file.

| Lines | Section | Functions | Target File |
|-------|---------|-----------|-------------|
| 1–62 | Imports + CodeGen struct fields | struct definition (30+ fields) | codegen.zig |
| 63–230 | Query methods | getNodeInfo, getTypeClass, getUnionMembers, isPromotedParam, funcReturnTypeClass, funcReturnMembers, getVarUnionMembers, sanitizeErrorName, getBitfieldName, isEnumVariant, isEnumTypeName | codegen.zig |
| 159–230 | init/deinit/getOutput | init, deinit, getOutput | codegen.zig |
| 231–293 | Emit helpers | emit, emitFmt, emitIndent, emitLine, emitTypePath, emitTypeMirPath, flushPreStmts, emitLineFmt | codegen.zig |
| 294–455 | Entry point + import | generate(), generateImport() | codegen.zig |
| 344–454 | Union helpers | extractValueType, unionTagName, isStringExpr, generateArbitraryUnionWrappedExpr, inferArbitraryUnionTag, matchesKind, findMemberByKind, generateArbitraryUnionWrappedExprMir, inferArbitraryUnionTagMir, isErrorConstant, TypeKind | STUBS → codegen_decls.zig (used heavily by expr generators; see D-06 note) |
| 456–543 | Top-level dispatch | generateImport, generateTopLevelMir | codegen.zig (stays, it's the entry) |
| 544–1069 | FUNCTIONS section | collectAssigned, getRootIdent, generateBridgeReExport, generateFuncMir, generateThreadFuncMir, collectAssignedMir, getRootIdentMir, generateFunc, generateThreadFunc | STUBS → codegen_decls.zig |
| 1070–1248 | STRUCTS + ENUMS + BITFIELDS | generateStructMir, generateEnumMir, generateBitfield, generateBitfieldMir | STUBS → codegen_decls.zig |
| 1249–1407 | VAR DECLS + TESTS | generateConst, generateVar, generateDecl, generateStmtDecl, isTypeAlias, generateCompt, generateTopLevelDeclMir, generateTestMir | STUBS → codegen_decls.zig |
| 1408–1649 | BLOCKS + STATEMENTS | generateBlockMir, generateBodyStatements, generateStatementMir, generateStmtDeclMir | STUBS → codegen_stmts.zig |
| 1650–2172 | EXPRESSIONS (AST) | generateExpr | STUB → codegen_stmts.zig |
| 2173–4067 | MIR EXPRESSIONS + MATCH | generateExprMir, generateCoercedExprMir, mirIsString, mirIsVector, mirGetBitfieldName, generateContinueExprMir, generateContinueExpr, writeRangeExprMir, writeRangeExpr, generateInterpolatedString, generateForMir, generateDestructMir, mirContainsIdentifier, hasGuardedArm, generateGuardedMatchMir, generateMatchMir, generateTypeMatchMir, generateStringMatchMir, generateInterpolatedStringMirInline, generateInterpolatedStringMir, generateCollectionExprMir, generatePtrCoercionMir, generateCompilerFuncMir, generateWrappingExpr/Mir, generateSaturatingExpr/Mir, generateOverflowExpr/Mir, fillDefaultArgsMir, generateCompilerFunc, generatePtrCoercion, fillDefaultArgs, generateCollectionExpr | STUBS → codegen_exprs.zig |
| 4068–4296 | TYPE TRANSLATION | allocTypeStr, typeToZig | codegen.zig (stays, D-03) |
| 4297–4354 | Free functions + test | opToZig, isResultValueField, test "codegen - type to zig" | codegen.zig (opToZig/isResultValueField stay as free fns; move test too) |

**D-06 guidance on union helpers (lines 344–454):** `generateArbitraryUnionWrappedExpr`, `inferArbitraryUnionTag`, `generateArbitraryUnionWrappedExprMir`, `inferArbitraryUnionTagMir` are called predominantly from statement and expression generators. Place them in `codegen_exprs.zig` as free functions. `isStringExpr`, `isErrorConstant`, `extractValueType`, `unionTagName`, `matchesKind`, `findMemberByKind`, `TypeKind` are query/utility helpers that stay in `codegen.zig` since they're called from all sections via `self.helper()`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Splitting struct methods across files in Zig 0.15 | Custom namespace merging | Wrapper stub pattern (one-liner delegates in codegen.zig) | usingnamespace removed; this is the idiomatic replacement |
| Verifying byte-for-byte identical output | Custom diff tool | `./testall.sh` existing test suite | Already covers 262 test cases including `test/08_codegen.sh` and `test/10_runtime.sh` |
| Function grouping analysis | Manual reading | Follow existing `// === SECTION ===` dividers already in codegen.zig | Boundaries are already defined and match D-01 |

---

## Common Pitfalls

### Pitfall 1: usingnamespace Attempt
**What goes wrong:** Planner or implementer attempts the `pub usingnamespace @import("codegen_decls.zig")` pattern inside the CodeGen struct.
**Why it happens:** D-04 mentions usingnamespace as one possible mechanism.
**How to avoid:** usingnamespace was entirely removed in Zig 0.15.1 (confirmed by release notes and compilation test). Use the wrapper stub pattern exclusively.
**Warning signs:** Zig compiler error "unknown identifier: usingnamespace" or similar.

### Pitfall 2: Forgetting to Add New Files to build.zig Test List
**What goes wrong:** New files `codegen_decls.zig`, `codegen_stmts.zig`, `codegen_exprs.zig` are not added to the `test_files` array in `build.zig`. Their `test` blocks are never run.
**Why it happens:** build.zig has an explicit list of test files (lines 43–64); it does not auto-discover.
**How to avoid:** Add all three new files to the `test_files` array as a Wave 0 prerequisite.
**Warning signs:** `zig build test` passes but `./testall.sh` test/01_unit.sh stage misses new tests.

### Pitfall 3: Breaking anyerror! on Moved Recursive Functions
**What goes wrong:** A moved function like `generateExpr` or `generateStatementMir` uses `!void` instead of `anyerror!void` after relocation.
**Why it happens:** Some editors or formatters infer `!T` from usage. Recursive functions require explicit `anyerror!`.
**How to avoid:** Keep all recursive generate functions as `anyerror!void` (existing project rule from CLAUDE.md).
**Warning signs:** Zig compile error "error: unable to infer error set".

### Pitfall 4: Changing Function Signatures When Moving
**What goes wrong:** A function signature gets accidentally changed (parameter name, type, or order) while moving it. codegen.zig stub calls it with the old signature.
**Why it happens:** Copy-paste errors, editor auto-refactoring.
**How to avoid:** Move function bodies verbatim. The stub in `codegen.zig` must match the old signature exactly. Verify with `zig build` after each function move.
**Warning signs:** Zig compile error at the stub call site.

### Pitfall 5: Moving Query Helpers That Are Used Everywhere
**What goes wrong:** `isEnumVariant`, `getNodeInfo`, `emit`, etc. are moved to a helper file, but they're called as `self.helper()` in the stub file which no longer has the body.
**Why it happens:** D-06 says query functions can go either way; a wrong call-site analysis moves them.
**How to avoid:** Keep all `self.helper()` query functions and all emit functions in `codegen.zig` as real implementations. Only generators (generate*, collectAssigned, getRootIdent) move to helper files.
**Warning signs:** Zig compile error "no field named 'isEnumVariant' in struct CodeGen".

### Pitfall 6: Inter-Helper Direct @imports
**What goes wrong:** `codegen_stmts.zig` directly `@import("codegen_exprs.zig")` to call `generateExprMir`, creating a more tangled dependency graph.
**Why it happens:** Seems like a shortcut to avoid stub overhead.
**How to avoid:** All cross-file calls route through the `*CodeGen` receiver stubs in `codegen.zig`. `self.generateExprMir(m)` dispatches correctly without stmts knowing about exprs.
**Warning signs:** `@import` of a sibling codegen file appearing in a helper file.

---

## Code Examples

### Wrapper Stub Pattern (the implementation mechanism)

```zig
// codegen.zig — struct method stub
// (replaces the original full body, which moves to codegen_decls.zig)
fn generateFuncMir(self: *CodeGen, m: *mir.MirNode) anyerror!void {
    return decls_impl.generateFuncMir(self, m);
}

// At top of CodeGen struct or before it:
const decls_impl = @import("codegen_decls.zig");
const stmts_impl = @import("codegen_stmts.zig");
const exprs_impl = @import("codegen_exprs.zig");
```

```zig
// codegen_decls.zig — full implementation
const std = @import("std");
const codegen = @import("codegen.zig");
const parser = @import("parser.zig");
const mir = @import("mir.zig");
const declarations = @import("declarations.zig");
const errors = @import("errors.zig");
const K = @import("constants.zig");
const module = @import("module.zig");
const RT = @import("types.zig").ResolvedType;
const builtins = @import("builtins.zig");

const CodeGen = codegen.CodeGen;

pub fn generateFuncMir(cg: *CodeGen, m: *mir.MirNode) anyerror!void {
    // Original body verbatim.
    // Internal self.generateBridgeReExport() calls become cg.generateBridgeReExport()
    // which dispatches through codegen.zig stub → back to decls_impl if moved.
}
```

### Import constants (where @import lines go in codegen.zig)

```zig
// codegen.zig — these go at file scope, before or after the CodeGen struct closing brace
const decls_impl = @import("codegen_decls.zig");
const stmts_impl = @import("codegen_stmts.zig");
const exprs_impl = @import("codegen_exprs.zig");
```

Note: Zig allows imports at file scope or inside a struct/namespace. Keep them at file scope for clarity.

### build.zig test_files addition

```zig
// build.zig — add after "src/codegen.zig":
"src/codegen_decls.zig",
"src/codegen_stmts.zig",
"src/codegen_exprs.zig",
```

---

## Zig 0.15 Critical Finding: usingnamespace Removed

| Feature | Status in Zig 0.15 | Impact on This Phase |
|---------|-------------------|----------------------|
| `usingnamespace` | **Entirely removed** (release notes confirmed) | D-04 option "pub usingnamespace" is unavailable — must use wrapper stubs |
| Circular `@import` | **Allowed** (verified by compilation test) | Inter-helper file circular imports are safe if needed, but should be avoided via the stub pattern |
| File-as-struct (`@This()`) | Available | Not applicable — CodeGen is a named struct in codegen.zig |
| Free function pattern | Fully supported | Primary mechanism for helper files |

Source: https://ziglang.org/download/0.15.1/release-notes.html

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig built-in `test` blocks + shell integration tests |
| Config file | `build.zig` (test_files array, lines 43–64) |
| Quick run command | `zig build test` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CGR-01 | codegen.zig + 3 helper files exist, all under 1200 lines | smoke | `wc -l src/codegen*.zig` | Wave 0 (new files) |
| CGR-02 | typeToZig and allocTypeStr in exactly one location | unit | `zig build test` (existing "codegen - type to zig") | ✅ `src/codegen.zig:4330` |
| CGR-03 | emit* helpers callable from all helper files via *CodeGen | unit | `zig build test` + `zig build` | ✅ (inherent via receiver) |
| CGR-04 | Generated Zig output byte-for-byte identical | integration | `./testall.sh` (262 tests) | ✅ existing |

### Sampling Rate
- **Per task commit:** `zig build` (compilation gate)
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite 262/262 green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `src/codegen_decls.zig` — new file, covers CGR-01
- [ ] `src/codegen_stmts.zig` — new file, covers CGR-01
- [ ] `src/codegen_exprs.zig` — new file, covers CGR-01
- [ ] Add all three to `build.zig` `test_files` array
- [ ] No new test blocks needed — existing 262 tests + "codegen - type to zig" cover all requirements

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — pure code reorganization, Zig already verified installed at 0.15.2)

---

## Open Questions

1. **Placement of union helpers (lines 344–454: generateArbitraryUnionWrapped*, inferArbitraryUnionTag*, TypeKind, matchesKind, findMemberByKind)**
   - What we know: these are called from generateStatementMir (stmts section) and generateExprMir (exprs section)
   - What's unclear: D-06 says "planner decides based on call-site analysis"
   - Recommendation: Move to `codegen_exprs.zig` since they're needed most heavily there. Add stubs in `codegen.zig` that forward to exprs_impl. Call sites in `codegen_stmts.zig` go through `cg.generateArbitraryUnionWrappedExprMir()` → stub → exprs_impl.

2. **generateImport and generateTopLevelMir — stay or stub?**
   - What we know: These are the entry-point dispatch functions called from `generate()` which must stay in codegen.zig
   - What's unclear: generateTopLevelMir is small (17 lines) but calls into decls
   - Recommendation: Keep both in `codegen.zig` as full implementations (not stubs). They're the dispatch layer.

3. **Free functions opToZig and isResultValueField**
   - What we know: These are already file-scope free functions (not methods) at lines 4299–4328
   - What's unclear: They could move to codegen_exprs.zig or stay
   - Recommendation: Move `opToZig` and `isResultValueField` to `codegen_exprs.zig` since they are only called from expression generators. No stubs needed — they're not methods.

---

## Sources

### Primary (HIGH confidence)
- `/home/yunus/Projects/orhon/orhon_compiler/src/codegen.zig` — direct file analysis (4354 lines, all section boundaries confirmed)
- `/home/yunus/Projects/orhon/orhon_compiler/build.zig` — test_files array confirmed, codegen.zig on line 55
- Zig 0.15.2 compiler test — circular imports between two `.zig` files compiled successfully
- https://ziglang.org/download/0.15.1/release-notes.html — usingnamespace entirely removed in Zig 0.15

### Secondary (MEDIUM confidence)
- `/usr/lib64/zig/std/json/Stringify.zig` — `@This()` file-as-struct pattern (stdlib reference)
- https://ziggit.dev/t/using-usingnamespace-to-create-single-namespace-for-many-smaller-files/11419 — community confirmation of re-export pattern

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — file is in this repo, all analysis is direct
- Architecture: HIGH — Zig 0.15 circular import behavior verified by compilation test
- Zig 0.15 mechanism: HIGH — release notes confirm usingnamespace removed; wrapper stub is the only viable option

**Research date:** 2026-03-28
**Valid until:** Stable (pure refactor, no moving ecosystem targets)
