# Kodr — Next Steps

Prioritized list of best next moves as of 2026-03-19.

---

## Open Decisions

---

### D6. slice.splitAt() — in spec, not implemented

**Doc says** (`docs/06-collections.md`):
```
var left, right = data.splitAt(3)    // atomic split, data consumed after
```

**Code does:** Nothing — no parser rule, no codegen path for `.splitAt()`.

Tied to Thread/Async (the mechanism for safely sharing data between threads).
Defer until concurrency is implemented.

---

## Implementation Items

---

## 1. Overflow helpers — `overflow()`, `wrap()`, `sat()`
Documented in `docs/04-operators.md`, not in parser or codegen at all.
~20 lines parser + ~50 lines codegen mapping to Zig builtins.

## 2. Pass 8: Thread safety
Currently a 100-line stub. Blocked on splitAt (D6) and concurrency design.
`Thread(T)` and `Async(T)` emit a compiler error — not yet implemented.

## 3. Tighten `compt` generics
The `any` type works in simple cases but complex nested generics have untested
edge cases. `compt for` generates `inline for` but compile-time semantics may
not fully match.

## 4. Extern func sidecar validation
Missing `.zig` sidecars produce cryptic Zig errors instead of clear Kodr errors.
Add a focused error check pass.

---

## Done

- `arr[a..b]` slice expressions — parser + codegen + all passes
- `bitfield` keyword — own declaration type, clean separation from `enum`,
  integer-flag based, constructor + `.has()/.set()/.clear()/.toggle()`
- `String` (uppercase) — consistent naming, docs + templates + tests updated
- `std::console` — print, println, debugPrint, get — replaces zigstd
- `@typeid` — fixed codegen, unique per type via `@intFromPtr(@typeName(T).ptr)`
- Thread/Async — replaced broken codegen with clear "not yet implemented" error
- Spec cleanup — removed auto-deferred free, arr.ptr, Pool/Ring allocators,
  main.deps/main.gpu from spec; moved to FUTURE.md
