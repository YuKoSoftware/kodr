# Phase 18: Type Alias Syntax - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Add support for type alias declarations using the existing `const` syntax: `const Alias: type = T`. This generates Zig `const Alias = T`. The `type` keyword in the annotation position signals that the RHS is a type expression, not a value. This blocks Tamga from creating readable type abbreviations like `pub const WindowHandle: type = Ptr(u8)`.

**NOTE:** GOAL.md references `pub type Alias = T` syntax — this is stale. The user decided to use `const Alias: type = T` form instead (reuses existing const declaration pattern).

</domain>

<decisions>
## Implementation Decisions

### Syntax
- **D-01:** Type aliases use `const Name: type = T` syntax — reuses existing const declaration, no new keyword form
- **D-02:** `pub const Name: type = T` for public aliases — `pub` modifier works the same as other const declarations
- **D-03:** Aliases are transparent (structural) — `const Speed: type = i32` means Speed equals i32, not a distinct type

### Scope
- **D-04:** Type aliases allowed at top-level and inside structs — same placement rules as `const_decl`
- **D-05:** Type aliases inside function bodies also work (Zig supports local const type aliases)

### RHS Type Forms
- **D-06:** All type forms valid on the RHS — primitives, generics (`List(T)`), pointers (`&T`, `const &T`), function types (`func(T) R`), struct types, enum types, slices (`[]T`), arrays (`[N]T`), error unions (`(Error | T)`), null unions (`(T | null)`)

### Codegen Mapping
- **D-07:** `const Name: type = T` emits `const Name = T` in Zig — the `: type` annotation is dropped (Zig infers it)
- **D-08:** `pub const Name: type = T` emits `pub const Name = T` in Zig

### Parser Strategy
- **D-09:** No new grammar rule needed — existing `const_decl` already parses `const IDENTIFIER (':' type)? '=' expr TERM`; the type annotation will be `type` (keyword_type)
- **D-10:** The RHS expression must be interpreted as a type expression — when annotation is `type`, the value is a type, not a runtime value

### Declaration Collection
- **D-11:** Type aliases registered in `DeclTable.types` hashmap — already exists with comment "type aliases and compt types"

### Claude's Discretion
- How to distinguish type alias const_decl from regular const_decl in builder/codegen (check if type annotation is `type` keyword)
- Whether to add a flag to VarDecl AST node or detect at codegen time
- Test fixture design and example module placement

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Grammar & Parser
- `src/orhon.peg` — `const_decl` rule at line 194 (already supports `: type` annotation)
- `src/peg/builder.zig` — `buildConstDecl()` at line 508 (builds const_decl nodes)

### AST
- `src/parser.zig` — `NodeKind.const_decl`, `VarDecl` struct (name, type_annotation, value, is_pub)

### Declarations
- `src/declarations.zig` — `DeclTable.types` hashmap at line 75, `collectVar()` at line 374

### Codegen
- `src/codegen.zig` — `generateCompt()` at line 1291 (similar pattern: const with type annotation)
- `src/codegen.zig` — `generateTopLevelDeclMir()` at line 1303 (MIR-path top-level declarations)

### Type System
- `src/lexer.zig` — `kw_type` token kind at line 63
- `src/peg/token_map.zig` — `"type"` → `.kw_type` mapping at line 60
- `src/orhon.peg` — `keyword_type` rule at line 538 (`'type' / 'any' / 'void' / 'null'`)

### Existing Example Module
- `src/templates/example/example.orh` — anchor file for example module
- `src/templates/example/advanced.orh` — advanced language features

### Language Spec
- `docs/02-types.md` — type system documentation (no alias section yet — needs update)
- `docs/03-variables.md` — variable declaration documentation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `const_decl` grammar rule already parses `const Name: type = expr` — no grammar changes needed
- `buildConstDecl()` in builder.zig already handles optional type annotation
- `DeclTable.types` hashmap exists and is initialized — ready for type alias entries
- `generateCompt()` in codegen.zig shows the pattern: emit `const Name: zigType = value` — type alias is simpler (drop annotation, emit RHS as type)

### Established Patterns
- `compt_decl` precedent: compile-time functions use a flag on the existing func_decl node, not a new node kind
- Codegen detects `is_compt` flag to switch between `inline fn` and `fn` — type alias can similarly be detected by checking if type annotation is `type`
- The `keyword_type` PEG rule matches `'type'` — this is what the parser produces for `: type` annotations

### Integration Points
- `src/declarations.zig` — `collectVar()` needs to detect `: type` annotation and register in `types` map instead of `vars` map
- `src/codegen.zig` — Both AST-path and MIR-path generators need to detect type alias const_decl and emit `const Name = TypeExpr` (no Zig type annotation, RHS is a type not a value)
- `src/mir.zig` — MirAnnotator/MirLowerer need to handle const_decl where value is a type expression
- `src/resolver.zig` — Type resolver may need to recognize type aliases for downstream type lookups

</code_context>

<specifics>
## Specific Ideas

- The Tamga use case is `pub const WindowHandle: type = Ptr(u8)` — pointer type abbreviations
- The `generateCompt()` function is the closest existing pattern — it emits `const Name: zigType = value`. For type aliases, emit `const Name = zigType` instead (the value IS the type)
- The `keyword_type` grammar rule already matches `'type'` as a type form, so `const X: type = ...` parses today — the issue is only in codegen/declarations not recognizing this pattern

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-type-alias-syntax*
*Context gathered: 2026-03-26*
