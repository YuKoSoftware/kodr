# Orhon — TODO

Items ordered by importance and how much they unblock future work.

---

## Core — Language Ergonomics

### Data-carrying enums (tagged unions) `hard`

Specced in `docs/10-structs-enums.md` (lines 145-150) but broken across the pipeline.
Variant field information is dropped at every stage:

1. **EnumSig** (`declarations.zig`) — only stores variant names, no field info
2. **MIR lowerer** (`mir_lowerer.zig:570-577`) — copies only name/value, drops fields
3. **Codegen** (`codegen_decls.zig:286-318`) — always emits `enum(backing)`, never `union(enum(backing))`
4. **Resolver** — no validation of variant field types

Needs a vertical slice: extend EnumSig with VariantSig (fields list), carry fields
through MIR, emit `union(enum(backing))` in codegen for data-carrying variants,
validate field types in resolver. Also: reject variants that have both data fields
AND explicit integer discriminants (currently produces confusing Zig error).

Simple value enums work correctly — this only affects data-carrying variants.

### Review metadata directives (`#name`, `#version`, `#build`, `#dep`) `medium`

All metadata directives need to be looked at together. Questions:
- Should `#dep` move to `.zon` files (like C deps already do)?
- Is `#dep` tested? (Currently zero tests)
- Are `#name`, `#version`, `#build` the right set, or should some move to `.zon`?
- Should metadata be unified into one system instead of split between `#` directives and `.zon`?

Not blocking zero-magic work — metadata doesn't touch codegen. But needs a design pass.

### For-loop tuple captures `medium`

Specced in `docs/07-control-flow.md` (line 29+): `for(my_map) |(key, value)| {}`.
AST has `is_tuple_capture` field in `ForStmt` but it's never set by the PEG builder.
The builder conflates tuple elements with index variables. Codegen only uses the first
capture element. Needs:
- Builder: detect parenthesized capture form, set `is_tuple_capture = true`
- Resolver: type-check both capture variables from map/set element types
- Codegen: emit Zig destructure pattern for tuple captures
- Blocked on std::collections having iterable map/set types

### Mixed numeric type checking and for-loop index type `medium`

The spec says "mixing numeric types is a compile error" but the check is not yet
enforced. Design decision needed on automatic widening rules:

**Same-family widening (automatic, lossless):**
- `i32 + i64` → `i64`, `f32 + f64` → `f64`, `u8 + u32` → `u32`

**Cross-family mixing (require `@cast`):**
- `i32 + f64` → error (int/float)
- `u32 + i32` → error (signed/unsigned)
- `usize + i32` → error (platform-dependent size)

Also blocked on for-loop index type — currently `usize`. Options:
- Typed index: `for (arr) |val, i: i32| { }`
- Default index to `i32` instead of `usize`
- Keep `usize` and require explicit `@cast`

Once resolved, enable mixed numeric type checking in `resolver_exprs.zig`.

### std::thread limitations `medium`

Known Zig comptime friction with Orhon codegen:
- **No top-level `spawn()` convenience** — Zig-to-Orhon converter can't handle `anytype` params.
  Users must write `thread.Thread(i32).spawn(func, arg)` instead of `thread.spawn(func, arg)`.
- **spawn/spawn2 arity split** — `spawn(func, arg)` for 1-arg, `spawn2(func, a, b)` for 2-arg.
  Zig's `@call` needs a tuple but Orhon passes individual values. Needs spawn3+ for more args.

### Tuple math (element-wise arithmetic, scalar broadcast) `hard` — DEFERRED

Specced in `docs/04-operators.md` but not implemented. Needs codegen expansion to
per-field operations and scalar broadcast wrapping. No current use cases in Tamga.

### Reject positional struct constructors `easy`

The spec says "Named instantiation always" for structs, but the resolver doesn't
reject `Player(42, "hero")` — it passes through and fails at Zig compilation with
a confusing error. Add a check: when a call targets a known struct name and args
have no names, report "struct constructors require named arguments."

### Spec: clarify `var` inside structs `easy`

`docs/10-structs-enums.md` line 11 shows `var defaultHealth: f32 = 100.0` (mutable static),
but lines 103-108 say "Only `const` is supported." The compiler accepts both.
Decide which is correct and update the spec + add validation if needed.

### Partial field move detection `medium`

Ownership pass claims to enforce struct atomicity (no partial field moves) but has no
field-access tracking. `let b = player.name` moves a single field without error.
Either implement field-level ownership states or document the limitation.

### Self outside struct scope `easy`

`Self` is accepted as a valid type everywhere (even outside structs) because the resolver
can't distinguish struct-method context from top-level. Would need `struct_depth` tracking
for anonymous structs in compt functions too. Currently codegen handles this correctly
(only maps Self → @This() inside structs), so invalid usage produces a Zig error.

### Bitfield as pure Orhon std module `hard` — DEFERRED

- Design: enum-based API — `Bitfield(Perm)` wraps a user enum, maps variants to bit positions
- Must be implemented as a pure Orhon module in std, not Zig
- **Blockers:**
  1. Compt iteration over enum variants
  2. Compt arithmetic (`1 << index` at compile time)
  3. Compt `@intFromEnum` equivalent
- Users can create bitfields manually with `u32` + bitwise operators in the meantime

### Break up oversized functions `medium`

- `generateExprMir()` in codegen_exprs.zig — 537 lines, one giant switch
- Split into per-expression-kind functions (binary, call, field, index, etc.)

### Deduplicate pipeline/LSP module resolution sequence `medium`

`pipeline.zig` and `lsp/lsp_analysis.zig` both duplicate the same module resolution
sequence: scan → parse → circular import check → validate imports. Extract into a
shared function (e.g., `Resolver.resolveAll()`) that both call.

---

## Core — Compiler Architecture

### MIR — SSA construction (Phase 4a) `hard`

Flatten MirNode tree to basic blocks, build SSA form using Braun's algorithm.
Each value gets a single definition, phi nodes at join points.

Unblocks: inlining (4b), dead code elimination (4c), constant folding (4d), MIR
caching (4e). Nothing in the optimization pipeline works without SSA.

### MIR — caching (Phase 4e) `hard`

Binary serialization/deserialization of SSA IR per module. Cache invalidation via
file content hashing. Skip annotation + lowering for unchanged modules.

### Dependency-parallel module compilation `hard`

Modules are processed sequentially in topological order. Independent modules could
be processed in parallel via a thread pool.

**Prerequisites:**
- Thread-safe `Reporter` (atomic append)
- Per-module allocators (already arena-based)
- Work-stealing queue with dependency tracking
- Careful DeclTable registration ordering for cross-module refs

---

## Core — Developer Experience

### Error message quality `medium`

- Cross-module errors should show module context
- Generic instantiation failures should show the constraint that failed
- Common mistake detection — token insertions/deletions at failure point
- `else if` → suggest `elif` (currently produces generic parse error expecting `{`)

### Formatter — line-length awareness `medium`

Missing: wrapping for long lines, function signature breaking rules, alignment
for multi-line assignments, comment-aware formatting, configurable style.

### LSP — feature-gated passes `medium`

Gate passes by request type instead of running 1–9 on every change:
- **Completion:** passes 1–4 (parse + declarations)
- **Hover:** passes 1–5 (+ type resolution)
- **Diagnostics:** passes 1–9, debounced 100–300ms

Add cancellation tokens for in-flight analysis.

### LSP — incremental document sync `hard`

Full reparse on every keystroke. No incremental updates, no background compilation,
limited completion context.

### Source mapping for debugger `hard`

Emit `.orh.map` files mapping generated `.zig` lines back to `.orh` source.
Build a VS Code DAP adapter that reads these maps.

---

## Features — Tooling & Ecosystem

### Binding generator `hard`

Auto-generate Zig module wrappers from C headers:
```bash
orhon bindgen vulkan.h --module vulkan
```

### Tree-sitter grammar `medium`

Enables syntax highlighting in Neovim, Helix, Zed, and other editors beyond VS Code.

### Web playground `hard`

Online sandbox to try Orhon without installing. Already targets `wasm32-freestanding`.
Single biggest adoption accelerator for new languages.

### Debugger integration `hard`

Debug symbol generation, GDB/LLDB line mapping from generated Zig back to `.orh`
source. See also: source mapping in Developer Experience section.

---

## Optimization Passes (require SSA — Phase 4a)

### Inlining (Phase 4b) `hard`

Inline Zig module wrappers, single-expression functions, coercion wrappers at call sites.

### Dead code elimination (Phase 4c) `hard`

If an SSA value has no uses, delete it. Reachability analysis from entry points.

### Type-aware constant folding (Phase 4d) `hard`

Fold `@type(x) == T` when statically known, eliminate redundant wrap/unwrap chains,
simplify coercion sequences.

---

## Testing Improvements

### Property-based pipeline testing `medium`

- Parse then pretty-print should round-trip
- Type-checking the same input twice should give identical results
- Codegen output should always be valid Zig (`zig ast-check`)

---

## Architectural Decisions (Settled)

| Decision | Rationale |
|----------|-----------|
| Fix bugs before architecture work | Correctness before performance/elegance |
| Const auto-borrow via MIR annotation | Re-derive const-ness from AST, avoid coupling to ownership checker |
| Pointers in std, not compiler | Borrows handle safe refs; std::ptr is the escape hatch |
| Transparent (structural) type aliases | `Speed == i32`, not a distinct nominal type |
| Allocator via `.new(alloc)`, not generic param | Keeps generics pure (types only) |
| SMP as default allocator | GeneralPurposeAllocator optimized for general use |
| Zig-as-module for Zig interop | `.zig` files auto-convert to Orhon modules |
| `throw` not `try` for error propagation | Less noisy, less hidden control flow |
| Parenthesized guard syntax `(x if expr)` | Consistent with syntax containment rule |
| Hub + satellite split pattern | All large file splits use same pattern for consistency |
| `blueprint` for traits, not `impl` blocks | Everything visible at the definition site |
| No Zig IR layer in codegen | Direct string emission. MIR/SSA is the optimization target |

---

## Explicitly NOT Adding

| Feature | Why Not |
|---------|---------|
| Macros | `compt` covers the use cases without readability costs |
| Algebraic effects | Too complex. Union-based errors + Zig module I/O is sufficient |
| Row polymorphism / structural typing | Contradicts Orhon's nominal type system |
| Garbage collection | Contradicts systems language positioning. Explicit allocators |
| Exceptions | Union-based errors are better for compiled languages |
| Operator overloading | Leads to unreadable code. Named methods are clearer |
| Multiple inheritance | Composition via struct embedding is sufficient |
| Implicit conversions | Explicit `@cast()` is correct. Implicit conversions cause subtle bugs |
| Refinement types | Struct-validation pattern already covers this |
| Full Polonius borrow checker | Overkill. NLL gives 85% of the benefit for 30% of the work |
| Zig IR layer in codegen | Would model Zig semantics inside the compiler |
| Arena allocator pairing syntax | `.new(alloc)` already covers composed allocators via Zig module |
| `#derive` auto-generation | Blueprints require explicit implementation. No implicit anything |
| `#extern` / `#packed` struct layout | `.zig` modules already support these natively |
| `async` keyword | Wait for Zig's new async design, then map cleanly. `std::thread` + `thread.Atomic` covers parallelism |
| `capture()` / closures | No anonymous functions. State passed as arguments — explicit, obvious |
