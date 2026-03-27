# Phase 21: Flexible Allocators - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Collections (List, Map, Set) accept an optional allocator parameter via `.new(alloc)`. Three usage modes: default SMP (no arg), inline allocator instantiation in the arg, or external variable. Default allocator changed from `page_allocator` to SMP. Users can build custom allocators via Zig bridge sidecars.

</domain>

<decisions>
## Implementation Decisions

### Syntax — three allocator modes
- **D-01:** Mode 1 (default): `List(i32).new()` — no allocator arg, uses global SMP singleton
- **D-02:** Mode 2 (inline): `List(i32).new(arena.allocator())` — allocator instantiated at call site
- **D-03:** Mode 3 (external): `var a = smp.allocator(); List(i32).new(a)` — allocator from variable in module/file scope
- **D-04:** Allocator passed through `.new()` constructor, NOT as a generic type parameter — keeps generics pure (types only)

### Default allocator setup
- **D-05:** Global SMP singleton lives in `collections.zig` sidecar — `var default_smp = GeneralPurposeAllocator(.{}){}` with `default_allocator()` accessor
- **D-06:** Default allocator changed from `std.heap.page_allocator` to SMP (`GeneralPurposeAllocator`)
- **D-07:** Auto-cleanup at exit — OS reclaims memory, no user-facing `.deinit()` for the default SMP

### Custom allocator bridge
- **D-08:** Custom allocators written in Zig via bridge sidecars — allocators are low-level, Zig is the right place
- **D-09:** No Orhon-side interface enforcement — Zig handles type errors if the user passes an incompatible value
- **D-10:** Existing allocator bridge types (SMP, Arena, Page) already satisfy the pattern via `.allocator()` method

### Codegen translation
- **D-11:** `.new()` with 0 args emits `.{}` (unchanged — struct zero-init picks up default SMP field)
- **D-12:** `.new(alloc)` with 1 arg emits `.{ .alloc = alloc_expr }` — allocator becomes struct field init
- **D-13:** String interpolation temp buffers switch from `page_allocator` to global SMP — consistent default across all generated code

### Claude's Discretion
- How the global SMP singleton is initialized (lazy vs eager)
- collections.zig internal refactoring to use `default_allocator()` function
- Whether `.new()` codegen path needs MIR annotation changes or can be handled purely in codegen

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Collection system
- `src/std/collections.zig` — Current collection implementations with `alloc` field and `default_alloc` constant
- `src/std/collections.orh` — Bridge declarations for List, Map, Set

### Allocator system
- `src/std/allocator.zig` — SMP, Arena, Page sidecar implementations with `.allocator()` method
- `src/std/allocator.orh` — Bridge declarations for allocator types

### Codegen — .new() handling
- `src/codegen.zig` lines 1834-1851 (AST path) and 2301-2319 (MIR path) — Current `.new()` → `.{}` emission
- `src/codegen.zig` lines 3324-3328 — String interpolation temp buffer allocation (page_allocator to replace)

### Memory spec
- `docs/09-memory.md` — Memory allocation documentation (needs updating after this phase)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `collections.zig` already has `alloc: std.mem.Allocator = default_alloc` field on all three collection types — just need to change the default
- `allocator.zig` already implements SMP with `.allocator()` returning `std.mem.Allocator` — exact interface collections expect
- `.new()` codegen already detects collection types and emits `.{}` — extend to emit `.{ .alloc = expr }` when arg present

### Established Patterns
- Bridge sidecar pattern: `.orh` declares interface, `.zig` implements — custom allocators follow this exactly
- `.new()` with 0 args → `.{}` zero-init — extend to 1 arg for allocator field
- Named Zig modules (Phase 19) — collections.zig is already a named module, cross-sidecar imports work

### Integration Points
- `codegen.zig` `.new()` emission path — add allocator arg detection
- `collections.zig` default_alloc constant — change from page_allocator to SMP singleton
- String interpolation in codegen — replace `std.heap.page_allocator` references with SMP default
- `docs/09-memory.md` — update documentation to show the 3 modes
- Example module (`src/templates/`) — add allocator usage examples

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose `.new(alloc)` over generic param `List(i32, alloc)` because it's "more clean, honest, and easier to implement" — keeps generics as pure type parameters
- SMP is the correct default because page_allocator is a raw system allocator not optimized for general use
- The pattern should feel Zig-like — Zig developers expect allocator-as-argument, not allocator-as-type-param

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 21-flexible-allocators*
*Context gathered: 2026-03-26*
