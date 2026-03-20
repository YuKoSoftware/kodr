# Kodr — Future Ideas

Ideas and language decisions that are not yet committed. These may make it into the language, get rejected, or evolve into something else.

---

## Extended `extern` — data, types, and Zig-generated code

Currently `extern func` only bridges Kodr → Zig for functions. The bridge should be extended to cover:

- **`extern func` with `any` params** — maps to `anytype` in the sidecar `.zig`, enabling generic Zig utilities callable from Kodr
- **`extern var` / `extern const`** — expose a Zig variable or constant to Kodr (e.g. hardware registers, OS constants)
- **`extern struct` / `extern enum`** — declare a type whose layout and implementation lives in Zig, used as an opaque or fully-typed value in Kodr
- **Zig-generated code** — allow a sidecar `.zig` file to `comptime`-generate types or values that Kodr then imports, enabling macros/codegen patterns without adding them to the Kodr language itself

This would make the Zig bridge a full interop layer, not just a function escape hatch. Particularly useful for: hardware bindings, wrapping C libraries, and letting power users drop into Zig for anything Kodr doesn't cover yet.

---

## Additional allocators — `mem.Pool`, `mem.Ring`, `mem.OverwriteRing`

Three allocator types are designed but not yet implemented in the compiler:

- `mem.Pool(T)` — homogeneous object pool, fixed-size chunks, no fragmentation
- `mem.Ring(T, n)` — circular buffer, returns Error when full (backpressure)
- `mem.OverwriteRing(T, n)` — circular buffer, silently overwrites oldest when full

These map to Zig's `std.heap.MemoryPool` and ring buffer implementations.
Priority: low — implement after core language is stable.

---

## External dependency management — `#dep`

Designed, not yet implemented. See `docs/11-modules.md` for the full spec.
`main.gpu` deferred until GPU/concurrency design is settled.

---

## Enforce `const` for never-reassigned variables

Currently Kodr allows `var x: i32 = 5` even if `x` is never reassigned. Zig already enforces this and errors when a `var` is never mutated.

The idea: Kodr itself (in an analysis pass, likely Pass 6 — ownership) emits a proper Kodr error like:

```
error: 'x' is never reassigned — use const
  var x: i32 = 5
      ^
```

**Arguments for:** catches mistakes early, enforces intentionality about mutability, fits the "safe language" philosophy, unnecessary mutability is a code smell.

**Arguments against:** non-trivial to implement correctly (need to track all assignments per variable across scopes), may be annoying for beginners.

**Status:** not started, low priority for now.
