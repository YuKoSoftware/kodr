---
phase: 33-mir-split
plan: "01"
subsystem: mir
tags: [refactor, split, mir, types, registry, node]
dependency_graph:
  requires: []
  provides: [mir_types.zig, mir_registry.zig, mir_node.zig]
  affects: [mir.zig, build.zig]
tech_stack:
  added: []
  patterns: [re-export pattern for backward compatibility, underscore-prefixed module imports to avoid shadowing]
key_files:
  created:
    - src/mir_types.zig
    - src/mir_registry.zig
    - src/mir_node.zig
  modified:
    - src/mir.zig
    - build.zig
decisions:
  - "Use underscore-prefixed import names (_mir_types, _mir_registry, _mir_node) to avoid shadowing conflicts with local variables named mir_node in MirLowerer"
  - "pub const re-exports at file scope in mir.zig for full backward compatibility with zero downstream changes"
  - "RT alias defined in mir_types.zig as pub const (not private) so mir_registry.zig and mir_node.zig can re-use it"
metrics:
  duration: "~10 minutes"
  completed: "2026-03-29"
  tasks_completed: 1
  files_modified: 5
---

# Phase 33 Plan 01: MIR Foundation Extraction Summary

Extract MIR foundation modules (types, registry, node) from the monolithic mir.zig into dedicated files.

## What Was Built

Three foundation modules extracted from mir.zig:

- **mir_types.zig** (98 lines): TypeClass enum, classifyType function, Coercion enum, NodeInfo struct, NodeMap type alias, RT alias. Includes 3 classifyType unit tests.
- **mir_registry.zig** (108 lines): UnionRegistry struct with init/deinit/canonicalize methods. Includes 2 union registry unit tests.
- **mir_node.zig** (236 lines): MirNode struct (with all child accessor methods), LiteralKind enum, MirKind enum, IfNarrowing struct. No tests (none existed for these types).

mir.zig reduced from 2356 to 1958 lines (~398 lines removed). All 9 extracted types are re-exported via pub const aliases for zero downstream impact.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extract mir_types.zig, mir_registry.zig, mir_node.zig and update mir.zig | f54e51b | src/mir_types.zig, src/mir_registry.zig, src/mir_node.zig, src/mir.zig, build.zig |

## Decisions Made

1. **Underscore-prefixed import names** — importing as `_mir_node` instead of `mir_node` avoids Zig shadowing errors where local variables named `mir_node` exist in MirLowerer methods.

2. **pub const re-exports in mir.zig** — all 9 moved types re-exported via `pub const TypeClass = _mir_types.TypeClass` etc., so codegen.zig, main.zig, and all other consumers importing `mir.zig` require zero changes.

3. **RT alias as pub const in mir_types.zig** — made public so mir_registry.zig and mir_node.zig can import it directly, avoiding duplicate `const RT = types.ResolvedType` declarations across files.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Underscore-prefix for module imports to avoid shadowing**
- **Found during:** Task 1 verification (zig build test)
- **Issue:** Using `const mir_node = @import("mir_node.zig")` caused Zig shadowing errors because MirLowerer has a local variable `var mir_node = try self.allocator.create(MirNode)` and a function parameter `mir_node: *MirNode`
- **Fix:** Renamed imports to `_mir_types`, `_mir_registry`, `_mir_node` with underscore prefix
- **Files modified:** src/mir.zig
- **Commit:** f54e51b (same commit — caught before final commit)

## Verification

- `zig build test` — all unit tests pass (5 tests in new files: 3 classifyType + 2 registry)
- `./testall.sh` — all 266 integration tests pass, zero behavior change
- No downstream consumers required changes (codegen.zig, main.zig still import mir.zig)

## Known Stubs

None.

## Self-Check: PASSED

- `src/mir_types.zig` exists and contains `pub const TypeClass = enum {` ✓
- `src/mir_registry.zig` exists and contains `pub const UnionRegistry = struct {` ✓
- `src/mir_node.zig` exists and contains `pub const MirNode = struct {` ✓
- `src/mir.zig` contains `pub const TypeClass = _mir_types.TypeClass;` ✓
- `build.zig` contains `"src/mir_types.zig"`, `"src/mir_registry.zig"`, `"src/mir_node.zig"` ✓
- Commit f54e51b exists ✓
