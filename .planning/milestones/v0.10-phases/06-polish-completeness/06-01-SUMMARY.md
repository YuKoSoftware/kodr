---
phase: 06-polish-completeness
plan: 01
subsystem: codegen, build
tags: [version, hygiene, memory-safety, codegen, interpolation]
dependency_graph:
  requires: []
  provides: [HYGN-01, HYGN-02]
  affects: [src/codegen.zig, build.zig, build.zig.zon, .planning/PROJECT.md]
tech_stack:
  added: []
  patterns: [pre-statement hoisting buffer, output buffer swap for expression codegen]
key_files:
  created: []
  modified:
    - build.zig
    - build.zig.zon
    - .planning/PROJECT.md
    - src/codegen.zig
decisions:
  - "Version unified to v0.10.0 across build.zig, build.zig.zon, and PROJECT.md"
  - "Interpolation codegen uses pre-statement hoisting buffer (pre_stmts) to pair allocPrint with defer free — temp_var MIR lowerer path uses a separate inline variant to avoid double-hoisting"
metrics:
  duration: 15
  completed: "2026-03-25T07:53:21Z"
  tasks: 2
  files: 4
---

# Phase 06 Plan 01: Version Alignment + Interpolation Memory Leak Fix Summary

Version aligned to v0.10.0 across all three locations and string interpolation codegen fixed to hoist allocPrint into a temp variable with defer free, eliminating the memory leak in both AST and MIR non-hoisted paths.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Align version numbers to v0.10.0 (HYGN-01) | 1e9d2cf | build.zig, build.zig.zon, .planning/PROJECT.md |
| 2 | Fix string interpolation memory leak in both codegen paths (HYGN-02) | a35ddeb | src/codegen.zig |

## Decisions Made

1. **Version unified to v0.10.0**: All three files that reference the version (build.zig SemanticVersion struct, build.zig.zon package manifest, .planning/PROJECT.md) now agree on v0.10.0.

2. **Pre-statement hoisting buffer for interpolation**: Added `pre_stmts: std.ArrayListUnmanaged(u8)` and `interp_count: u32` fields to CodeGen. When `generateInterpolatedString` or `generateInterpolatedStringMir` is called from an expression context, the allocPrint + defer free are appended to `pre_stmts`. `flushPreStmts()` is called in `generateBlockMir` before each statement emission, ensuring the declarations appear on their own lines before the statement that references them.

3. **Separate inline variant for MIR temp_var path**: The existing MIR lowerer path (temp_var + injected_defer nodes) already handles hoisting correctly. To avoid double-hoisting, a separate `generateInterpolatedStringMirInline` function provides the original emit-to-output behavior for the temp_var statement handler.

4. **Output buffer swap pattern**: To emit expression arguments (which call recursive codegen functions) into the `pre_stmts` buffer, the implementation temporarily swaps `self.output` with `self.pre_stmts`, runs the expression codegen, then swaps back. This avoids threading an extra allocator/buffer parameter through the entire codegen chain.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Separate inline variant required for temp_var path**
- **Found during:** Task 2
- **Issue:** The plan described modifying `generateInterpolatedStringMir` to use hoisting, but this function is also called by the `temp_var` statement handler which already provides hoisting via the MIR lowerer. Calling the hoisting version from there would double-hoist (emit into pre_stmts instead of inline output).
- **Fix:** Added `generateInterpolatedStringMirInline` with the original inline emit behavior; updated the `temp_var` handler to use it. `generateInterpolatedStringMir` now has the new hoisting behavior for expression contexts only.
- **Files modified:** src/codegen.zig
- **Commit:** a35ddeb

## Verification Results

```
grep -c "0, .minor = 10, .patch = 0" build.zig   → 1 ✓
grep -c '"0.10.0"' build.zig.zon                  → 1 ✓
grep -c "v0.10.0" .planning/PROJECT.md             → 1 ✓
grep -c "page_allocator.free" src/codegen.zig      → 6 ✓ (≥3 required)
grep -c "interp_count" src/codegen.zig             → 5 ✓ (≥1 required)
zig build                                          → OK ✓
zig build test                                     → OK ✓
./testall.sh                                       → 231 passed, 7 failed (all pre-existing) ✓
```

## Known Stubs

None. The interpolation hoisting paths are dormant (PEG builder does not yet generate interpolation nodes), but the codegen is wired correctly for when they become active.

## Self-Check: PASSED

Files exist:
- build.zig: FOUND (minor = 10, patch = 0)
- build.zig.zon: FOUND (.version = "0.10.0")
- .planning/PROJECT.md: FOUND (v0.10.0)
- src/codegen.zig: FOUND (pre_stmts, interp_count, flushPreStmts, generateInterpolatedStringMirInline)

Commits exist:
- 1e9d2cf: chore(06-01): align all version numbers to v0.10.0
- a35ddeb: fix(06-01): fix string interpolation memory leak in codegen (HYGN-02)
