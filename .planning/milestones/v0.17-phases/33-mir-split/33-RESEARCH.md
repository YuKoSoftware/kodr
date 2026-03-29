# Phase 33: MIR Split - Research

**Researched:** 2026-03-29
**Domain:** Zig module refactoring — splitting a monolithic source file into focused files using wrapper patterns
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Split by struct boundary — each major struct gets its own file. MirAnnotator, MirLowerer, UnionRegistry, and MirNode each move to dedicated files. Type definitions share a types module.
- **D-02:** The main `mir.zig` keeps the public re-exports so downstream importers (`@import("mir.zig")`) continue to work unchanged. No changes to codegen.zig or other consumers.
- **D-03:** Shared types module (`mir_types.zig` or similar) holds: TypeClass, Coercion, NodeInfo, NodeMap, MirKind, LiteralKind, IfNarrowing, and the `classifyType()` function. All split files import from this module.
- **D-04:** The `RT` alias (`types.ResolvedType`) is defined once in the types module and re-exported.
- **D-05:** MirNode gets its own file with `populateData()` and `astToMirKind()` helper functions that are tightly coupled to it.
- **D-06:** Follow the flat naming pattern from Phase 29/32: `src/mir_*.zig` files (not a subdirectory). Consistent with `src/codegen_*.zig` and `src/lsp_*.zig`.
- **D-07:** Pure refactor. No function signatures change, no behavior changes, no new MIR features. Generated output must be identical.
- **D-08:** Unit tests move to their new file locations alongside the code they test.

### Claude's Discretion

- Exact file names beyond the `mir_*` prefix
- Whether `mir.zig` uses `pub usingnamespace` or explicit re-exports for backward compatibility
- Exact helper function placement when a function is used by multiple structs — put it where it's most called

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPLIT-03 | mir.zig split into 6+ files — types, registry, node, annotator, lowerer, and utils | File boundary mapping below; wrapper stub pattern from Phase 29 applies directly |
| SPLIT-02 | Zero behavior change gate — `./testall.sh` passes all tests before and after each split, unit tests work in new locations | Tests must be moved with the code; `build.zig` `test_files` array must include all new files |

</phase_requirements>

## Summary

`src/mir.zig` is a 2356-line file containing 5 major structs, 20 private helpers, and 20 test blocks. The split follows the established `codegen`/`lsp` split patterns from Phases 29 and 32. The core technical pattern is already proven: flat `src/mir_*.zig` files, a shared types module, and `mir.zig` reduced to a thin re-export facade.

The primary risk in this refactor is cross-file visibility: Zig requires all struct methods that helper files need to call to be marked `pub`. MirAnnotator has private methods (`annotateNode`, `annotateExpr`, etc.) that call each other — if MirAnnotator stays in one file this is not a concern, but if private helpers need to be accessed via the struct pointer from other files, they must be made `pub`. Given D-01 puts MirAnnotator entirely in `mir_annotator.zig`, internal privacy is preserved.

The second risk is the `CoercionResult` type used internally by `detectCoercion`. It is a file-scoped type in mir.zig that is not exported — it must stay adjacent to `detectCoercion` and the annotator code. It belongs in `mir_annotator.zig` since it is only used there.

**Primary recommendation:** Follow the LSP split model — no wrapper stubs needed. Move structs wholesale to their files. `mir.zig` becomes a re-export hub with `pub const X = @import("mir_X.zig").X;` style explicit re-exports.

## Standard Stack

### Core (already in use — no additions)

| Library | Purpose |
|---------|---------|
| Zig stdlib (`std`) | All data structures: `AutoHashMapUnmanaged`, `ArrayListUnmanaged`, `ArenaAllocator` |
| `parser.zig` | AST node types consumed by all MIR files |
| `declarations.zig` | `DeclTable`, `FuncSig`, `ParamSig` consumed by MirAnnotator and MirLowerer |
| `types.zig` | `ResolvedType` — the central type used everywhere in MIR |
| `errors.zig` | `Reporter` used only by MirAnnotator |
| `builtins.zig` | Used only by MirAnnotator (for builtin name lookups) |
| `constants.zig` | `K` constants used only by MirAnnotator |

**Installation:** No new dependencies. This is a pure code reorganization.

## Architecture Patterns

### Established Pattern: LSP Split (Phase 32 — latest, closest analog)

The LSP split is the most recent prior art and is the closest structural match:
- lsp.zig had no central struct (standalone functions) → moved functions wholesale
- `mir.zig` has 5 structs → move structs wholesale, one per file
- `lsp.zig` did NOT use wrapper stubs — just direct function moves with updated imports
- lsp.zig's re-export is implicit (consumers import lsp.zig for `serve()`, not for types)

**Key difference from codegen split (Phase 29):** Phase 29 used wrapper stubs because `CodeGen` methods were split across files but all called via `*CodeGen`. For MIR the structs are independent — `MirAnnotator`, `MirLowerer`, `UnionRegistry`, and `MirNode` do not call each other's private methods. They pass each other as arguments. This means **no wrapper stubs are needed** — structs move cleanly to their own files.

### Recommended Project Structure After Split

```
src/
├── mir.zig              # ~50 lines: re-export facade only
├── mir_types.zig        # ~100 lines: TypeClass, Coercion, NodeInfo, NodeMap, classifyType, RT alias
├── mir_registry.zig     # ~80 lines: UnionRegistry
├── mir_node.zig         # ~280 lines: MirNode, LiteralKind, MirKind, IfNarrowing, accessor methods
├── mir_annotator.zig    # ~700 lines: MirAnnotator + CoercionResult + all private helpers + tests
└── mir_lowerer.zig      # ~700 lines: MirLowerer + populateData + astToMirKind + tests
```

### Pattern: Re-export Facade (mir.zig)

`mir.zig` becomes a thin re-export hub. All downstream consumers (`main.zig`, `codegen.zig`, `codegen_*.zig`) continue to `@import("mir.zig")` with zero changes.

```zig
// mir.zig — MIR (Mid-level Intermediate Representation) pass (pass 10)
// Public re-exports for backward compatibility. Implementation split across mir_*.zig files.

pub const TypeClass = @import("mir_types.zig").TypeClass;
pub const Coercion = @import("mir_types.zig").Coercion;
pub const NodeInfo = @import("mir_types.zig").NodeInfo;
pub const NodeMap = @import("mir_types.zig").NodeMap;
pub const classifyType = @import("mir_types.zig").classifyType;
pub const MirKind = @import("mir_node.zig").MirKind;
pub const LiteralKind = @import("mir_node.zig").LiteralKind;
pub const IfNarrowing = @import("mir_node.zig").IfNarrowing;
pub const MirNode = @import("mir_node.zig").MirNode;
pub const UnionRegistry = @import("mir_registry.zig").UnionRegistry;
pub const MirAnnotator = @import("mir_annotator.zig").MirAnnotator;
pub const MirLowerer = @import("mir_lowerer.zig").MirLowerer;
```

This is explicit re-export, not `usingnamespace`. Explicit re-exports are preferable because:
1. The set of exported symbols is clear and auditable
2. No accidental re-export of internal types
3. Consistent with how `lsp.zig` imports from `lsp_types.zig` (pull in what you need by name)

### Pattern: Per-File Imports (each split file)

Each `mir_*.zig` file imports only what it needs:

```zig
// mir_annotator.zig — MIR annotator pass
const std = @import("std");
const parser = @import("parser.zig");
const declarations = @import("declarations.zig");
const errors = @import("errors.zig");
const types = @import("types.zig");
const K = @import("constants.zig");
const builtins = @import("builtins.zig");
const mir_types = @import("mir_types.zig");

const RT = mir_types.RT;
const TypeClass = mir_types.TypeClass;
const Coercion = mir_types.Coercion;
const NodeInfo = mir_types.NodeInfo;
const NodeMap = mir_types.NodeMap;
const classifyType = mir_types.classifyType;
```

```zig
// mir_lowerer.zig — MIR lowerer pass
const std = @import("std");
const parser = @import("parser.zig");
const declarations = @import("declarations.zig");
const mir_types = @import("mir_types.zig");
const mir_node = @import("mir_node.zig");
const mir_registry = @import("mir_registry.zig");

const RT = mir_types.RT;
const NodeInfo = mir_types.NodeInfo;
const NodeMap = mir_types.NodeMap;
const classifyType = mir_types.classifyType;
const MirNode = mir_node.MirNode;
const MirKind = mir_node.MirKind;
const IfNarrowing = mir_node.IfNarrowing;
const UnionRegistry = mir_registry.UnionRegistry;
```

### Pattern: build.zig Test Registration

Every new `mir_*.zig` file must be added to the `test_files` array in `build.zig`. This is mandatory for `zig build test` to pick up the tests.

Current entry: `"src/mir.zig"` — must be replaced with all 6 new files:

```zig
"src/mir.zig",
"src/mir_types.zig",
"src/mir_registry.zig",
"src/mir_node.zig",
"src/mir_annotator.zig",
"src/mir_lowerer.zig",
```

**Keeping `mir.zig` in the list is correct** — the re-export facade has no tests itself, but it still needs to compile. However, since the facade only contains `pub const` re-exports, there will be no test blocks in it after the split.

### Anti-Patterns to Avoid

- **Helper files importing each other:** `mir_annotator.zig` must NOT import `mir_lowerer.zig` and vice versa. All cross-file dependencies route through `mir_types.zig`, `mir_node.zig`, or `mir_registry.zig`. If a function is needed in multiple places, move it to the types module.
- **Leaving CoercionResult private to mir.zig:** `CoercionResult` is used inside `detectCoercion` and the callers of that function in `MirAnnotator`. It must travel with the annotator to `mir_annotator.zig`.
- **Making `populateData` and `astToMirKind` public unnecessarily:** These two file-scope functions are only called by `MirLowerer.lowerNode()`. They move to `mir_lowerer.zig` as private (no `pub`). D-05 says MirNode "gets its own file with populateData and astToMirKind" — but these functions are not methods on MirNode, they take `*MirNode` as a parameter. Because they need `parser.Node` types heavily, keeping them in `mir_lowerer.zig` (where `lowerNode` calls them) is simpler than `mir_node.zig`. The planner should verify actual call sites.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Cross-file symbol visibility in Zig | Complex re-export macros or usingnamespace chains | Explicit `pub const X = @import("f.zig").X;` — simple and auditable |
| Test discovery across files | Manual test runner | `build.zig` `test_files` array — Zig finds all `test` blocks automatically |
| Checking no behavior regression | Manual diff of codegen output | `./testall.sh` — 266 tests, already covers this |

## Common Pitfalls

### Pitfall 1: Private Struct Methods Called From Outside Their File
**What goes wrong:** Moving `MirAnnotator` to `mir_annotator.zig` while leaving a caller of its private method in `mir.zig` (or vice versa). Zig will refuse to compile — private methods are not accessible outside their file.
**Why it happens:** Phase 29 encountered this with CodeGen helper files calling `cg.method()` — required making all called methods `pub`.
**How to avoid:** Since D-01 keeps each struct entirely within its file (not split across files like codegen was), this is NOT a problem for this refactor. Each struct's private methods stay private inside their new file.
**Warning signs:** Compile error "member function 'X' is not accessible".

### Pitfall 2: CoercionResult Lost in Translation
**What goes wrong:** `detectCoercion` returns `CoercionResult`, a file-scoped struct in the current mir.zig. If it's not moved with `MirAnnotator`, compilation fails.
**Why it happens:** Forgetting to audit file-scoped (non-pub) types that are used internally.
**How to avoid:** Before moving `MirAnnotator`, inventory all non-pub types in mir.zig that are used exclusively by annotator code. Move them to `mir_annotator.zig` as private types.
**Warning signs:** "use of undeclared identifier 'CoercionResult'" when compiling `mir_annotator.zig`.

### Pitfall 3: Forgetting build.zig test_files Registration
**What goes wrong:** New `mir_*.zig` files compile fine as part of the main executable but their `test` blocks never run because `zig build test` only runs tests for explicitly listed files.
**Why it happens:** The test runner in build.zig uses an explicit array, not auto-discovery.
**How to avoid:** After creating each new file, immediately add it to the `test_files` array in `build.zig`.
**Warning signs:** Tests pass but test count is unchanged from before the split — tests that moved to new files are silently not running.

### Pitfall 4: mir_lowerer.zig Importing mir_annotator.zig (Circular Dependency)
**What goes wrong:** MirLowerer uses `NodeInfo` and `NodeMap` from the types module, and `MirNode` from the node module. If `populateData` is placed in `mir_node.zig` and it needs `classifyType`, it's fine — `classifyType` is in `mir_types.zig`. But if `mir_node.zig` somehow imports `mir_lowerer.zig` or `mir_annotator.zig`, Zig will detect the cycle and refuse to compile.
**Why it happens:** Wanting to group all MirNode-related code in `mir_node.zig` including functions that actually depend on lowering context.
**How to avoid:** `mir_node.zig` imports only `parser.zig` and `mir_types.zig`. Functions that need lowering context stay in `mir_lowerer.zig`.
**Warning signs:** Zig compile error "dependency loop detected".

### Pitfall 5: Test Imports Are Implicit in Zig
**What goes wrong:** A test block in `mir_annotator.zig` references `declarations.DeclTable` but the test passes by accident in the old mir.zig because all imports were at file scope. After moving, the test file needs its own imports.
**Why it happens:** Test blocks inherit file-scope imports. When code moves, the test needs the same imports in the new file.
**How to avoid:** Each `mir_*.zig` file must import everything its test blocks use. The imports at the top of the new file cover both production code and tests.
**Warning signs:** "use of undeclared identifier" errors only when running `zig build test`, not `zig build`.

### Pitfall 6: The test/08_codegen.sh File Reference Check (from Phase 29 lessons)
**What goes wrong:** Shell tests in `test/08_codegen.sh` or `test/01_unit.sh` reference the string `"src/mir.zig"` in content checks (e.g., checking that a pattern appears in a specific file). After the split, that pattern now lives in `mir_annotator.zig`.
**Why it happens:** Phase 29 hit exactly this — test checked `codegen.zig` for a pattern that moved to `codegen_exprs.zig`.
**How to avoid:** After moving code, search test scripts for references to `"mir.zig"` and update any that check file content rather than just behavior.
**Warning signs:** test/01_unit.sh fails with a file-content check error after the split.

## Code Examples

### Re-export Facade (mir.zig after split)

```zig
// Source: Phase 29/32 pattern, adapted for MIR
// mir.zig — MIR (Mid-level Intermediate Representation) pass (pass 10)
// Re-export hub — all implementations live in mir_*.zig files.

pub const TypeClass = @import("mir_types.zig").TypeClass;
pub const Coercion = @import("mir_types.zig").Coercion;
pub const NodeInfo = @import("mir_types.zig").NodeInfo;
pub const NodeMap = @import("mir_types.zig").NodeMap;
pub const classifyType = @import("mir_types.zig").classifyType;
pub const MirKind = @import("mir_node.zig").MirKind;
pub const LiteralKind = @import("mir_node.zig").LiteralKind;
pub const IfNarrowing = @import("mir_node.zig").IfNarrowing;
pub const MirNode = @import("mir_node.zig").MirNode;
pub const UnionRegistry = @import("mir_registry.zig").UnionRegistry;
pub const MirAnnotator = @import("mir_annotator.zig").MirAnnotator;
pub const MirLowerer = @import("mir_lowerer.zig").MirLowerer;
```

### Dependency Graph Between Split Files

```
mir_types.zig      ← imports: std, parser, types
mir_registry.zig   ← imports: std, mir_types
mir_node.zig       ← imports: std, parser, mir_types
mir_annotator.zig  ← imports: std, parser, declarations, errors, types, K, builtins, mir_types, mir_registry
mir_lowerer.zig    ← imports: std, parser, declarations, mir_types, mir_node, mir_registry
mir.zig            ← imports: mir_types, mir_node, mir_registry, mir_annotator, mir_lowerer (re-exports only)
```

No cycles. Clean DAG.

### Test Block Distribution

| Test Name | Home File |
|-----------|-----------|
| `classifyType - primitives` | `mir_types.zig` |
| `classifyType - unions` | `mir_types.zig` |
| `classifyType - pointers and named` | `mir_types.zig` |
| `union registry - canonicalize` | `mir_registry.zig` |
| `union registry - different unions` | `mir_registry.zig` |
| `mir annotator - basic` | `mir_annotator.zig` |
| `var_types - populated from var_decl` | `mir_annotator.zig` |
| `detectCoercion - *` (5 tests) | `mir_annotator.zig` |
| `resolveCallSig - cross-module lookup` | `mir_annotator.zig` |
| `const auto-borrow - *` (6 tests) | `mir_annotator.zig` |

Total: 3 tests → `mir_types.zig`, 2 tests → `mir_registry.zig`, 15 tests → `mir_annotator.zig`, 0 tests → `mir_node.zig`, 0 tests → `mir_lowerer.zig`.

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| Monolithic mir.zig (2356 lines) | 6 focused files (~50-700 lines each) | Matches codegen_*.zig and lsp_*.zig split pattern |
| All types co-located with implementation | Shared `mir_types.zig` for pure type definitions | Single import source for downstream consumers |

## Open Questions

1. **Where do `populateData` and `astToMirKind` live?**
   - What we know: D-05 says "MirNode gets its own file with `populateData()` and `astToMirKind()`". These are currently file-scope functions (not struct methods) in mir.zig.
   - What's unclear: `populateData(m: *MirNode, node: *parser.Node)` takes a `*MirNode` and a `*parser.Node`. It only reads from `parser.Node` and writes to `MirNode` fields. It does NOT need `classifyType` or any allocator. `astToMirKind(node: *parser.Node)` only reads `parser.Node` and returns `MirKind`. Both are lightweight and only called by `MirLowerer.lowerNode()`.
   - Recommendation: Both belong in `mir_lowerer.zig` as private helpers (they are only called from `lowerNode`). D-05's intent is that MirNode structure is self-contained — the accessor methods (`body()`, `condition()`, etc.) unambiguously belong in `mir_node.zig`. `populateData` and `astToMirKind` are lowering logic, not node behavior. Planner should decide based on this analysis.

2. **Does `mir.zig` need a `test` block after the split?**
   - What we know: `build.zig` runs tests per file. After the split, `mir.zig` will only contain `pub const` re-exports — no functions to test.
   - Recommendation: No test blocks in `mir.zig` after the split. The file stays in `build.zig`'s `test_files` because it must compile, but the Zig test runner will find zero test blocks in it, which is fine.

## Environment Availability

Step 2.6: SKIPPED — this phase is a pure code reorganization with no external tool dependencies. The existing Zig toolchain (`zig build`, `zig build test`, `./testall.sh`) is already verified to be working (266 tests pass on main).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Zig built-in `test` blocks + shell integration tests |
| Config file | `build.zig` — `test_files` array at line 43 |
| Quick run command | `zig build test` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPLIT-03 | mir.zig split into 6+ files | unit | `zig build test` | ✅ existing tests move to new files |
| SPLIT-02 | Zero behavior change — all tests pass | integration | `./testall.sh` | ✅ 266 tests already exist |

### Sampling Rate

- **Per task commit:** `zig build test`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all phase requirements. No new test files need to be created. Tests move from `mir.zig` to their respective new files during the split itself.

## Sources

### Primary (HIGH confidence)

- Direct code inspection of `src/mir.zig` (2356 lines, read in full)
- `.planning/phases/29-codegen-split/29-01-SUMMARY.md` — wrapper stub pattern, lessons learned, deviations
- `.planning/phases/32-lsp-split/32-CONTEXT.md` — latest split decisions and patterns
- `src/lsp.zig` + `src/lsp_types.zig` — explicit re-export pattern verified
- `build.zig` — test_files array structure verified
- `.planning/codebase/CONVENTIONS.md` — naming and structure conventions verified

### Secondary (MEDIUM confidence)

- Call graph analysis via `grep` — all consumers of `mir.zig` identified (`main.zig`, `codegen.zig`, `codegen_*.zig`)

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — Zig stdlib only, no new dependencies
- Architecture: HIGH — pattern directly proven in Phases 29 and 32 on this codebase
- Pitfalls: HIGH — derived from actual deviations logged in Phase 29 SUMMARY plus direct code inspection

**Research date:** 2026-03-29
**Valid until:** Stable — pure internal refactor, no external dependencies
