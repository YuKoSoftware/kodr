---
phase: 21-flexible-allocators
plan: 01
subsystem: collections, codegen, stdlib, build-system, type-system
tags: [allocators, collections, codegen, smp, bridge-modules]
dependency_graph:
  requires: []
  provides: [flexible-allocator-collections, smp-default, scoped-type-syntax]
  affects: [src/std/collections.zig, src/codegen.zig, src/std/allocator.orh, src/peg/builder.zig, src/resolver.zig, src/zig_runner.zig]
tech_stack:
  added: []
  patterns: [scoped-type-in-type-annotation, bridge-module-transitive-import]
key_files:
  created: []
  modified:
    - src/std/collections.zig
    - src/codegen.zig
    - src/std/allocator.orh
    - src/peg/builder.zig
    - src/resolver.zig
    - src/zig_runner.zig
    - test/fixtures/tester.orh
    - test/fixtures/tester_main.orh
    - test/10_runtime.sh
decisions:
  - Qualified type syntax (module.Type) is validated at the module level, not by looking up cross-module declarations — resolver skips validation for dotted names
  - Bridge modules not directly imported by root get mod_{name} created and wired to all shared modules and the root to support transitive bridge imports
  - scoped_type and scoped_generic_type PEG rules now have dedicated builders producing type_named("module.Type") — simple, correct, and codegen-transparent
metrics:
  duration: 30min
  completed_date: "2026-03-26"
  tasks_completed: 2
  files_modified: 9
---

# Phase 21 Plan 01: Flexible Allocators Summary

SMP singleton default in collections.zig, 1-arg .new(alloc) codegen path for collection types, smp_allocator for string interpolation, allocator.orh .allocator() bridge declarations, and runtime tests for all three allocator modes — plus three compiler fixes needed to make it work.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | SMP default + codegen .new(alloc) + allocator.orh bridge methods | 7852505 | collections.zig, codegen.zig, allocator.orh |
| 2 | Runtime tests + build/type system fixes | 5f0636f | tester.orh, tester_main.orh, 10_runtime.sh, builder.zig, resolver.zig, zig_runner.zig |

## What Was Built

**Task 1:**
- `collections.zig`: replaced `const default_alloc = std.heap.page_allocator` with `var _default_smp: std.heap.GeneralPurposeAllocator(.{}) = .{}` — all collection struct fields now default to `_default_smp.allocator()`
- `collections.zig`: removed redundant `new()` methods from List, Map, Set (codegen emits `.{}` directly)
- `codegen.zig` AST path: `.new()` with 1 arg on a type node emits `.{ .alloc = expr }` instead of falling through to a method call
- `codegen.zig` MIR path: same 1-arg handling for MIR `.type_expr`/`.collection` obj
- `codegen.zig`: replaced all 5 `page_allocator` references in string interpolation paths with `smp_allocator` (AST: lines ~2788, ~2840; MIR: lines ~3211, ~3278, ~3326; injected_defer: ~1566)
- `allocator.orh`: added `bridge func allocator(self: &SMP) void`, `bridge func allocator(self: &Arena) void`, `bridge func allocator(self: &Page) void`

**Task 2:**
- `tester.orh`: added `import std::allocator` at module scope, added `test_alloc_arena()` and `test_alloc_external()` functions
- `tester_main.orh`: added PASS/FAIL assertions for `alloc_arena` (expects 30) and `alloc_external` (expects 12)
- `test/10_runtime.sh`: added `alloc_arena alloc_external` to assertion list

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] scoped_type PEG rule had no builder**
- **Found during:** Task 2 — `var arena: allocator.Arena = ...` generated `var arena: allocator = ...`
- **Issue:** The `scoped_type <- IDENTIFIER '.' IDENTIFIER` and `scoped_generic_type` grammar rules existed in `orhon.peg` but had no dedicated builders in `builder.zig`. They fell through to the transparent rule, which took only the first IDENTIFIER token.
- **Fix:** Added `buildScopedType` and `buildScopedGenericType` in `src/peg/builder.zig`. Both produce `type_named("module.Type")` by concatenating the two IDENTIFIER tokens with a `.`.
- **Files modified:** `src/peg/builder.zig`
- **Commit:** 5f0636f

**2. [Rule 2 - Missing critical functionality] Qualified type names rejected by resolver**
- **Found during:** Task 2 — after fixing the builder, the resolver reported `unknown type 'allocator.Arena'`
- **Issue:** The type validator in `resolver.zig` checked local declarations only. Module-qualified type names like `allocator.Arena` are not declared locally but are valid references to imported bridge types.
- **Fix:** Added `const is_qualified = std.mem.indexOfScalar(u8, type_name, '.') != null` check — dotted names bypass the unknown-type error since module-level import validation is already handled by the module resolver.
- **Files modified:** `src/resolver.zig`
- **Commit:** 5f0636f

**3. [Rule 1 - Bug] Bridge modules not available to shared modules as named imports**
- **Found during:** Task 2 — `tester.zig` had `@import("allocator")` but Zig reported "no module named 'allocator' available within module 'tester'"
- **Issue:** In `buildZigContent`, bridge modules (e.g. `allocator`) that are not directly imported by the root module are never registered as named Zig modules (`mod_allocator`). Only the `bridge_allocator` (the raw `.zig` sidecar) was registered. Shared modules like `tester` that transitively import `allocator` needed `mod_allocator` wired in.
- **Fix:** In `zig_runner.zig`, for bridge modules not already in `shared_modules`, create `mod_{name}` and wire it into: all shared modules, the root exe, the static/dynamic lib targets, and the test target.
- **Files modified:** `src/zig_runner.zig`
- **Commit:** 5f0636f

## Known Stubs

None. All three allocator modes produce correct runtime output (alloc_default=300, alloc_arena=30, alloc_external=12).

## Self-Check: PASSED

- commits 7852505 and 5f0636f exist in git log
- all key files exist: collections.zig, allocator.orh, builder.zig, resolver.zig, zig_runner.zig, SUMMARY.md
- all 253 tests pass (5 new tests added vs 248 baseline)
