---
phase: 18-type-alias-syntax
plan: 01
subsystem: declarations, codegen, resolver
tags: [type-alias, const-decl, codegen, declarations]
dependency_graph:
  requires: []
  provides: [type-alias-declarations, type-alias-codegen]
  affects: [declarations.zig, codegen.zig, resolver.zig]
tech_stack:
  added: []
  patterns: [isTypeAlias helper, DeclTable.types routing, typeToZig expression dispatch]
key_files:
  created: []
  modified:
    - src/declarations.zig
    - src/codegen.zig
    - src/resolver.zig
    - src/templates/example/advanced.orh
    - test/09_language.sh
decisions:
  - "Reuse existing const_decl grammar — no new grammar rules; ': type' annotation signals type alias"
  - "Route type aliases into DeclTable.types (not DeclTable.vars) to skip ownership/type checking"
  - "Use RT.inferred in resolver when variable type is a known type alias name"
  - "Local aliases store as RT.primitive(.type) in scope (not RT.named('type'))"
  - "typeToZig handles call_expr as type_generic and binary_expr '|' as union patterns"
metrics:
  duration: "~2 hours"
  completed: "2026-03-26"
  tasks_completed: 2
  files_modified: 5
requirements_satisfied: [TAMGA-04]
---

# Phase 18 Plan 01: Type Alias Support Summary

Type alias declarations (`const Name: type = T`) that generate transparent Zig type aliases (`const Name = T`), with full support for primitives, generics, pointers, error/null unions, and local aliases inside function bodies.

## What Was Built

### declarations.zig

Added `isTypeAlias` helper that detects `: type` annotation by checking `type_named == "type"` (reuses existing `K.Type.TYPE` constant). Modified `collectVar()` to route type aliases into `DeclTable.types` (skipping the vars map entirely) so no ownership or type checking is applied to the alias itself.

### resolver.zig

Added `resolveTypeAnnotationInScope` that returns `RT.inferred` when a type annotation name resolves to a known type alias (found in `DeclTable.types` or as `RT.primitive(.@"type")` in local scope). This lets variables declared with aliased types (`const s: Speed = 42`) pass type checking — the return-type checker sees `RT.inferred` which is compatible with any expected return type.

Extended `validateType` to accept names found in `DeclTable.types` as valid known types, preventing spurious "unknown type 'Speed'" errors.

### codegen.zig

Added `isTypeAlias` helper (same logic as in declarations.zig). Modified `generateTopLevelDeclMir` and `generateStatementMir` to detect type aliases before the `is_compt` branch, emitting `const Name = ZigType;` or `pub const Name = ZigType;`.

Extended `typeToZig` with two new dispatch cases:
- `.call_expr`: reconstructs as `type_generic` node to handle `List(i32)`, `Ptr(u8)`, `Map(K,V)` in RHS position
- `.binary_expr`: detects `null | T` (→ `?T`) and `Error | T` (→ `anyerror!T`) patterns

### example module + test

Added Type Aliases section to `src/templates/example/advanced.orh` covering primitives, generic, null union, error union, and local aliases. Added `test "type alias"` block with two assertions. Added assertion in `test/09_language.sh` checking `const Speed = i32` appears in generated example.zig.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Return type mismatch for variables typed with module-level aliases**
- **Found during:** Task 1
- **Issue:** Variable `const s: Speed = 42` resolved to type `RT.named("Speed")`, incompatible with return type `i32`
- **Fix:** Added `resolveTypeAnnotationInScope` that returns `RT.inferred` for names in `DeclTable.types`
- **Files modified:** src/resolver.zig
- **Commit:** 4368dbb

**2. [Rule 1 - Bug] Return type mismatch for local type aliases**
- **Found during:** Task 1
- **Issue:** Local alias `const MyInt: type = i32` stores as `RT.primitive(.@"type")` in scope (not `RT.named("type")`), so the initial check `t == .named and t.named == "type"` missed it
- **Fix:** Changed check to `t == .primitive and t.primitive == .@"type"`
- **Files modified:** src/resolver.zig
- **Commit:** 4368dbb

**3. [Rule 1 - Bug] "unknown type 'Speed'" error in semantic validation**
- **Found during:** Task 1
- **Issue:** `validateType` did not check `DeclTable.types` so alias names were rejected as unknown types
- **Fix:** Added `self.decls.types.contains(type_name)` to the `is_known` predicate in `validateType`
- **Files modified:** src/resolver.zig
- **Commit:** 4368dbb

**4. [Rule 1 - Bug] Complex type alias RHS generated wrong Zig**
- **Found during:** Task 2 — `const Scores: type = List(i32)` generated `const Scores = i32` instead of the list type; `(null | i32)` generated `anyopaque`
- **Issue:** `List(i32)` in value/expression position parses as `call_expr` (not `type_generic`); `(null | i32)` parses as `binary_expr`. `typeToZig` had no handling for these cases.
- **Fix:** Added `.call_expr` and `.binary_expr` dispatch cases in `typeToZig`
- **Files modified:** src/codegen.zig
- **Commit:** e98f316

**5. [Rule 1 - Bug] Debug prints left in codegen after investigation**
- **Found during:** Cleanup
- **Issue:** `[CG DEBUG] std.debug.print` statements added during investigation remained in `generateTopLevelDeclMir`
- **Fix:** Removed all debug prints
- **Files modified:** src/codegen.zig
- **Commit:** e98f316

## Commits

| Hash | Message |
|------|---------|
| a1ca8f2 | feat(18-01): implement type alias detection and codegen |
| 4368dbb | feat(18-01): add example coverage, test assertions, and resolver support |
| e98f316 | fix(18-01): remove debug prints from type alias codegen path |

## Verification

All 248 tests pass (`./testall.sh`). Key assertions verified:
- `const Speed = i32` appears in generated example.zig
- `const Scores = OrhonList(i32)` (generic alias) works
- `const OptionalInt = ?i32` (null union alias) works
- `const Fallible = anyerror!i32` (error union alias) works
- Local `const MyInt: type = i32` inside function body works
- `pub const Distance: type = f64` generates `pub const Distance = f64`
- Existing const declarations are unaffected

## Self-Check: PASSED
