# Phase 22: `throw` Statement - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Add the `throw` statement to Orhon. `throw x` propagates an error from an `(Error | T)` variable and narrows `x` to type `T` for all subsequent code. This is a statement (not an expression prefix like Zig's `try`).

</domain>

<decisions>
## Implementation Decisions

### Throw Semantics
- **D-01:** `throw` operates on named variables only, not arbitrary expressions. `throw x` is valid; `throw divide(10,0)` is not. Rationale: type narrowing requires a variable to narrow — expressions have no binding to narrow.
- **D-02:** `throw x` where `x: (Error | T)` emits early return of the error and narrows `x` to `T`. The enclosing function must return an error type.
- **D-03:** `throw` is a statement keyword, not an expression. It appears on its own line: `throw result` — not inside an expression.

### Type Narrowing
- **D-04:** After `throw x`, `x` is narrowed to its value type `T` for the rest of the function (not just the current block). The throw guarantees the error case is gone — no need to re-check.
- **D-05:** Multiple `throw` statements are allowed — each narrows one variable. `throw a; throw b;` is valid when both `a` and `b` are error unions.

### Codegen
- **D-06:** `throw result` generates: `if (result) |_| {} else |err| return err;` in Zig. Subsequent uses of `result` emit the unwrapped payload access.
- **D-07:** The `throw` keyword maps to Zig's error check + early return pattern, NOT Zig's `try` (which is an expression). This is intentional — Orhon's `throw` is a statement.

### Compile Errors
- **D-08:** `throw` in a function that doesn't return `(Error | T)` produces a compile error. Wording at Claude's discretion.
- **D-09:** `throw` on a non-error-union variable produces a compile error.

### Claude's Discretion
- Exact error message wording for compile errors
- Whether the propagation checker (pass 9) or a new pass handles throw validation
- Internal representation of throw in MIR (annotation approach)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Language Spec
- `docs/08-error-handling.md` — Current error handling patterns, `(Error | T)` syntax
- `docs/TODO.md` §"throw statement for error propagation" — Design rationale and examples

### Compiler Architecture
- `docs/COMPILER.md` — Pipeline overview (12 passes)
- `src/orhon.peg` — PEG grammar (add throw_stmt rule)
- `src/lexer.zig` lines 122-169 — KEYWORDS map (add kw_throw)
- `src/peg/builder.zig` — AST builder (add throw_stmt handler)
- `src/propagation.zig` — Error propagation analysis pass (pass 9), handles union tracking
- `src/mir.zig` — MIR annotation (needs throw awareness for type narrowing)
- `src/codegen.zig` — Zig emission (emit error check + early return + narrowed access)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PropagationChecker` (src/propagation.zig) — already tracks error union variables, marks them as "handled" via `if(x is Error)` and return. Can be extended to recognize `throw` as a handling mechanism.
- `KEYWORDS` map (src/lexer.zig:122) — add `"throw"` → `.kw_throw` entry
- PEG grammar rule patterns — existing statement rules (return, defer, break) provide templates for `throw_stmt`
- MIR `NodeInfo` annotation — existing type narrowing patterns from `is` checks may inform throw narrowing

### Established Patterns
- New keyword: add to lexer KEYWORDS, add TokenKind variant, add PEG rule, add builder handler, add AST node kind
- Statement codegen: follows pattern of `generateStatementMir` dispatch in codegen
- Error union handling: MIR annotates coercions; codegen emits Zig `if/else` unwrapping

### Integration Points
- Lexer: new `.kw_throw` token kind
- PEG: `throw_stmt <- 'throw' IDENTIFIER` rule in statement position
- Builder: `buildThrowStmt` produces `throw_stmt` AST node
- Parser types: new `NodeKind.throw_stmt` variant
- Propagation (pass 9): recognize throw as union handling (marks variable as narrowed)
- MIR: annotate post-throw variable as narrowed type
- Codegen: emit `if (x) |_| {} else |err| return err;` and narrowed access pattern

</code_context>

<specifics>
## Specific Ideas

- `throw` was chosen over `try` because it's a statement, not an expression prefix — less noisy, allows work between call and propagation
- The type narrowing after `throw` is the key ergonomic win — no `.value` needed
- Pattern follows Orhon's philosophy of explicit statements over magic keywords

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 22-throw-statement*
*Context gathered: 2026-03-27*
