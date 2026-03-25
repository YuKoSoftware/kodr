# Phase 16: `is` Operator with Module-Qualified Types

## Goal
The `is` operator works with cross-module types — both qualified (`mod.Type`) and unqualified (`Type`) forms.

## Source
Tamga `docs/bugs.txt` — OPEN: `is` operator rejects module-qualified type names

## Problem
Two related issues:
1. `if(ev is tamga_sdl3.QuitEvent)` — parser rejects the `.` (unexpected '.')
2. `if(ev is QuitEvent)` — parser accepts it, but codegen emits `QuitEvent` without module qualifier, causing "use of undeclared identifier" in Zig

## Success Criteria
1. `ev is module.Type` parses successfully (dotted type names on RHS of `is`)
2. Codegen emits module-qualified names (`module.Type`) in generated Zig
3. Unqualified cross-module types also emit correct Zig (with import qualifier)
4. Union-of-structs dispatch works across module boundaries
5. All 11 test stages pass

## Areas
- Parser (`src/orhon.peg`, `src/peg/builder.zig`)
- Codegen (`src/codegen.zig`)
- Type resolution (`src/resolver.zig`)
- Test fixtures
