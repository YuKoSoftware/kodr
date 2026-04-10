# Handle Type — Design Spec

**Date:** 2026-04-11
**Scope:** New `handle` keyword for nominally-typed opaque pointer declarations

---

## Motivation

Orhon needs a safe way to represent opaque pointers — values that are held and passed
but never dereferenced. The primary use case is Zig interop (libraries like tamga expose
`*anyopaque` handles for windows, GPU resources, etc.), but handle types are useful in
pure Orhon code too (any library handing out opaque resource identifiers).

Orhon's safety philosophy requires that these pointers cannot be dereferenced, cast, or
used in arithmetic. The `handle` keyword creates a nominally-typed opaque value: two
handle types with different names are incompatible at compile time.

This is a novel combination: language-level keyword, nominal typing, safe by construction,
zero ceremony, zero runtime cost.

---

## Syntax

```
handle WindowHandle           // private
pub handle WindowHandle       // public (exported)
```

No body, no braces, no fields. A handle declaration creates a named type.

### Usage

```
import tamga_sdl3

func main() {
    const win: tamga_sdl3.WindowHandle = tamga_sdl3.createWindow("hello", 800, 600)
    tamga_sdl3.destroyWindow(win)
}
```

### Optional handles

```
func tryOpen(path: str) (null | GamepadHandle) { ... }

func use() {
    const gp = tryOpen("/dev/input/js0")
    if(gp) |handle| {
        closeGamepad(handle)
    }
}
```

### As struct fields

```
struct Renderer {
    window: WindowHandle
    device: DeviceHandle
}
```

---

## Type System Rules

- Handle types are **nominal** — `handle A` and `handle B` are different types
- Valid uses: assignment, function params/returns, struct fields, optionals
- Invalid uses (compile-time errors):
  - Arithmetic: `h + 1`
  - Indexing: `h[0]`
  - Field access: `h.field`
  - Casting: `@cast(h)`
  - Dereferencing

---

## Codegen

`handle` compiles to a Zig type alias for `*anyopaque`:

```
handle WindowHandle       →  const WindowHandle = *anyopaque;
pub handle WindowHandle   →  pub const WindowHandle = *anyopaque;
```

Zero runtime overhead. Functions using handle types reference the alias name directly:

```
func destroy(win: WindowHandle)  →  fn destroy(win: WindowHandle) void { ... }
```

Zig resolves the alias to `*anyopaque` on its side.

---

## Pipeline

1. **PEG parse** — new rule: `handle_decl <- 'handle' IDENTIFIER`
2. **AST** — new `handle_decl` node kind with `HandleDecl` struct (name, is_pub, doc)
3. **Declaration collection** — registered in `DeclTable.handles` map; duplicates are errors
4. **MIR lowering** — new `handle_def` MIR kind, carries name and is_pub
5. **Codegen** — emits `const Name = *anyopaque;`
6. **Import/export** — `pub handle` is visible to importing modules, same as `pub struct`

### Files to modify

| File | Change |
|------|--------|
| `src/peg/orhon.peg` | Add `handle_decl` rule, add to `top_level_decl`, `pub_decl`, `top_level_start` |
| `src/lexer.zig` | Add `kw_handle` to `TokenKind` enum and `KEYWORDS` map |
| `src/parser.zig` | Add `handle_decl` to `NodeKind`, `Node` union, add `HandleDecl` struct |
| `src/peg/builder_decls.zig` | Add `buildHandleDecl` builder function |
| `src/declarations.zig` | Add `HandleSig`, `handles` map to `DeclTable`, `collectHandle` method |
| `src/mir/mir_node.zig` | Add `handle_def` to `MirKind` enum |
| `src/mir/mir_lowerer.zig` | Handle `handle_decl` in `collectDeclaration` and `lowerNode` |
| `src/codegen/codegen_decls.zig` | Add `generateHandleMir` function |
| `src/codegen/codegen.zig` | Dispatch `handle_def` to `generateHandleMir` |
| `src/resolver.zig` | Resolve handle names as valid types |

---

## Testing

**Unit tests** (in relevant `.zig` files):
- PEG parser correctly parses `handle Name` and `pub handle Name`
- Declaration collector registers handles and rejects duplicates

**Language tests** (`test/09_language.sh` fixtures):
- Declare a handle, pass through functions, return it
- Two different handles are incompatible types
- Optional handle `(null | MyHandle)` works
- Handle as a struct field

**Error tests** (`test/11_errors.sh` fixtures):
- Arithmetic on handle type → error
- Field access on handle type → error
- Duplicate handle declaration → error

**Example module** — add `handles.orh` to `src/templates/example/`

---

## Out of Scope

- Auto-mapper `*anyopaque` extraction (separate mapper improvement work)
- Cross-module `field_access` resolution (GAP-001, separate work)
- Typed/generic handles (e.g., `handle(Window)`) — future work if needed
- Handle equality comparison (`==` between same-type handles) — can add later
