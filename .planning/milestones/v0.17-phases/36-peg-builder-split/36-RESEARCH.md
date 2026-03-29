# Phase 36: PEG Builder Split - Research

**Researched:** 2026-03-29
**Domain:** Zig file refactoring — split large source file into satellite modules
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Split into 5 satellite files: `builder_decls.zig`, `builder_stmts.zig`, `builder_exprs.zig`, `builder_types.zig`, plus `builder.zig` as the hub
- **D-02:** `builder.zig` retains: BuildContext struct, SyntaxError, buildAST/buildASTWithArena entry points, buildNode dispatch function, shared helpers (tokenText, findTokenInRange, buildAllChildren, collectExprsRecursive, collectCallArgs, collectParamsRecursive, buildTokenNode, buildChildrenByRule)
- **D-03:** No single satellite file should exceed ~510 lines
- **D-04:** `builder_decls.zig` (~620 lines): buildProgram, buildModuleDecl, buildImport, buildMetadata, buildFuncDecl, buildParam, buildConstDecl, buildVarDecl, buildStructDecl, collectStructParts, hasPubBefore, buildEnumDecl, collectEnumMembers, buildFieldDecl, buildEnumVariant, buildDestructDecl, buildDestructFromTail, buildBitfieldDecl, buildTestDecl, buildPubDecl, buildComptDecl, buildBridgeDecl, buildBridgeFunc, buildBridgeConst, buildBridgeStruct, buildThreadDecl, setPub
- **D-05:** `builder_stmts.zig` (~210 lines): buildBlock, buildReturn, buildThrowStmt, buildIf, buildElifChain, buildWhile, buildFor, buildDefer, buildMatch, buildMatchArm, buildExprOrAssignment
- **D-06:** `builder_exprs.zig` (~350 lines): buildIntLiteral, buildFloatLiteral, buildStringLiteral, buildBoolLiteral, buildIdentifier, buildErrorLiteral, buildCompilerFunc, buildArrayLiteral, buildGroupedExpr, buildTupleLiteral, buildStructExpr, buildBinaryExpr, buildCompareExpr, buildRangeExpr, buildNotExpr, buildUnaryExpr, buildPostfixExpr
- **D-07:** `builder_types.zig` (~170 lines): buildNamedType, buildKeywordType, buildScopedType, buildScopedGenericType, buildGenericType, collectGenericArgs, buildBorrowType, buildRefType, buildParenType, buildSliceType, buildArrayType, buildFuncType
- **D-08:** Mirror the codegen split pattern exactly: `builder.zig` imports satellites as `const decls_impl = @import("builder_decls.zig")` etc. The `buildNode` dispatch calls satellite functions directly (e.g., `return decls_impl.buildProgram(ctx, cap)`)
- **D-09:** All satellite functions take `*BuildContext` as first parameter — BuildContext stays in `builder.zig` and satellites import it
- **D-10:** Tests stay in `builder.zig` since they test the integrated behavior through buildAST entry points.

### Claude's Discretion
- Exact line where helpers end and satellite boundary begins
- Whether buildDestructFromTail stays with buildDestructDecl in decls or goes to stmts (recommendation: keep with decls since it's part of destructuring declaration logic)
- If decls exceeds 510 lines, whether to split further into `builder_bridge.zig`

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPLIT-06 | peg/builder.zig split into 6+ files — context, dispatch, decls, stmts, exprs, and types (mirrors codegen pattern) | builder.zig is 1836 lines with clear section boundaries; codegen split pattern is the proven template |
| SPLIT-02 | Zero behavior change gate — `./testall.sh` passes all tests before and after each split, unit tests work in new locations | All builder tests are in builder.zig and test through buildAST entry points; peg.zig re-exports keep public API stable |
</phase_requirements>

---

## Summary

`src/peg/builder.zig` is a 1836-line file that transforms PEG capture trees into parser.Node AST nodes. It has five natural sections separated by comments: BuildContext (lines 1-98), public API + dispatch (99-225), shared helpers (226-345), and four function groups: decls (347-984), stmts (986-1197), exprs (1198-1544), types (1545-1709), and tests (1710-1836).

The split follows the identical pattern used in Phase 29 (codegen split). The pattern is: `builder.zig` becomes the hub holding BuildContext, the public API, dispatch function, and shared helpers; four satellite files (`builder_decls.zig`, `builder_stmts.zig`, `builder_exprs.zig`, `builder_types.zig`) hold the builder functions for each category. The hub imports satellites and the dispatch function (`buildNode`) routes by calling satellite functions directly.

The only structural difference from the codegen split is that `buildNode` is a free function (not a method on a struct), and all satellite functions receive `*BuildContext` as a parameter (not a self receiver). The import chain `peg.zig` → `peg/builder.zig` means only `builder.zig` needs to be updated — `peg.zig` already re-exports `BuildContext`, `BuildResult`, `buildAST`, and `buildASTWithArena` by name, so those re-exports remain stable after the split.

**Primary recommendation:** Follow the codegen split template exactly, with the hub calling `decls_impl.buildFuncDecl(ctx, cap)` etc. The decls section is ~638 lines — the discretion call is whether to split bridge declarations into a `builder_bridge.zig` to stay under 510 lines.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Zig stdlib | 0.15.2+ | File I/O, data structures, testing | Project requirement — all compiler code is Zig |

No new dependencies — this is a pure refactor of existing Zig source.

**Installation:** None required.

---

## Architecture Patterns

### Recommended Project Structure (after split)

```
src/peg/
├── builder.zig          # Hub: BuildContext, SyntaxError, BuildResult, buildAST, buildASTWithArena, buildNode dispatch, shared helpers, tests
├── builder_decls.zig    # Satellite: declaration builders (program through thread_decl)
├── builder_stmts.zig    # Satellite: statement builders (block through expr_or_assignment)
├── builder_exprs.zig    # Satellite: expression builders (int_literal through postfix_expr)
└── builder_types.zig    # Satellite: type builders (named_type through func_type)
```

### Pattern 1: Hub-Satellite Import (from codegen split)

The hub imports each satellite with a namespaced alias:

```zig
// builder.zig — imports at top, after existing imports
const decls_impl = @import("builder_decls.zig");
const stmts_impl = @import("builder_stmts.zig");
const exprs_impl = @import("builder_exprs.zig");
const types_impl = @import("builder_types.zig");
```

Then `buildNode` dispatches through the namespace:

```zig
if (std.mem.eql(u8, rule, "program")) return decls_impl.buildProgram(ctx, cap);
if (std.mem.eql(u8, rule, "func_decl")) return decls_impl.buildFuncDecl(ctx, cap);
if (std.mem.eql(u8, rule, "block")) return stmts_impl.buildBlock(ctx, cap);
// ...etc
```

### Pattern 2: Satellite File Header (from codegen_decls.zig template)

Each satellite starts with the same preamble — import builder.zig for BuildContext, import other dependencies directly:

```zig
// builder_decls.zig — Declaration builders for the PEG AST builder
// Contains: program, module_decl, import, func_decl, struct_decl, enum_decl, etc.
// All functions receive *BuildContext as first parameter.

const std = @import("std");
const builder = @import("builder.zig");
const parser = @import("../parser.zig");
const lexer = @import("../lexer.zig");
const capture_mod = @import("capture.zig");
const CaptureNode = capture_mod.CaptureNode;
const Node = parser.Node;
const Token = lexer.Token;
const TokenKind = lexer.TokenKind;

const BuildContext = builder.BuildContext;
```

Note: `BuildContext` must be `pub` in `builder.zig` (it already is). Satellite functions call `buildNode` — since `buildNode` is a private function in `builder.zig`, satellites cannot call it directly. They call `builder.buildNodeFromSatellite(ctx, cap)` OR `buildNode` must be promoted to `pub`. See Pitfall 2 below.

### Pattern 3: Shared Helper Access from Satellites

Satellites need access to `tokenText`, `findTokenInRange`, `buildAllChildren`, `collectExprsRecursive`, `collectCallArgs`, `collectParamsRecursive`, `buildTokenNode`, `buildChildrenByRule`. These are private helpers in builder.zig that satellites depend on.

Two verified approaches (both used in codegen split):

**Option A — Make helpers pub in builder.zig:**
```zig
pub fn tokenText(ctx: *BuildContext, pos: usize) []const u8 { ... }
pub fn buildAllChildren(ctx: *BuildContext, cap: *const CaptureNode) ![]*Node { ... }
// ...etc
```
Then satellites call `builder.tokenText(ctx, pos)`.

**Option B — Mirror the codegen pattern with pub stubs in hub:**
The codegen split made all `CodeGen` methods `pub` to allow cross-file calls. For builder, the equivalent is making the free helper functions `pub`.

Option A is the direct equivalent. Option B would be adding `pub` to the specific functions satellites call.

### Pattern 4: buildNode Visibility

`buildNode` is recursive and called by many satellite functions (e.g., `buildFuncDecl` calls `buildNode` to build child nodes). Satellites need to call it. Since `buildNode` lives in `builder.zig`:

Make `buildNode` `pub` in `builder.zig`:
```zig
pub fn buildNode(ctx: *BuildContext, cap: *const CaptureNode) anyerror!*Node { ... }
```

This matches how the codegen split made CodeGen methods pub.

### Pattern 5: build.zig Registration

New satellite files must be added to the `test_files` slice in `build.zig`. The current entry is `"src/peg.zig"` which pulls in `builder.zig` via `_ = @import("peg/builder.zig")`. The satellites are not directly tested — they are tested through `builder.zig`'s tests. However, each satellite should still be registered so the Zig compiler checks them independently.

Add to `test_files`:
```zig
"src/peg/builder_decls.zig",
"src/peg/builder_stmts.zig",
"src/peg/builder_exprs.zig",
"src/peg/builder_types.zig",
```

The codegen split pattern puts satellites in the `test_files` array (confirmed: `src/codegen_decls.zig`, `src/codegen_stmts.zig`, `src/codegen_exprs.zig`, `src/codegen_match.zig` are all listed).

### Anti-Patterns to Avoid

- **Circular imports:** `builder.zig` imports satellites, satellites import `builder.zig`. This is NOT circular in Zig as long as satellites do not import each other. Each satellite only imports `builder.zig` for `BuildContext`.
- **Satellite importing sibling satellites:** `builder_decls.zig` should not import `builder_stmts.zig`. If decl builders need stmt builders they call through `builder.buildNode()`.
- **Private helpers left private:** Forgetting to `pub` the shared helpers will cause compile errors when satellites try to call them. Check all helpers used by the functions in each satellite.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Zig circular import avoidance | Complex re-export facades | Make hub functions pub | Zig handles same-package imports without circular issues |
| Test discovery for satellites | New test harness | Add to build.zig test_files array | Existing pattern already handles this |

---

## Actual Line Counts (measured from source)

| Section | Lines | Target Satellite | Within 510? |
|---------|-------|-----------------|-------------|
| Decls (line 347–984) | ~638 | builder_decls.zig | NO — ~128 lines over |
| Stmts (line 986–1197) | ~212 | builder_stmts.zig | YES |
| Exprs (line 1198–1544) | ~347 | builder_exprs.zig | YES |
| Types (line 1545–1709) | ~165 | builder_types.zig | YES |
| Hub (context + dispatch + helpers + tests) | ~472 | builder.zig | YES |

**Decls overrun:** The decls section is ~638 lines, not the estimated ~620. It exceeds the 510-line limit. Claude's Discretion (CONTEXT.md) explicitly covers this: "If decls exceeds 510 lines, whether to split further into `builder_bridge.zig`."

The bridge declarations (lines ~881–984) are a clean split point. They contain: `buildBridgeDecl`, `buildBridgeFunc`, `buildBridgeConst`, `buildBridgeStruct`, `buildThreadDecl`, `setPub`. That is roughly lines 881–984 = ~104 lines. Moving them to `builder_bridge.zig` would leave decls at ~534 lines (still slightly over). A better split point: also move `buildBitfieldDecl` and `buildTestDecl` (lines 809–856, ~48 lines) to bridge, bringing decls to ~486 lines and bridge to ~152 lines — both comfortably under 510.

Alternatively, the plan can treat the 510-line limit as a soft target and leave decls at 638 lines with a note that SPLIT-06 says "6+ files" and already targets 5 satellites. The success criteria says "no single file exceeds ~510 lines" — so a `builder_bridge.zig` split may be needed.

---

## Common Pitfalls

### Pitfall 1: buildNode Recursion Visibility
**What goes wrong:** Satellite functions (e.g., `buildFuncDecl`) call `buildNode` internally to build child nodes. If `buildNode` remains private in `builder.zig`, the satellite file fails to compile.
**Why it happens:** `buildNode` is currently `fn buildNode` (no `pub`), so it is package-private.
**How to avoid:** Change `fn buildNode` to `pub fn buildNode` in `builder.zig` before moving satellites. This is exactly what Phase 29 did with CodeGen methods.
**Warning signs:** `error: 'buildNode' is not public` at compile time.

### Pitfall 2: Shared Helper Visibility
**What goes wrong:** Satellites call `builder.tokenText`, `builder.findTokenInRange`, etc. — all currently private functions.
**Why it happens:** These are helper functions not in the public API, so they're `fn` not `pub fn`.
**How to avoid:** When writing each satellite, audit every helper it calls. Make those helpers `pub` in `builder.zig`. The full list of helpers that will need `pub`:
- `tokenText`
- `findTokenInRange`
- `buildTokenNode`
- `buildChildrenByRule`
- `collectExprsRecursive`
- `collectCallArgs`
- `collectParamsRecursive`
- `buildAllChildren`
- `hasPubBefore` (called from decls only — can stay private if decls is a satellite that imports from builder)
- `collectStructParts` (used internally in buildStructDecl — will move with it to decls)
- `collectEnumMembers` (used internally in buildEnumDecl — moves with it to decls)
- `buildDestructFromTail` (called from buildConstDecl/buildVarDecl — moves with them to decls)
- `collectGenericArgs` (called from buildGenericType — moves with it to types)
**Warning signs:** Compile errors on satellite helpers that call parent functions.

### Pitfall 3: peg.zig Re-export of SyntaxError
**What goes wrong:** `peg.zig` does not currently re-export `SyntaxError`. If downstream code (module.zig, etc.) imports `SyntaxError` through `peg.zig`, it would break.
**Why it happens:** `SyntaxError` is defined in `builder.zig` and accessed via `peg.zig`'s `_ = @import("peg/builder.zig")` test block — not as a named re-export.
**How to avoid:** `SyntaxError` stays in `builder.zig` and is not moved to a satellite, so no change needed. Verify `peg.zig` does not need to add a re-export.
**Warning signs:** No compile errors expected here — this is a non-issue as long as `SyntaxError` stays in `builder.zig`.

### Pitfall 4: Decls Function Dependencies on Each Other
**What goes wrong:** Within `builder_decls.zig`, functions call each other (e.g., `buildConstDecl` calls `buildDestructFromTail`, `buildStructDecl` calls `collectStructParts`). These calls become same-file calls within the satellite and work fine — but only if ALL the functions that a given function calls are co-located in the same satellite.
**Why it happens:** When moving functions to a satellite, a callee might be left behind in builder.zig.
**How to avoid:** Move helper functions with the primary function that calls them. The `hasPubBefore`, `collectStructParts`, `collectEnumMembers`, `buildDestructFromTail`, `collectGenericArgs` are internal-only helpers that should travel with their callers.
**Warning signs:** `error: use of undeclared identifier 'collectStructParts'` style errors.

### Pitfall 5: build.zig Test File Path for peg Satellites
**What goes wrong:** Satellite files are in `src/peg/`, not `src/`. The path in `test_files` must be `"src/peg/builder_decls.zig"`, not `"src/builder_decls.zig"`.
**Why it happens:** `builder.zig` lives in `src/peg/` and uses relative imports (`@import("../parser.zig")`). Satellites inherit this location.
**Warning signs:** `error: file not found` at build time.

---

## Code Examples

### Dispatch pattern after split

```zig
// builder.zig — buildNode after split
const decls_impl = @import("builder_decls.zig");
const stmts_impl = @import("builder_stmts.zig");
const exprs_impl = @import("builder_exprs.zig");
const types_impl = @import("builder_types.zig");

pub fn buildNode(ctx: *BuildContext, cap: *const CaptureNode) anyerror!*Node {
    const rule = cap.rule orelse return error.NoRule;
    ctx.current_pos = cap.start_pos;

    if (std.mem.eql(u8, rule, "program")) return decls_impl.buildProgram(ctx, cap);
    if (std.mem.eql(u8, rule, "module_decl")) return decls_impl.buildModuleDecl(ctx, cap);
    // ... remaining decls dispatch
    if (std.mem.eql(u8, rule, "block")) return stmts_impl.buildBlock(ctx, cap);
    // ... remaining stmts dispatch
    if (std.mem.eql(u8, rule, "int_literal")) return exprs_impl.buildIntLiteral(ctx, cap);
    // ... remaining exprs dispatch
    if (std.mem.eql(u8, rule, "named_type")) return types_impl.buildNamedType(ctx, cap);
    // ... remaining types dispatch

    if (cap.children.len > 0) return buildNode(ctx, &cap.children[0]);
    return buildTokenNode(ctx, cap);
}
```

### Satellite file skeleton

```zig
// builder_stmts.zig — Statement builders for the PEG AST builder
// Contains: buildBlock, buildReturn, buildThrowStmt, buildIf, buildElifChain,
//           buildWhile, buildFor, buildDefer, buildMatch, buildMatchArm, buildExprOrAssignment
// All functions receive *BuildContext as first parameter.

const std = @import("std");
const builder = @import("builder.zig");
const parser = @import("../parser.zig");
const capture_mod = @import("capture.zig");
const CaptureNode = capture_mod.CaptureNode;
const Node = parser.Node;

const BuildContext = builder.BuildContext;

// Function bodies moved verbatim from builder.zig
pub fn buildBlock(ctx: *BuildContext, cap: *const CaptureNode) !*Node {
    // ... (body unchanged)
}
```

### build.zig test_files additions

```zig
const test_files = [_][]const u8{
    // ... existing entries ...
    "src/peg.zig",             // already present — re-exports builder and pulls in its tests
    "src/peg/builder_decls.zig",
    "src/peg/builder_stmts.zig",
    "src/peg/builder_exprs.zig",
    "src/peg/builder_types.zig",
};
```

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — this is a pure Zig source refactor within the project)

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Zig built-in `test` blocks + shell integration tests |
| Config file | `build.zig` (test_files array) |
| Quick run command | `zig build test 2>&1 | tail -20` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPLIT-06 | builder.zig split into 5+ satellite files, no file > ~510 lines | structural | `ls -la src/peg/builder*.zig` | ❌ Wave 0 (files created in this phase) |
| SPLIT-06 | All builder functions accessible via original dispatch | unit | `zig build test` (builder tests in builder.zig) | ✅ existing |
| SPLIT-02 | Zero behavior change — all tests pass | integration | `./testall.sh` | ✅ existing |

### Sampling Rate

- **Per task commit:** `zig build test 2>&1 | tail -20`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all phase requirements. The 4 builder tests in `builder.zig` (lines 1714–1836) test through `buildAST` entry points and will continue to work after the split since they remain in `builder.zig`. No new test files are needed for Wave 0.

---

## Open Questions

1. **Decls satellite line count**
   - What we know: Measured at ~638 lines — 128 lines over the 510-line limit
   - What's unclear: Whether the plan should add a `builder_bridge.zig` satellite or accept 638 lines with a note
   - Recommendation: Add `builder_bridge.zig` (bridge_decl, bridge_func, bridge_const, bridge_struct, thread_decl, setPub — approximately lines 881–984 plus setPub at ~969) to bring decls under 510. This also satisfies SPLIT-06's "6+ files" requirement more cleanly. The CONTEXT.md discretion item explicitly anticipates this.

2. **setPub placement**
   - What we know: `setPub` (line 969) is a helper called by `buildPubDecl` and `buildComptDecl`, which are in decls. It's also a utility for any builder that sets pub flags.
   - What's unclear: Whether it goes in the hub or travels with decls/bridge
   - Recommendation: Move with decls since it has no callers outside the decls category.

---

## Sources

### Primary (HIGH confidence)
- Direct source read: `src/peg/builder.zig` (1836 lines) — full function inventory, line ranges, dependency graph
- Direct source read: `src/codegen.zig`, `src/codegen_decls.zig`, `src/codegen_stmts.zig` — exact split pattern to replicate
- Direct source read: `src/peg.zig` — re-export chain, test block for builder
- Direct source read: `build.zig` (test_files array) — how satellites are registered
- Direct source read: `.planning/phases/36-peg-builder-split/36-CONTEXT.md` — locked decisions and discretion areas

### Secondary (MEDIUM confidence)
- Accumulated context from STATE.md (Phase 33 mir-split decisions) — underscore-prefixed imports for shadowing avoidance, pub re-exports as facade pattern

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pure Zig stdlib, no new dependencies
- Architecture: HIGH — verified against actual source and working codegen split pattern
- Pitfalls: HIGH — derived from direct source inspection and known Phase 29/33/34/35 lessons

**Research date:** 2026-03-29
**Valid until:** 2026-04-28 (stable codebase, no external dependencies)
