# Phase 17: `Unit` Type in Return Position

## Goal
`Unit` is recognized as a valid type, enabling `(Error | Unit)` for void-returning bridge functions.

## Source
Tamga `docs/bugs.txt` — OPEN: `Unit` type not recognized in bridge return position

## Problem
Compiler rejects `pub bridge func initPlatform() (Error | Unit)` with "unknown type 'Unit'". Cannot express error-or-nothing for void-returning bridge functions.

## Success Criteria
1. `Unit` is recognized as a builtin type mapping to Zig's `void`
2. `(Error | Unit)` compiles — codegen emits `anyerror!void`
3. Bridge functions returning `(Error | Unit)` work correctly
4. All 11 test stages pass

## Areas
- Type system (`src/types.zig`, `src/builtins.zig`)
- Type resolution (`src/resolver.zig`)
- Codegen (`src/codegen.zig`)
- Test fixtures
