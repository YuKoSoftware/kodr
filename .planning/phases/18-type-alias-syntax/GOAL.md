# Phase 18: `pub type Alias = T` Type Alias Syntax

## Goal
Type alias declarations are supported, generating Zig `pub const Alias = Type`.

## Source
Tamga `docs/bugs.txt` — OPEN: `pub type Alias = T` type alias syntax not supported

## Problem
Compiler rejects `pub type WindowHandle = Ptr(u8)` with "unexpected 'type'" at parse time. The `type` keyword is not recognized as a declaration form.

## Success Criteria
1. `pub type Alias = SomeType` parses successfully
2. `type Alias = SomeType` (non-pub) also works
3. Codegen emits `pub const Alias = SomeType` in Zig
4. Aliases work with all type forms (primitives, generics, pointers, structs)
5. Example module updated with type alias syntax
6. All 11 test stages pass

## Areas
- Parser (`src/orhon.peg`, `src/peg/builder.zig`)
- AST (`src/parser.zig` — new node kind)
- Declarations (`src/declarations.zig`)
- Codegen (`src/codegen.zig`)
- Test fixtures
