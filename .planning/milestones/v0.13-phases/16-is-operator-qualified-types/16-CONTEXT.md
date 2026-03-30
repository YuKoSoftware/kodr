# Phase 16: `is` Operator Qualified Types - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the `is` operator work with cross-module types — `ev is module.Type` must parse and generate correct Zig. Currently the grammar only accepts a single `IDENTIFIER` on the RHS of `is`, blocking dotted paths like `sdl.Event`. This is needed for Tamga's union-of-structs dispatch across module boundaries.

</domain>

<decisions>
## Implementation Decisions

### Grammar
- **D-01:** The `is` RHS accepts `IDENTIFIER ('.' IDENTIFIER)*` — one or more dot-separated identifiers
- **D-02:** `is null` and `is not null` remain unchanged — `null` is a keyword, not an IDENTIFIER path
- **D-03:** `is not` continues to work with qualified types: `ev is not module.Type`

### Builder (AST Construction)
- **D-04:** For single identifiers (`ev is Foo`), builder produces `.identifier` node as before — no regression
- **D-05:** For dotted paths (`ev is module.Type`), builder produces a `.field_expr` chain — reusing the existing `field_expr` AST node type
- **D-06:** The builder scans tokens after `kw_is` (and optional `kw_not`) collecting `IDENTIFIER.IDENTIFIER...` sequences

### Codegen
- **D-07:** Codegen handles `.field_expr` on the RHS of `is` checks — emits the full dotted path in generated Zig
- **D-08:** For arbitrary union type checks (`val is mod.Type`), codegen emits `val == .mod_Type` or equivalent Zig discriminant comparison
- **D-09:** For general comptime type checks, codegen emits `@TypeOf(val) == mod.Type`
- **D-10:** 1:1 mapping — codegen is a pure translator, no validation of whether the module/type exists

### Validation
- **D-11:** Type existence validation deferred to Zig — consistent with Phase 15 approach

### Claude's Discretion
- Exact token scanning loop for collecting dotted identifiers in the builder
- How to construct the `field_expr` chain (left-to-right nesting)
- Whether to handle the arbitrary union discriminant case with dots or defer to Zig's own dispatch
- Test fixture design

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Grammar & Parser
- `src/orhon.peg` — PEG grammar, `compare_expr` rule at line 316 (the `is` operator branch)
- `src/peg/builder.zig` — `buildCompareExpr()` at line 1215, handles `is` type check construction

### AST
- `src/parser.zig` — `NodeKind.field_expr` (line 49) and `FieldExpr` struct (line 113) — for dotted paths

### Codegen
- `src/codegen.zig` — `is` operator codegen at line 1616–1671, handles Error/null/arbitrary_union/general type checks
- `src/codegen.zig` — `field_expr` generation (for emitting dotted paths in other contexts)

### Existing `is` Usage
- `src/templates/example/example.orh` — existing `is` usage in example module
- `src/templates/example/advanced.orh` — tagged union `is` pattern usage

### Bug Source
- `/home/yunus/Projects/orhon/tamga_framework/docs/bugs.txt` — OPEN: `is` operator with qualified types

</canonical_refs>

<code_context>
## Existing Code Insights

### Current Grammar
- `compare_expr <- bitor_expr 'is' 'not'? (IDENTIFIER / 'null')` — only accepts single IDENTIFIER
- Need to extend to accept `IDENTIFIER ('.' IDENTIFIER)*`

### Current Builder (line 1219–1256)
- Scans for `.kw_is` token, finds optional `.kw_not`
- Then scans for single `.identifier` or `.kw_null` token
- Constructs `binary_expr` with `compiler_func("type", args)` on LHS and `identifier` on RHS
- Needs to handle multi-token dotted paths → build `field_expr` chain

### Current Codegen (line 1616–1671)
- Handles `b.right.* == .null_literal` → null check
- Handles `b.right.* == .identifier` → Error check, arbitrary union check, general type check
- Needs new branch for `b.right.* == .field_expr` → qualified type check

### Integration Points
- `src/mir.zig` — MIR annotation may need to handle field_expr on RHS of type checks
- `src/resolver.zig` — type resolution for qualified types

</code_context>

<specifics>
## Specific Ideas

- The Tamga use case is SDL3 event dispatch: `if ev is sdl.KeyboardEvent { ... }` — cross-module union-of-structs pattern
- Hex/binary literals are not relevant here — RHS is always a type name path

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 16-is-operator-qualified-types*
*Context gathered: 2026-03-26*
