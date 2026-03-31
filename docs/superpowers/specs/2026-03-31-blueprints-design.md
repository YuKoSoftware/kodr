# Blueprints — Design Spec

**Date:** 2026-03-31
**Version target:** v0.12.0
**Approach:** Purely semantic (Approach A) — blueprints are erased at codegen

## Summary

Blueprints are Orhon's trait/interface mechanism — strict, nominal contracts that structs must satisfy at compile time. A blueprint declares method signatures. A struct that conforms to a blueprint must implement every declared method with a matching signature. No auto-derive, no default implementations, no magic. Pure compile-time validation, zero runtime cost.

## Syntax

### Blueprint declaration

```
blueprint Eq {
    func eq(self: const& Eq, other: const& Eq) bool
}

pub blueprint Drawable {
    func draw(self: const& Drawable)
    func resize(self: mut& Drawable, width: f32, height: f32)
}
```

- `blueprint` is a new keyword
- Methods are signatures only — no bodies allowed
- All methods are implicitly `pub` (no `pub` keyword on them)
- Blueprint uses its own name in signatures (not `Self`)
- Visibility: private by default, `pub` to export — same rules as structs

### Struct conformance

```
struct Point: Eq {
    x: f32
    y: f32

    func eq(self: const& Point, other: const& Point) bool {
        return self.x == other.x and self.y == other.y
    }
}
```

- Colon syntax after struct name: `struct Name: Blueprint1, Blueprint2 { ... }`
- Struct must implement every method from every listed blueprint
- Struct uses its own name where the blueprint used the blueprint's name
- The blueprint dictates how `self` is passed (const& vs mut&) — the struct must match

### Multiple conformance

```
struct Circle: Eq, Drawable {
    radius: f32

    func eq(self: const& Circle, other: const& Circle) bool {
        return self.radius == other.radius
    }

    func draw(self: const& Circle) {
        // ...
    }

    func resize(self: mut& Circle, width: f32, height: f32) {
        self.radius = width / 2.0
    }
}
```

## Design Rules

- Blueprints contain only method signatures — no bodies, no fields, no default implementations
- No inheritance between blueprints — blueprints cannot extend other blueprints
- Structs can conform to blueprints — this is the only inheritance-like relationship
- One level only: blueprint → struct. No struct-extends-struct, no blueprint-extends-blueprint
- No generic blueprints in v1 (deferred — needs type substitution in conformance check; future use cases: `Convertible(T)`, `Iterable(T)`, `Serializable(Format)`)
- No associated types in v1
- No dynamic dispatch in v1 (static/monomorphized only)
- No auto-derive in v1 — every method must be explicitly implemented

## Grammar

Additions to `src/orhon.peg`:

```
blueprint_decl <- 'blueprint' IDENTIFIER '{' _ blueprint_body _ '}'
blueprint_body <- (blueprint_method)*
blueprint_method <- doc_block? 'func' IDENTIFIER '(' param_list? ')' type? TERM
```

Note: Blueprint methods reuse existing `param_list` and `type` rules but have no block body — the line ends with `TERM`. This is distinct from `func_decl` which requires a `block` body. The parser enforces this: if a `{` follows the signature inside a blueprint, it's an error ("blueprint methods cannot have bodies").

`struct_decl` is extended to accept optional blueprint conformance:

```
struct_decl <- 'pub'? 'struct' IDENTIFIER generic_params? (':' blueprint_list)? '{' _ struct_body _ '}'
blueprint_list <- IDENTIFIER (',' IDENTIFIER)*
```

## AST

### New node kind

```zig
// NodeKind enum
blueprint_decl,

// New struct
pub const BlueprintDecl = struct {
    name: []const u8,
    methods: []*Node,    // func_signature nodes (no body)
    is_pub: bool,
    doc: ?[]const u8,
};
```

### StructDecl extension

```zig
pub const StructDecl = struct {
    name: []const u8,
    type_params: []*Node,
    members: []*Node,
    blueprints: []const []const u8,  // NEW: ["Eq", "Hash"]
    is_pub: bool,
    is_bridge: bool,
    doc: ?[]const u8,
};
```

## Declaration Pass

### New types in `declarations.zig`

```zig
pub const BlueprintSig = struct {
    name: []const u8,
    methods: []BlueprintMethodSig,
    is_pub: bool,
};

pub const BlueprintMethodSig = struct {
    name: []const u8,
    params: []ParamSig,
    return_type: types.ResolvedType,
};
```

### DeclTable extension

```zig
blueprints: std.StringHashMap(BlueprintSig),
```

### StructSig extension

```zig
pub const StructSig = struct {
    name: []const u8,
    fields: []FieldSig,
    conforms_to: []const []const u8,  // NEW: blueprint names
    is_pub: bool,
};
```

### Collection flow

1. `DeclCollector` encounters `blueprint_decl` → collects name + method signatures → stores in `decls.blueprints`
2. `DeclCollector` encounters `struct_decl` with blueprints list → stores blueprint names on `StructSig.conforms_to`
3. No validation during collection — conformance checking is in the resolver

## Resolver — Conformance Checking

Runs during type resolution pass (pass 7), after struct methods are resolved.

### Algorithm

For each struct with `conforms_to` entries:

1. **Resolve blueprint name** — look up in `decls.blueprints`. Not found → error.
2. **For each method in the blueprint:**
   - Look up `"StructName.methodName"` in `decls.struct_methods`
   - Missing → error
   - Found → compare signatures:
     - Parameter count must match
     - Parameter types must match, with blueprint name substituted for struct name
     - Return type must match, same substitution rule
   - Mismatch → error with expected vs found signatures
3. **Check for duplicates** — same blueprint listed twice → error

### Name substitution rule

When comparing types, any occurrence of the blueprint's name in the blueprint method signature is treated as equivalent to the struct's name. `const& Eq` in the blueprint matches `const& Point` in the struct.

### Cross-module conformance

A struct in module A can conform to a `pub blueprint` in module B, as long as module A imports module B. Uses the same cross-module lookup mechanisms already in the resolver.

## Codegen — Pure Erasure

- **Blueprint declarations:** Skipped entirely. No Zig output.
- **Conforming structs:** Emitted as plain Zig structs, same as non-conforming structs. `conforms_to` is ignored.
- **MIR:** No changes. Blueprint nodes are skipped during annotation.
- **Passes 8–12 don't know blueprints exist.** All enforcement is in passes 1–7.

### Example

```
// Orhon input
struct Point: Eq {
    x: f32
    y: f32

    func eq(self: const& Point, other: const& Point) bool {
        return self.x == other.x and self.y == other.y
    }
}

// Generated Zig — no trace of Eq
const Point = struct {
    x: f32,
    y: f32,

    pub fn eq(self: *const Point, other: *const Point) bool {
        return self.x == other.x and self.y == other.y;
    }
};
```

## Error Messages

### 1. Unknown blueprint

```
error: unknown blueprint 'Foo'
  --> shapes.orh:5:16
    | struct Point: Foo {
    |               ^^^
```

### 2. Missing method

```
error: struct 'Point' does not implement 'eq' required by blueprint 'Eq'
  --> shapes.orh:5:8
    | struct Point: Eq {
    |        ^^^^^
```

### 3. Wrong signature

```
error: method 'eq' in struct 'Point' does not match blueprint 'Eq'
  --> shapes.orh:9:5
    | expected: func eq(self: const& Point, other: const& Point) bool
    |    found: func eq(self: const& Point) bool
```

### 4. Blueprint with method body

```
error: blueprint methods cannot have bodies
  --> contracts.orh:3:5
    | func eq(self: const& Eq, other: const& Eq) bool {
    |                                                  ^
```

### 5. Duplicate conformance

```
error: struct 'Point' lists blueprint 'Eq' more than once
  --> shapes.orh:5:8
    | struct Point: Eq, Eq {
    |                   ^^
```

## Testing Strategy

### Unit tests (Zig test blocks)

- Blueprint declaration collection in `declarations.zig`
- Conformance checking logic in `resolver.zig` — signature matching, name substitution

### Language feature tests (`test/fixtures/`)

- `blueprint_basic.orh` — declare a blueprint, struct conforms, compiles successfully
- `blueprint_multiple.orh` — struct conforms to multiple blueprints
- `blueprint_cross_module.orh` — blueprint in one module, struct conforming in another

### Negative tests (`test/11_errors.sh`)

- Missing method
- Wrong signature (wrong params, wrong return type, wrong borrow kind)
- Unknown blueprint name
- Blueprint method with body
- Duplicate conformance
- Non-pub blueprint used from another module

### Example module update

- Add blueprint usage to the example module (`src/templates/`) as part of the living language manual

## Deferred to Future Versions

- **Generic blueprints** — `blueprint Convertible(T: type) { ... }`. Needs type substitution in conformance check.
- **Auto-derive** — compiler generates method implementations from field introspection via compt.
- **Default method implementations** — methods with bodies in blueprints.
- **Dynamic dispatch** — vtable generation for heterogeneous collections.
- **Blueprint as parameter type** — `func draw(item: Drawable)` for constrained generics.
- **Associated types** — type members declared in blueprints.
