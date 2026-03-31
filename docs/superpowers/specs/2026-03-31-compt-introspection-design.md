# Compt Struct Introspection — Design Spec

**Date:** 2026-03-31
**Status:** Approved
**Prerequisite for:** [[TODO#Blueprints (abstract structs — Orhon's traits)]]

## Summary

Add 4 compile-time struct introspection compiler functions: `@hasField`, `@hasDecl`,
`@fieldType`, `@fieldNames`. These map to Zig builtins/stdlib and enable structural
queries needed for blueprint auto-derive, serialization, and conditional codegen.

## Functions

| Function | Arguments | Returns | Zig Emission |
|---|---|---|---|
| `@hasField(T, "name")` | type or value, string literal | `bool` | `@hasField(T, "name")` |
| `@hasDecl(T, "name")` | type or value, string literal | `bool` | `@hasDecl(T, "name")` |
| `@fieldType(T, "name")` | type or value, string literal | `type` | `@FieldType(T, "name")` |
| `@fieldNames(T)` | type or value | comptime string slice | `std.meta.fieldNames(T)` |

## Design Decisions

### Approach: Orhon-level validation + Zig codegen (Approach 2)

Validate arguments in the Orhon resolver so users get Orhon-quality error messages
for misuse. Emit Zig builtins directly — no Orhon-level evaluation. Zig handles all
comptime evaluation.

Rejected alternatives:
- **Pure pass-through (Approach 1):** No Orhon-level errors, poor DX.
- **Full Orhon evaluation (Approach 3):** Duplicates Zig comptime, breaks for bridge types.

### First argument: type or value

All 4 functions accept either a type (`Point`) or a value (`myPoint`). When a value
is passed, codegen wraps it in `@TypeOf(...)`. The resolver already knows whether an
expression resolves to `type`.

### Context: anywhere, not just compt

These functions work anywhere in code, not just inside `compt` blocks. They are
inherently compile-time (Zig guarantees it). `@size` and `@align` already follow
this pattern. No enforcement of compt-only context needed.

### @hasDecl scope: all declarations

`@hasDecl` checks for any declaration — methods, compt functions, constants, nested
types. Matches Zig's `@hasDecl` semantics with no artificial restriction.

### @fieldNames return type: Zig comptime slice

`@fieldNames(T)` emits `std.meta.fieldNames(T)` which returns
`[]const [:0]const u8` — a comptime string slice. This is not a runtime Orhon type.
It works directly in compt for-loops (the primary use case for auto-derive).
No runtime materialization — keeps it zero-cost.

## Orhon-Level Validation (Resolver)

| Function | Arg count | Second arg constraint | Error message |
|---|---|---|---|
| `@hasField` | exactly 2 | string literal | `"@hasField requires a string literal as second argument"` |
| `@hasDecl` | exactly 2 | string literal | `"@hasDecl requires a string literal as second argument"` |
| `@fieldType` | exactly 2 | string literal | `"@fieldType requires a string literal as second argument"` |
| `@fieldNames` | exactly 1 | — | `"@fieldNames takes exactly 1 argument"` |

Arg count errors: `"@hasField takes exactly 2 arguments"` (etc.)

## Codegen

In `generateCompilerFuncMir()` for each function:

1. Determine if first arg is a type expression — if yes, emit directly; if not, wrap
   in `@TypeOf(...)`
2. Emit the corresponding Zig builtin/stdlib call
3. Pass remaining args through (string literals emitted as-is)

### Type vs value detection

Codegen checks if the first argument's MIR annotation has `TypeClass.type_class` or
if the AST node is a `type_expr`. If neither, wrap in `@TypeOf(...)`.

## Files Changed

1. **`src/builtins.zig`** — add `"hasField"`, `"hasDecl"`, `"fieldType"`, `"fieldNames"` to `COMPILER_FUNCS`
2. **`src/peg/orhon.peg`** — add 4 entries to `compiler_func_name` rule
3. **`src/resolver.zig`** — return types (`bool`, `bool`, `type`, comptime slice) + argument validation
4. **`src/codegen/codegen_match.zig`** — Zig emission with `@TypeOf` wrapping logic
5. **`docs/05-functions.md`** — document the 4 new functions
6. **`src/templates/example*.orh`** — add introspection examples to living language manual
7. **Tests** — unit tests in resolver + codegen, integration fixture in `test/fixtures/`

## Example Usage

```orhon
// Check if a struct has a field
compt func hasPosition(T: type) bool {
    return @hasField(T, "x")
}

// Works with values too — wraps in @TypeOf
var p: Point = Point(1.0, 2.0)
const has_x: bool = @hasField(p, "x")

// Iterate all field names (compt for-loop)
compt for(@fieldNames(Point)) |name| {
    // name is a comptime string — use for auto-derive
}

// Get a field's type
const XType: type = @fieldType(Point, "x")

// Check for a method or declaration
if (@hasDecl(Point, "deinit")) {
    // cleanup logic
}
```

## Relationship to Blueprints

These introspection functions are prerequisites for blueprint auto-derive. When a
struct conforms to a blueprint (`struct Point: Eq {}`), the compiler will use
`@fieldNames` + `@fieldType` + `@hasDecl` to auto-generate missing method
implementations. This spec covers only the introspection primitives — blueprint
implementation is a separate spec.
