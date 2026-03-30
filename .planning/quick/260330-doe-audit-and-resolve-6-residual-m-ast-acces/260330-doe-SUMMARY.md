---
phase: quick-260330-doe
plan: 01
subsystem: codegen
tags: [mir, codegen, refactor, docs]
dependency_graph:
  requires: []
  provides: [nodeLocMir, current_func_mir-only MIR path]
  affects: [src/codegen/codegen.zig, src/codegen/codegen_decls.zig, src/codegen/codegen_stmts.zig, src/codegen/codegen_exprs.zig, src/codegen/codegen_match.zig, src/mir/mir_node.zig, docs/TODO.md]
tech_stack:
  added: []
  patterns: [nodeLocMir convenience wrapper, current_func_mir-only MIR return type tracking]
key_files:
  created: []
  modified:
    - src/codegen/codegen.zig
    - src/codegen/codegen_decls.zig
    - src/codegen/codegen_stmts.zig
    - src/codegen/codegen_exprs.zig
    - src/codegen/codegen_match.zig
    - src/mir/mir_node.zig
    - docs/TODO.md
decisions:
  - "6 structural .ast accesses retained as permanent boundary — typeToZig/generateExpr walk recursive AST type trees; duplicating into MirNode adds complexity for zero benefit"
  - "current_func_node kept as AST-path-only field for legacy generateFunc path"
metrics:
  duration: ~10 minutes
  completed: 2026-03-30
  tasks_completed: 2
  files_modified: 7
---

# Phase quick-260330-doe Plan 01: MIR Residual AST Access Audit Summary

**One-liner:** Migrated 4 m.ast accesses to MIR (nodeLoc + current_func_node) and documented 6 structural type-tree accesses as a permanent architectural boundary.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Migrate current_func_node to current_func_mir and add nodeLocMir | b68c917 | codegen.zig, codegen_decls.zig, codegen_exprs.zig, codegen_stmts.zig |
| 2 | Document architectural boundary and update TODO.md | 6ee93b2 | mir_node.zig, codegen_exprs.zig, codegen_stmts.zig, codegen_decls.zig, codegen_match.zig, docs/TODO.md |

## What Was Done

### Task 1 — MIR path migration

Added `nodeLocMir(*MirNode)` convenience method to `CodeGen` that calls `nodeLoc(m.ast)` internally. Replaced the two `cg.nodeLoc(m.ast)` call sites in codegen_stmts.zig and codegen_exprs.zig with `cg.nodeLocMir(m)`.

Migrated `generateFuncMir` and `generateThreadFuncMir` in codegen_decls.zig to set `current_func_mir = m` instead of `current_func_node = m.ast`. Removed the `current_func_node` fallback branches from `funcReturnTypeClass()` and `funcReturnMembers()` — these methods now only read from `current_func_mir`. Documented `current_func_node` as AST-path-only in the field comment.

### Task 2 — Architectural boundary documentation

Updated `MirNode.ast` doc comment with precise two-category boundary description. Added inline comments at all 6 remaining `.ast` access sites:
- `codegen_stmts.zig:61` and `codegen_decls.zig:816` — type alias value (`typeToZig` walks AST type tree)
- `codegen_exprs.zig:618-619` — type_expr and passthrough MirKinds (already had good comments)
- `codegen_match.zig:583,585` — cast() target type (`typeToZig` + `isEnumTypeName`)

Marked the TODO.md entry as RESOLVED (v0.10.25) with a full migration summary. Updated the Done section to replace the "6 residual accesses remain" note with the final resolution.

## Verification

- `grep -c '.ast' src/codegen/codegen_decls.zig src/codegen/codegen_stmts.zig src/codegen/codegen_exprs.zig src/codegen/codegen_match.zig` → 1 + 1 + 2 + 2 = 6 (all structural boundary)
- `grep 'current_func_node' src/codegen/*.zig` → only AST-path uses in generateFunc/generateThreadFunc + field declaration
- `grep 'nodeLocMir' src/codegen/*.zig` → 2 call sites + 1 method definition
- All 269 tests pass

## Decisions Made

- The 6 structural `.ast` accesses (typeToZig + type_expr/passthrough generateExpr) are a **permanent architectural boundary**. Duplicating the recursive AST type tree (`type_named`, `type_slice`, `type_array`, `type_union`, `type_ptr`, etc.) into MirNode would add significant complexity for zero runtime or correctness benefit — these are syntax-to-syntax translations.
- `current_func_node` retained as AST-path-only field rather than removed, because `generateFunc` and `generateThreadFunc` (AST-path functions) still use it. These functions are defined but not currently called from the pipeline, so they could be removed in a future cleanup task.

## Deviations from Plan

None — plan executed exactly as written. The plan's contingency about checking whether `generateFunc`/`generateTestDef` were live code was resolved correctly: `generateFunc` is defined but never called outside its own module (confirmed via grep), so `current_func_node` was kept as AST-path-only rather than removed.

## Self-Check: PASSED

- src/codegen/codegen.zig: FOUND
- src/mir/mir_node.zig: FOUND
- commit b68c917: FOUND
- commit 6ee93b2: FOUND
