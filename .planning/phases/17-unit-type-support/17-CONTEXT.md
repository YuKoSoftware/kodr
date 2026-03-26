# Phase 17: Void in Error Unions - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Allow `void` in error union position — `(Error | void)` must parse, compile, and emit `anyerror!void` in Zig. This enables functions that can fail but return nothing on success, needed by Tamga bridge functions.

</domain>

<decisions>
## Implementation Decisions

### Naming
- **D-01:** Use `void` — no new `Unit` type. `void` already exists as a keyword and primitive type in Orhon
- **D-02:** The user writes `(Error | void)` — `void` appears in the union position like any other type

### Grammar & Parser
- **D-03:** The grammar already accepts `void` in union types — `keyword_type <- 'type' / 'any' / 'void' / 'null'` is a valid `type` alternative, and `paren_type` accepts `type ('|' type)+`
- **D-04:** No grammar changes expected — verify and confirm

### Type Resolution
- **D-05:** `resolveUnion` already detects `(Error | T)` and produces `.error_union` — needs verification that `T = void` flows through correctly
- **D-06:** The inner type of `.error_union` can be `.void` primitive — downstream passes must handle this

### Codegen
- **D-07:** `typeToZig` on `type_union` with Error already emits `anyerror!{inner}` — with void inner, should emit `anyerror!void`
- **D-08:** Return statements in `(Error | void)` functions: `return` (no value) must work, and error returns must work
- **D-09:** 1:1 mapping to Zig — `anyerror!void` is valid Zig, Zig handles the semantics

### Validation Passes
- **D-10:** Ownership, borrow, and propagation passes must not reject `void` as an error union inner type
- **D-11:** The `is Error` / `is not Error` checks must work on `(Error | void)` values

### Claude's Discretion
- Which validation passes (if any) need changes vs already handle void correctly
- Test fixture design for bridge functions returning `(Error | void)`
- Whether the fix is purely test coverage or requires actual code changes (scout suggests it may already work)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Grammar & Parser
- `src/orhon.peg` — `keyword_type` at line 538 (already includes `void`), `paren_type` at line 493-497

### Builder
- `src/peg/builder.zig` — `buildKeywordType()` at line 1395, `buildParenType()` at line 1440

### Type Resolution
- `src/types.zig` — `resolveUnion()` at line 340, `Primitive` enum (includes `.void` at line 59)

### Codegen
- `src/codegen.zig` — `typeToZig()` at line 3810, error union emit at line 3829-3848
- `src/codegen.zig` — return statement handling for error_union functions at line 2775, 3191, 3261

### Validation Passes
- `src/propagation.zig` — error propagation checking
- `src/resolver.zig` — type resolver union handling at line 714-780

### Bug Source
- `/home/yunus/Projects/orhon/tamga_framework/docs/bugs.txt` — OPEN: void in error union position

</canonical_refs>

<code_context>
## Existing Code Insights

### Likely Already Working
- Grammar accepts `(Error | void)` — `void` is in `keyword_type`, which is a valid `type`, which `paren_type` accepts in unions
- Builder produces `type_union` with `type_named = "void"` as a member
- `resolveUnion` detects Error as first member → produces `.error_union` with void inner
- `typeToZig` emits `anyerror!void` for this pattern
- `primitiveToZig("void")` returns `"void"` (passthrough)

### Potential Issues
- Validation passes may reject void as an inner type in error unions
- Return statement codegen for `(Error | void)` functions — bare `return` needs to work
- `.value` unwrap on `(Error | void)` — `void` has no value to unwrap
- Match arms on `(Error | void)` — the non-error arm binds to void

### Integration Points
- Bridge declarations with `(Error | void)` return types
- Existing `void` return functions must not be affected

</code_context>

<specifics>
## Specific Ideas

- The Tamga use case is bridge functions wrapping SDL3 calls that can fail but return nothing
- Should first test if `(Error | void)` already compiles before making any code changes — the scout suggests the pipeline may already handle it

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 17-unit-type-support*
*Context gathered: 2026-03-26*
