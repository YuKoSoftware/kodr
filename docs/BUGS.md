# Orhon — Known Bugs

Bugs discovered during testing. Fix before v1.

---

## Codegen — inferred union types not tracked

When a variable receives a function return without a type annotation, the codegen
doesn't track it as an error/null/arb union variable. This causes `.value` unwrap
to emit literal `.value` instead of `.ok`, `.some`, or `._i32`.

**Workaround:** Always annotate union variables — `const r: (Error | i32) = f()`.

## Codegen — arb union types not unified across functions

Each function that declares `(i32 | String)` gets a unique generated union type
(`func_name__union_NNNNN`). Assigning a return value from one function into a
local typed as the "same" union causes a Zig type mismatch.

**Workaround:** Use direct literal assignment or avoid cross-function arb union returns.

## Codegen — bitfield variants not namespaced

`Perms(Read, Write)` generates `Perms(Read, Write)` in Zig, but `Read` is not
in scope — it should be `.Read`. Bitfield variant names conflict with identifiers.

## Codegen — `mem` module not auto-imported

`mem.DebugAllocator()`, `mem.Arena()`, `mem.Page()` generate `mem.X()` in Zig
but `mem` is not imported. The allocator module needs codegen-level import wiring.

## Codegen — array literal to slice coercion

`system.run("echo", ["hello"])` and `parts.join(", ")` generate array literals
where Zig expects slices. Need `&` address-of operator for coercion.

## Codegen — Map.get returns optional

`Map(K,V).get()` returns `?V` in Zig but codegen treats it as `V`. Need null
union wrapping or `.?` unwrap at the call site.

## Codegen — Set/Map iteration

`for(set) |key|` and `for(map) |(key, value)|` don't work — Set/Map types are
not directly iterable in Zig. Need iterator bridge methods.

## Codegen — thread blocks

`thread(T) name { }` syntax is parsed but codegen was removed. Thread support
needs reimplementation via the bridge pattern (std.thread).
