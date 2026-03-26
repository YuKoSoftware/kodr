# Phase 17: Void in Error Unions - Research

**Researched:** 2026-03-26
**Domain:** Orhon compiler pipeline — type resolution, codegen, propagation for `(Error | void)`
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Use `void` — no new `Unit` type. `void` already exists as a keyword and primitive type in Orhon
- **D-02:** The user writes `(Error | void)` — `void` appears in the union position like any other type
- **D-03:** The grammar already accepts `void` in union types — no grammar changes expected
- **D-04:** No grammar changes expected — verify and confirm
- **D-05:** `resolveUnion` already detects `(Error | T)` and produces `.error_union` — needs verification that `T = void` flows through correctly
- **D-06:** The inner type of `.error_union` can be `.void` primitive — downstream passes must handle this
- **D-07:** `typeToZig` on `type_union` with Error already emits `anyerror!{inner}` — with void inner, should emit `anyerror!void`
- **D-08:** Return statements in `(Error | void)` functions: `return` (no value) must work, and error returns must work
- **D-09:** 1:1 mapping to Zig — `anyerror!void` is valid Zig, Zig handles the semantics
- **D-10:** Ownership, borrow, and propagation passes must not reject `void` as an error union inner type
- **D-11:** The `is Error` / `is not Error` checks must work on `(Error | void)` values

### Claude's Discretion
- Which validation passes (if any) need changes vs already handle void correctly
- Test fixture design for bridge functions returning `(Error | void)`
- Whether the fix is purely test coverage or requires actual code changes (scout suggests it may already work)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TAMGA-03 | `(Error | void)` parses and compiles — codegen emits `anyerror!void`; bridge functions returning `(Error | void)` work; existing `void` return functions unchanged | Pipeline already handles `(Error | void)` at every pass — stdlib bridge files prove it. Phase work is test coverage, not code changes. |
</phase_requirements>

---

## Summary

The research traced `(Error | void)` through all 12 compiler passes by reading actual source code. The finding is clear: **`(Error | void)` already works end-to-end**. It is not a code-change phase — it is a test-coverage phase.

The stdlib bridge files (`src/std/fs.orh`, `src/std/net.orh`, `src/std/system.orh`, `src/std/tui.orh`) already declare multiple `pub bridge func ... (Error | void)` signatures, and the compiler processes them today. No validation pass rejects `void` as an error union inner type. The codegen path is clean. The gap is that no existing test fixture exercises `(Error | void)` in user-written Orhon code with a full compile-and-run cycle.

**Primary recommendation:** Write a test fixture with a user-defined `(Error | void)` function, add it to the tester module or a dedicated fixture, verify codegen emits `anyerror!void`, and add a negative test if needed. No compiler changes expected.

---

## Verification: Per-Pass Trace

### Pass 1: Lexer
`void` is a keyword token. `keyword_type` in `orhon.peg` line 539 already includes `'void'`. No change needed. (HIGH confidence — verified in `src/orhon.peg:539`)

### Pass 2: Parser / PEG Builder
`buildKeywordType()` at `src/peg/builder.zig:1395` creates `.type_named = "void"` — same as any keyword type. `buildParenType()` at line 1440 collects both type children (Error and void), finds 2 members, and returns a `.type_union` node. No special-casing needed. (HIGH confidence — verified by reading the builder)

### Pass 3: Module Resolver
No type resolution at this pass. No action needed.

### Pass 4: Declaration Collector
Bridge function signatures are stored in `decls.funcs` with `return_type` from `resolveTypeNode`. No special handling needed.

### Pass 5: Type Resolver
`resolveUnion()` in `src/types.zig:340` checks if first member is `"Error"` — it is — then resolves the second member. `resolveTypeNode("void")` returns `.{ .primitive = .void }`. Result: `.{ .error_union = &.{ .primitive = .void } }`. (HIGH confidence — verified by reading `resolveUnion`)

### Pass 6: Semantic Analysis / Ownership
`classifyType(.error_union)` in `src/mir.zig:34` returns `.error_union` regardless of the inner type. `void` inner has no ownership implications — it carries no value. No change needed.

### Pass 7: Borrow Checker
Borrow checker operates on values. `void` values are not stored or borrowed. No action needed.

### Pass 8: Thread Safety
Thread safety checks ownership of values passed across boundaries. `void` has nothing to check. No action needed.

### Pass 9: Propagation Checker
`typeCanPropagate()` in `src/propagation.zig:436` checks the `type_union` branch — finds `"Error"` in the members — returns `true`. Correct. `typeNodeIsUnion()` at line 399 finds `"Error"` in the union members — returns `true` (is error union). Correct.

`exprReturnsUnion()` at line 345 looks up the function signature in `decls.funcs` and calls `sig.return_type.isErrorUnion()` — which returns `true` for `.error_union` regardless of inner type. Correct.

The propagation checker does NOT inspect the inner type of an error union. It only tracks whether the union was handled (via `is Error` check or returned). No change needed. (HIGH confidence)

### Pass 10: MIR Annotator
`classifyType(.{ .error_union = &.{ .primitive = .void } })` returns `.error_union`. `funcReturnTypeClass()` returns `.error_union` for the enclosing function. All downstream codegen branches (`funcReturnTypeClass() == .error_union`) activate correctly. No change needed. (HIGH confidence)

### Pass 11: Codegen
`typeToZig` for `type_union` at `src/codegen.zig:3829`:
1. Sets `has_error = true` (found "Error" in members)
2. Iterates again looking for non-Error, non-NULL member
3. Finds `void` (not "Error", not "null")
4. Calls `typeToZig` on the `void` type_named node
5. Goes to `.type_named => builtins.primitiveToZig("void")` → returns `"void"`
6. Emits `anyerror!void`

Return statement handling at line 1418: `return;` with no children emits `return;`. Correct for `void` success path. Error literal returns use `return err_value;`. Both cases handled. (HIGH confidence — verified by reading codegen)

### Pass 12: Zig Runner
`anyerror!void` is valid Zig. Zig handles `return;` and `return error.Foo;` inside `anyerror!void` functions natively. No change needed.

---

## Architecture Patterns

### What Makes `(Error | void)` Different from `(Error | i32)`

The only semantic difference: the success path carries no value. In Zig, `anyerror!void` functions:
- Return successfully with bare `return;`
- Return errors with `return error.SomeError;` or by propagating `try`

Orhon's codegen emits `return;` when `return_stmt` has no children (line 1418-1448) — this is already correct behavior for `void`-returning functions. Nothing changes when the return type is `anyerror!void` vs `void`.

### Bridge Function Pattern
Bridge functions with `(Error | void)` return types are re-exported from Zig sidecars. Codegen emits `const funcName = @import("module_bridge.zig").funcName;`. The type annotation in the `.orh` file is only used for type resolution and validation passes — it does not affect the re-export call.

### Test Fixture Design

The correct test fixture for TAMGA-03:

```orhon
// In tester.orh or a dedicated fixture:

// A non-bridge function returning (Error | void)
pub func doSideEffect(flag: bool) (Error | void) {
    if(flag) {
        return Error("side effect failed")
    }
    return
}
```

Calling this in tester_main.orh:
```orhon
// Call site — propagation checker should accept bare return from (Error | void)
const result = doSideEffect(true)
if(result is Error) {
    console.print("got error")
} else {
    console.print("success: void")
}
```

Expected generated Zig:
```zig
pub fn doSideEffect(flag: bool) anyerror!void {
    if (flag) {
        return error.OrhonError;
    }
    return;
}
```

### Propagation Handling at Call Sites

When `result = doSideEffect(...)` is a tracked union variable, the propagation checker requires it to be handled before scope exit. `is Error` marks it handled. `is void` would also mark it handled. The checker doesn't distinguish inner types.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| `anyerror!void` Zig output | Custom void-union codegen | Existing `typeToZig` path | Already handles it correctly |
| `void` primitive mapping | New primitive | Existing `Primitive.void` + `Primitive.toZig()` | Already returns `"void"` |
| Propagation tracking for `(Error | void)` | Custom void tracking | Existing `PropagationChecker` | Already tracks any error_union regardless of inner type |

---

## Common Pitfalls

### Pitfall 1: Assuming a Code Change is Required
**What goes wrong:** Spending time modifying compiler passes that already work.
**Why it happens:** The Tamga bug reported `Unit` as failing, not `void`. The decision to use `void` instead means the actual keyword was already supported.
**How to avoid:** Run a simple `(Error | void)` fixture through the compiler first — it should compile cleanly.
**Warning signs:** If the compiler rejects it, check which pass reports the error rather than guessing.

### Pitfall 2: Testing Only the Bridge Path
**What goes wrong:** Only adding a bridge function test, missing coverage of user-defined `(Error | void)` functions.
**Why it happens:** The Tamga motivation is bridge functions, but user-defined functions are equally important.
**How to avoid:** Test both: a user-defined `func f() (Error | void)` AND a bridge declaration.

### Pitfall 3: Match Statement on `(Error | void)`
**What goes wrong:** A `match` on `(Error | void)` variable requires a `void` arm. The `validateMatchArm` at `resolver.zig:773` allows `inner.name()` which returns `"void"` — but users may not know to write `void =>` as a match arm.
**Why it happens:** `void` is typically not a "value" you match on.
**How to avoid:** Prefer `is Error` / `else` pattern rather than full `match`. Document this in the test fixture. Do not add match-on-void to the test scope unless TAMGA-03 explicitly requires it.

### Pitfall 4: Bare `return` Inside Propagating Scope
**What goes wrong:** Propagation checker tracks the function as `func_returns_error = true`, so any unhandled union vars in the scope are silently auto-propagated. This is correct behavior — bare `return;` from a `(Error | void)` function is valid.
**Why it happens:** Confusion between "unhandled union variable" (needs `is Error` check) and "return with void" (just returns, no union variable to handle).
**How to avoid:** Distinguish `const r = doSideEffect()` (tracked union var, needs handling) from `doSideEffect()` as a bare call (result discarded — no tracking needed).

---

## Code Examples

Verified from source:

### typeToZig for (Error | void) — src/codegen.zig:3829
```zig
// has_error = true, iterates, finds "void" member
// calls typeToZig on .type_named = "void"
// .type_named => builtins.primitiveToZig("void") => "void"
// emits: "anyerror!void"
```

### resolveUnion for (Error | void) — src/types.zig:340
```zig
// first = .type_named = "Error" → matches K.Type.ERROR
// second = .type_named = "void"
// resolveTypeNode("void") → Primitive.fromName("void") → .void
// returns .{ .primitive = .void }
// result: .{ .error_union = inner }  where inner.* = .{ .primitive = .void }
```

### Return statement for (Error | void) function — src/codegen.zig:1418
```zig
.return_stmt => {
    try self.emit("return");
    if (m.children.len > 0) { ... }  // bare return: no children → emits "return;"
    try self.emit(";");
}
```

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — pure compiler pass logic and test fixture work)

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell-based integration tests + Zig unit tests |
| Config file | `testall.sh` + `test/01_unit.sh` through `test/11_errors.sh` |
| Quick run command | `bash test/09_language.sh && bash test/10_runtime.sh` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TAMGA-03 | `(Error | void)` compiles and emits `anyerror!void` | codegen integration | `bash test/09_language.sh` (after fixture added to tester) | ❌ Wave 0 |
| TAMGA-03 | Bridge function with `(Error | void)` return compiles | codegen integration | `bash test/09_language.sh` | ❌ Wave 0 (needs fixture) |
| TAMGA-03 | Existing `void` return functions unchanged | regression | `./testall.sh` | ✅ (existing tester.orh has `void` functions) |
| TAMGA-03 | Codegen emits `anyerror!void` in generated Zig | codegen check | `bash test/08_codegen.sh` (after check added) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `bash test/09_language.sh`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fixtures/tester.orh` — add `(Error | void)` function (user-defined, non-bridge)
- [ ] `test/fixtures/tester_main.orh` — add call site exercising `is Error` / success path
- [ ] Optionally: `test/08_codegen.sh` — add grep check for `anyerror!void` in generated Zig

---

## Open Questions

1. **Does `(Error | void)` actually compile today without any changes?**
   - What we know: Every pass traced shows no rejection of `void` inner type
   - What's unclear: Has it ever been run through the full pipeline end-to-end in user code?
   - Recommendation: Wave 0 task should be: write the fixture, run it, confirm green before writing any code. If it passes, the phase is done (test only). If it fails, identify exactly which pass rejects it.

2. **Is match-on-void in scope?**
   - What we know: `validateMatchArm` would accept `void` as a pattern name since `inner.name()` returns `"void"`
   - What's unclear: TAMGA-03 doesn't mention match expressions — only compile + bridge + unchanged void funcs
   - Recommendation: Out of scope unless a test reveals it doesn't work.

3. **`is not Error` on `(Error | void)` — codegen of the else branch**
   - What we know: For `(Error | i32)`, the else branch can bind the value. For `(Error | void)`, there is no value to bind.
   - What's unclear: Does the codegen for `else { ... }` after `if(x is Error)` try to unwrap `.value` on the void inner?
   - Recommendation: Test this in the fixture. The `is Error` check should produce a clean `else` branch with no value unwrap.

---

## Sources

### Primary (HIGH confidence)
- `src/orhon.peg:538-539` — `keyword_type` includes `'void'`; `paren_type:493-497` — union type grammar
- `src/peg/builder.zig:1395,1440` — `buildKeywordType`, `buildParenType` — both create `.type_named = "void"` and `.type_union` correctly
- `src/types.zig:340-357` — `resolveUnion` creates `.error_union` with void inner; `Primitive.fromName("void")` returns `.void`
- `src/codegen.zig:3829-3848` — `typeToZig` for `type_union` finds non-Error/non-null member, emits `anyerror!{inner}`
- `src/codegen.zig:1418-1448` — return statement: bare `return;` (no children) works
- `src/mir.zig:32-49` — `classifyType` returns `.error_union` for any `error_union` regardless of inner
- `src/propagation.zig:399-447` — `typeNodeIsUnion` and `typeCanPropagate` check for `"Error"` presence, not inner type
- `src/builtins.zig:96-122` — `primitiveToZig("void")` falls through to identity return → `"void"`
- `src/std/fs.orh`, `src/std/net.orh`, `src/std/system.orh`, `src/std/tui.orh` — stdlib already uses `(Error | void)` in bridge signatures
- `docs/bugs.txt:87-100` — Tamga bug was `Unit` not `void`; using `void` was not attempted

### Secondary (MEDIUM confidence)
- Tamga `docs/bugs.txt` — confirms the workaround used `(Error | bool)` rather than `(Error | void)`, implying `void` was never tested in user code

---

## Metadata

**Confidence breakdown:**
- Pipeline already works: HIGH — traced all 12 passes, no rejection found
- Test coverage gap: HIGH — no test fixture for user-defined `(Error | void)` confirmed by grep
- Match statement behavior: MEDIUM — `validateMatchArm` logic read but not run against void

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (compiler internals are stable; this won't change)
