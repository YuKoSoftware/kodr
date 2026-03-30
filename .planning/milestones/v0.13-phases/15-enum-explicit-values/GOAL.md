# Phase 15: Enum Variants with Explicit Integer Values

## Goal
Typed enums support explicit integer value assignments per variant (e.g., `A = 4`).

## Source
Tamga `docs/bugs.txt` — OPEN: Enum variants with explicit integer values not supported

## Problem
Compiler rejects `A = 4` inside `pub enum(u32) Scancode { ... }` with "unexpected '='". Explicit per-variant integer assignments are not supported.

## Success Criteria
1. `pub enum(u32) Foo { A = 1, B = 5, C = 10 }` parses and compiles
2. Codegen emits `A = 1, B = 5, C = 10` in the Zig enum
3. Existing sequential enums still work unchanged
4. Example module updated with explicit enum value syntax
5. All 11 test stages pass

## Areas
- Parser (`src/orhon.peg`, `src/peg/builder.zig`)
- Codegen (`src/codegen.zig`)
- Test fixtures
