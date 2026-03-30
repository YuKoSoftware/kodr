---
phase: quick-260330-uvu
plan: 01
subsystem: compiler-pipeline
tags: [lexer, parser, peg, borrow, syntax]
dependency_graph:
  requires: []
  provides: [const_borrow_token, mut_borrow_token, mut_borrow_expr_node]
  affects: [lexer, parser, peg, resolver, ownership, borrow, thread_safety, mir, codegen, stdlib, docs]
tech_stack:
  added: []
  patterns: [compound-token-lexing, single-token-borrow-syntax]
key_files:
  created: []
  modified:
    - src/lexer.zig
    - src/parser.zig
    - src/peg/orhon.peg
    - src/peg/builder_exprs.zig
    - src/peg/builder_types.zig
    - src/peg/token_map.zig
    - src/peg.zig
    - src/resolver.zig
    - src/ownership.zig
    - src/borrow.zig
    - src/thread_safety.zig
    - src/mir/mir_annotator.zig
    - src/mir/mir_lowerer.zig
    - src/mir/mir_types.zig
    - src/codegen/codegen_stmts.zig
    - src/codegen/codegen_match.zig
    - src/module.zig
    - src/std/linear.orh
    - src/std/tui.orh
    - src/std/stream.orh
    - src/std/net.orh
    - src/std/allocator.orh
    - src/templates/example/example.orh
    - src/templates/example/advanced.orh
    - src/templates/example/data_types.orh
    - test/fixtures/tester.orh
    - test/fixtures/tester_main.orh
    - test/fixtures/fail_borrow.orh
    - test/fixtures/fail_threads.orh
    - test/fixtures/fail_ptr_cast.orh
    - test/snapshots/snap_structs.orh
    - test/11_errors.sh
    - docs/09-memory.md
    - docs/10-structs-enums.md
    - docs/12-concurrency.md
    - docs/14-zig-bridge.md
    - docs/COMPILER.md
    - docs/TODO.md
decisions:
  - "Tasks 1+2 committed together since AST rename (borrow_expr -> mut_borrow_expr) makes Task 1 incompilable alone"
  - "mut alone stays an identifier (not a keyword) -- only mut& is a compound token"
  - "Internal type representation strings (constants.zig CONST_REF/VAR_REF) unchanged -- only surface syntax changed"
metrics:
  duration: 1211s
  completed: "2026-03-30T19:39:34Z"
---

# Quick Task 260330-uvu: Compound Borrow Tokens Summary

const& and mut& compound borrow tokens across 12 compiler passes, 38 files, with full .orh migration and docs update.

## What Changed

### Lexer (src/lexer.zig)
- Added `const_borrow` and `mut_borrow` to `TokenKind` enum
- `lexIdentOrKeyword()` lookahead: when `const` or `mut` is immediately followed by `&` (no whitespace), consume `&` and return compound token
- `mut` alone returns as `.identifier` (not a keyword)
- 4 new unit tests: const& compound, mut& compound, const-space-& not compound, bare & bitwise AND

### PEG Grammar (src/peg/orhon.peg)
- `unary_expr`: `'const' '&'` -> `'const&'`, `'&'` -> `'mut&'`
- `borrow_type`: `'const' '&' type` -> `'const&' type`
- `ref_type`: `'&' type` -> `'mut&' type`
- Bare `&` only remains in `bitand_expr` for bitwise AND

### AST Rename
- `borrow_expr` -> `mut_borrow_expr` in `parser.zig` NodeKind and Node union
- Same rename propagated to all 12 passes: resolver, ownership, borrow, thread_safety, mir_annotator, mir_lowerer, codegen_stmts, codegen_match

### Error Messages
- borrow.zig: "consider borrowing with const&" (was "const &")
- resolver.zig: "mutable reference 'mut& {s}' not allowed across bridge -- use 'const& {s}' or pass by value"
- module.zig: "var &T is not valid -- use mut& T for mutable references"

### .orh File Migration (13 files)
All borrow syntax updated:
- `const &T` -> `const& T` (type position)
- `&T` -> `mut& T` (type position)
- `const &x` -> `const& x` (expression position)
- `&x` -> `mut& x` (expression position, borrow contexts only)
- Bitwise AND (`a & b`) unchanged

### Documentation (6 files)
All docs updated to reflect new syntax: memory model, structs/enums, concurrency, bridge, compiler architecture, TODO.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Tasks 1+2 committed together**
- **Found during:** Task 1 verification
- **Issue:** The AST rename (borrow_expr -> mut_borrow_expr) in parser.zig makes all downstream files fail to compile until they're also updated. Pre-commit hook runs `zig build test`.
- **Fix:** Combined Tasks 1+2 into a single commit, proceeded to Task 3 before committing.

**2. [Rule 1 - Bug] const_borrow_expr corrupted by replace_all**
- **Found during:** Task 1
- **Issue:** Using replace_all on `borrow_expr` -> `mut_borrow_expr` also changed `const_borrow_expr` to `const_mut_borrow_expr`
- **Fix:** Immediately reversed with another replace_all: `const_mut_borrow_expr` -> `const_borrow_expr`

**3. [Rule 2 - Missing] Additional files not in plan**
- **Found during:** Task 3
- **Issue:** Several files not listed in the plan also contained old borrow syntax: `src/peg.zig` (inline test), `test/snapshots/snap_structs.orh`, `test/fixtures/fail_ptr_cast.orh`, `test/11_errors.sh` (inline .orh in bridge test), `src/module.zig` (error message)
- **Fix:** Updated all of them. The `11_errors.sh` bridge test used `data: &i32` which no longer parses; changed to `data: mut& i32`.

## Known Stubs

None.

## Test Results

All 277 tests pass across 11 stages.

## Self-Check: PASSED

- Commit 2ff3a31: FOUND
- All key files: FOUND
- All 277 tests: PASSED
