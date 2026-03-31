# Orhon — TODO

Items ordered by importance and how much they unblock future work.

---

## Bugs

---

## Core — Language Ergonomics

These are the highest-impact language changes. Every user benefits immediately.

---

## Core — Compiler Architecture

Ordered by how much each item unblocks downstream work.

### MIR — SSA construction (Phase 4a)

Flatten MirNode tree to basic blocks, build SSA form using Braun's algorithm (simple,
no dominance frontiers needed). Each value gets a single definition, phi nodes at join
points. This is the foundation — all subsequent optimization passes run on SSA form.

Unblocks: inlining (4b), dead code elimination (4c), constant folding (4d), MIR
caching (4e). Nothing in the optimization pipeline works without SSA.

### MIR — caching (Phase 4e)

Binary serialization/deserialization of SSA IR per module. Cache invalidation via file
content hashing. Skip annotation + lowering for unchanged modules on incremental rebuilds.

Unblocks: fast incremental builds for large projects. Currently all 11 passes re-run
for every changed module.

### Dependency-parallel module compilation

Modules are processed sequentially in topological order. Independent modules (whose deps
are all complete) could be processed in parallel via a thread pool.

**Prerequisites:**
- Thread-safe `Reporter` (atomic append to error/warning lists)
- Per-module allocators (already arena-based, close to ready)
- Work-stealing queue with dependency tracking
- Careful DeclTable registration ordering for cross-module refs

The `SemanticContext` refactor (v0.9.3) lays groundwork — each pass now takes a shared
context rather than wiring individual fields, making per-thread state easier.

Unblocks: compilation speed scales with CPU cores. Matters most for projects with many
independent modules.

### ~~MIR — residual AST accesses~~ RESOLVED (v0.10.25)

Audited and resolved. 4 accesses migrated to MIR: `current_func_node` → `current_func_mir`
in `generateFuncMir`/`generateThreadFuncMir`, `nodeLoc(m.ast)` → `nodeLocMir(m)` at 2 sites.
6 accesses remain as a **permanent architectural boundary**: `typeToZig()` and `generateExpr()`
for `type_expr`/`passthrough` nodes walk the recursive AST type tree (`type_named`,
`type_slice`, `type_array`, `type_union`, `type_ptr`). Duplicating this structural tree
into MirNode adds complexity with zero benefit — type trees are syntax-to-syntax translations.
`MirNode.ast` back-pointer is retained for this purpose.

### ~~Bridge module import scoping~~ PARTIALLY DONE (v0.10.22)

~~Named bridge modules added to all targets.~~ Multi-target builds fixed: each lib/exe/test
target now only receives `addImport` for bridges it actually imports. Single-target path
left as-is — transitive bridge resolution requires all bridges to be available.

---

## Core — Build System

### ~~Thread cancellation mechanism~~ COVERED (std::async)

~~`.cancel()` sets a flag, but the mechanism for checking it inside the thread body is TBD.~~
Covered by `Atomic(bool)` in `std::async` — threads check a shared atomic flag.
Pattern: `var cancel: Atomic(bool) = Atomic(bool).new(false)`, pass to thread, check with `cancel.load()`.

---

## Core — Developer Experience

### Error message quality

The highest-ROI tooling investment. Every user hits errors. Good messages = faster
learning = more adoption. Elm, Gleam, and Rust set the bar.

**Remaining:**
- Cross-module errors should show module context
- Generic instantiation failures should show the constraint that failed
- Common mistake detection — try token insertions/deletions at failure point
  ("missing ':' in variable declaration")

### Docgen — wire `#description` as module summary

`#description = "..."` in anchor files is accepted but ignored by docgen.
Should be used as the module-level summary at the top of generated docs.
`///` doc comments remain for individual declarations only — not for modules.
This keeps multi-file modules clean: one description in the anchor, per-decl
docs wherever the declaration lives.

### Formatter — line-length awareness

Current formatter handles indentation and blank lines but has no concept of line length.
Missing: wrapping for long lines, function signature breaking rules, alignment for
multi-line assignments, comment-aware formatting, configurable style.

### LSP — feature-gated passes

Instead of running passes 1-9 on every change, gate by request type:
- **Completion:** passes 1-4 only (parse + declarations)
- **Hover:** passes 1-5 (parse + declarations + type resolution)
- **Diagnostics:** passes 1-9 (all analysis), debounced 100-300ms after last keystroke

Add cancellation tokens — if a new change arrives while analysis is running, cancel
and restart. This is rust-analyzer's architecture and the gold standard for LSP
responsiveness.

### LSP — incremental document sync

Full reparse on every keystroke. No background compilation, no incremental updates.
Limited completion context (not method-chain aware).

### Source mapping for debugger

Emit `.orh.map` files during codegen mapping generated `.zig` line numbers back to
original `.orh` source lines. Build a VS Code DAP adapter that reads these maps.
Simpler than DWARF manipulation but gives users `.orh`-level debugging.

---

## Features — Language

Ordered by how much they expand what Orhon programs can express and unblock downstream
features.

### ~~Blueprints (abstract structs — Orhon's traits)~~ DONE (v0.12.0)

~~The missing type system foundation.~~ Shipped. `blueprint` keyword defines named
method contracts. Structs declare conformance via `: Blueprint` syntax. Multiple
blueprints allowed per struct. All declared methods must be implemented — compiler
enforces completeness. No `impl` blocks — conformance is declared inline on the struct.

```
blueprint Describable {
    func describe(self: const& Describable) str
}

struct Animal: Describable {
    name: str
    pub func describe(self: const& Animal) str { return self.name }
}
```

Unblocks: generic constraints, numerous library patterns.

### ~~Compile-time struct introspection~~ DONE (v0.11.0)

~~Compiler functions for structural checks inside `compt` code.~~ Shipped.
`@hasField(T, "name")`, `@hasDecl(T, "name")`, `@fieldType(T, "name")`,
`@fieldNames(T)` — map to Zig builtins. Accept type or value as first argument
(values auto-wrapped in `@TypeOf`). Orhon-level argument validation (count +
string literal checks). Complements blueprints (nominal contracts) with low-level
introspection (structural queries).

### ~~Union flattening & CoreType unification~~ DONE (v0.13.0)

~~Compose unions from other unions.~~ Shipped. Unions containing other unions are
automatically flattened. Duplicate type names after flattening are a compile error.
`ErrorUnion(T)` and `NullUnion(T)` replace the old `(Error | T)` and `(null | T)`
syntax — Error and null are now banned from regular unions. All core language wrapper
types (ErrorUnion, NullUnion, Handle, Ptr, RawPtr, VolatilePtr) unified under a single
`CoreType` variant in the type system.


---

## Features — Tooling & Ecosystem

### Binding generator

Auto-generate `.orh` bridge + `.zig` sidecar pairs from C headers:

```bash
orhon bindgen vulkan.h --module vulkan
```

High-impact for systems programming use. Currently users write bridge declarations
by hand, which is tedious and error-prone for large C APIs.

### Tree-sitter grammar

Enables syntax highlighting in Neovim, Helix, Zed, and other modern editors beyond
VS Code. Should exist alongside the PEG grammar. Medium effort, extends reach.

### PEG syntax documentation generator

Auto-generate a formatted syntax reference from `src/orhon.peg`. Each rule name
becomes a section heading, alternatives become the documented forms.

Unblocks: always-accurate syntax docs that stay in sync with the grammar. Currently
docs are manually maintained and can drift.

### Web playground

Online sandbox to try Orhon without installing. Gleam, Go, Rust, Zig all have them.
Orhon already targets `wasm32-freestanding`. Single biggest adoption accelerator for
new languages — dramatically lowers the "try it" barrier.

### Debugger integration

Debug symbol generation, GDB/LLDB line mapping from generated Zig back to `.orh`
source. Currently debugging requires reading generated Zig. See also: source mapping
in Developer Experience section.

### Dynamic library output folder

Compiled `.so`/`.dll` files should go in a separate output folder instead of
cluttering `src/`. From Tamga feedback.

**Blocked:** Splitting exe (`bin/`) and lib (`lib/`) breaks runtime discovery —
the exe can't find the `.so` without an rpath. Either set `$ORIGIN/../lib` rpath
in generated `build.zig`, or keep everything in `bin/`. Needs rpath support first.


---

## Optimization Passes (require SSA — Phase 4a)

### Inlining (Phase 4b)

Identify inline candidates: bridge wrappers, single-expression functions, generated
coercion wrappers. Substitute at call sites. SSA makes substitution clean (no variable
name collisions). Reduces emitted Zig volume and gives LLVM better input.

### Dead code elimination (Phase 4c)

Trivial on SSA: if an SSA value has no uses, delete it. Reachability analysis from
entry points, skip emission of unreachable code. Less emitted Zig = faster Zig
compilation.

### Type-aware constant folding (Phase 4d)

Fold `@type(x) == T` when statically known, eliminate redundant wrap/unwrap coercion
chains, simplify coercion sequences. Single definitions mean constants propagate in
one pass.

---

## Testing Improvements

### Codegen snapshot tests

Capture generated `.zig` output for representative programs and diff against expected
output. Catches subtle codegen regressions that runtime tests miss (e.g., unnecessary
allocations, wrong variable names, missing `defer`).

### Property-based pipeline testing

Beyond "does it crash" fuzzing — test semantic properties across the pipeline:
- Parse then pretty-print should round-trip
- Type-checking the same input twice should give identical results
- Codegen output should always be valid Zig (run `zig ast-check` on it)

---

## Architectural Decisions (Settled)

Rationales for key choices already made. Preserved for future design consistency.

| Decision | Rationale |
|----------|-----------|
| Fix bugs before architecture work | Correctness before performance/elegance |
| Const auto-borrow via MIR annotation | Re-derive const-ness from AST, avoid coupling to ownership checker |
| Type-directed pointer coercion | Type annotation carries safety level |
| Transparent (structural) type aliases | `Speed == i32`, not a distinct nominal type |
| Allocator via `.new(alloc)`, not generic param | Keeps generics pure (types only) |
| SMP as default allocator | GeneralPurposeAllocator optimized for general use |
| Named bridge modules via build system | createModule/addImport eliminates file-path imports |
| `throw` not `try` for error propagation | Less noisy, less hidden control flow |
| Parenthesized guard syntax `(x if expr)` | Consistent with syntax containment rule |
| Hub + satellite split pattern | All large file splits use same pattern for consistency |
| `blueprint` for traits, not `impl` blocks | Everything visible at the definition site. One syntax for conformance + implementation |
| No Zig IR layer in codegen | Direct string emission. MIR/SSA is the optimization target |

---

## Explicitly NOT Adding

| Feature | Why Not |
|---------|---------|
| Macros | `compt` covers the use cases without readability costs. Zig made this choice. |
| Algebraic effects | Too complex. Union-based errors + bridge-based I/O is simpler and sufficient. |
| Row polymorphism / structural typing | Contradicts Orhon's nominal type system. |
| Garbage collection | Contradicts the systems language positioning. Explicit allocators are right. |
| Exceptions | Already decided against. Union-based errors are better for compiled languages. |
| Operator overloading | Leads to unreadable code. Named methods are always clearer. |
| Multiple inheritance | Composition via struct embedding is simpler and sufficient. |
| Implicit conversions | Orhon's explicit `cast()` is correct. Implicit conversions cause subtle bugs. |
| Refinement types | Struct-validation pattern already covers this. No language change needed. |
| Full Polonius borrow checker | Overkill for Orhon. NLL gives 85% of the benefit for 30% of the work. |
| Zig IR layer in codegen | Would model Zig semantics inside the compiler. See codegen refactor entry. |
| Arena allocator pairing syntax | Mode 2 `.new(alloc)` already covers composed allocators via bridge. |
| `#derive` auto-generation | Blueprints require explicit implementation. Fits "no implicit anything" philosophy. |
| `#extern` / `#packed` struct layout | Sidecar `.zig` files already support `extern struct` and `packed struct`. Bridge imports work normally. No need to duplicate layout control in Orhon. |
| `async` keyword | Zig removed async, will reintroduce with new design. Designing Orhon async now would mean fighting the backend. Wait for Zig's new primitives, then map cleanly. `thread` + `Atomic` covers parallelism meanwhile. |
| `capture()` / closures | Orhon has no anonymous functions. State is passed as arguments — explicit, obvious, already works. Closures would be the first implicit state mechanism in the language. Pass functions and data separately, like Zig and C. |

---

## Done

### Thread safety argument enforcement ✓

**Done in v0.10.17 (post-v0.17).** Three rules enforced at compile time when passing arguments to thread functions:
1. **Owned values** → moved into thread, original variable dead until join
2. **Const borrows (`const& x`)** → original frozen (read-only) until thread joined via `.value` or `.wait()`
3. **Mutable borrows (`mut& x`)** → compile error (no mutable sharing across threads)

Infrastructure: `moved_to_thread` map (existed, now populated), `frozen_for_thread` map (new), `checkThreadCallArgs` (new), `unfreezeForThread` (new). 14 unit tests + 4 negative integration fixtures.

### `throw` statement for error propagation ✓

**Done in v0.15 Phase 22.** `throw x` propagates error and narrows the variable
to its value type. Statement form (not expression prefix like Zig's `try`).

### Pattern guards in match ✓

**Done in v0.15 Phase 23.** `(x if x > 0) => { ... }` — parenthesized guard
syntax in match arms. Guards desugar to Zig labeled blocks with if/else chains.

### C/C++ source compilation in modules ✓

**Done in v0.15 Phase 24.** `#cimport = { name: "vma", include: "vk_mem_alloc.h",
source: "vma_impl.cpp" }` — the `source:` field compiles `.c`/`.cpp` files.
Auto-detects C++ from extension and applies `linkLibCpp()`.

### Runtime Library Removal ✓

**Done.** Zero runtime libraries. The only hardcoded imports are `const std = @import("std");`
and `str` (auto-imported for string method dispatch when not explicitly imported).

**What was removed:**
- `_orhon_collections` — collections require explicit `use std::collections` or `import std::collections` (v0.10.20)
- `_orhon_rt` — **deleted entirely**. `_rt.zig` and `_rt.orh` no longer exist.
- All `_rt.` references in codegen replaced with native Zig equivalents
- `_str` and `_collections` hardcoded prefixes replaced with user import aliases
- `OrhonRing`/`OrhonORing` stubs removed

**Native type mapping (no wrappers):**
- `(null | T)` -> `?T` (native Zig optional)
- `(Error | T)` -> `anyerror!T` (native Zig error union)
- `Error("msg")` -> `error.msg_sanitized` (native Zig error code)
- `typeid(x)` -> `@intFromPtr(@typeName(@TypeOf(x)).ptr)` (inline)
- Allocator -> `std.heap.smp_allocator` (inline)
- `Handle(T)` -> `_OrhonHandle(T)` (comptime helper emitted per file)

### PEG Parser — Error Recovery ✓

**Done in v0.9.3.** Grammar-level error recovery via `error_skip` + `top_level_start`
rules in `orhon.peg`. On top-level parse failure, skips bad tokens until the next
declaration keyword (`func`, `struct`, etc.) and continues parsing. Multiple syntax
errors collected via `BuildContext.syntax_errors`.

### MIR — Complete Self-Containment Migration ✓

**Done.** All semantic data reads from MirNode. Added `LiteralKind` enum, `is_const`,
`type_annotation`, `return_type`, `backing_type`, `type_params`, `default_value`,
`bit_members`, `arg_names`, `field_names`, `captures`, `index_var`, `names`,
`interp_parts` fields. Match arm children now include pattern (`[pattern, body]`).
`collectAssignedMir` traverses MirNode tree. Residual `m.ast` accesses audited in v0.10.25:
4 migrated (`current_func_node` → `current_func_mir`, `nodeLoc(m.ast)` → `nodeLocMir(m)`);
6 retained as permanent boundary for `typeToZig()` structural type tree walks.

### Fuzz Testing ✓

**Done in v0.12.** `std.testing.fuzz` covers lexer and parser. Standalone harness in
`src/fuzz.zig` with 5 strategies and 50,000 iterations.

### Bridge codegen fixes ✓

**Done in v0.16 Phase 25.** `const& BridgeStruct` parameters now pass by pointer
(not by value). Sidecar `export fn` declarations are fixed to `pub export fn` via
read-modify-write scanner. `is_bridge` flag on FuncSig guards const auto-borrow for
bridge calls.

### Cross-module `is` operator and negative literal parsing ✓

**Done in v0.16 Phase 26.** Cross-module `is` operator uses tagged union tag
comparison for arbitrary unions. Unary `-` placed before `&` in PEG unary_expr rule
to fix negative literal parsing.

### C interop: sidecar dedup, cimport include paths, linkSystemLibrary ✓

**Done in v0.16 Phase 27.** Infinite loop in pub-fixup scanner fixed. `addIncludePath`
derives path from sidecar dirname. Unconditional `cimport_source == null` guards
removed. Multi-file modules with Zig sidecars build correctly.

### Cross-compilation target fix and build cache cleanup ✓

**Done in v0.16 Phase 28.** Cross-compilation target flag corrected. Build cache
cleaned up. Dead `Async(T)` codegen branch removed from `typeToZig`.

### Codegen refactor ✓

**Done.** Split into 5 files: hub (`codegen.zig`) + 4 satellites (`codegen_decls.zig`,
`codegen_exprs.zig`, `codegen_stmts.zig`, `codegen_match.zig`). Zig IR layer rejected
— direct string emission kept. All smart decisions happen in MIR.

### Builtins cleanup — `List`, `Map`, `Set` no longer hardcoded ✓

**Done in v0.10.20.** Removed `List`, `Map`, `Set` from `BUILTIN_TYPES`. Collections
are now resolved through the import system like any other module. `use std::collections`
or `import std::collections` required. Added bridge func declarations to `collections.orh`.
Fixed `preScanImports` to recognize `use` keyword. Always collect declarations for all
modules (including cached) so cross-module type resolution works. Codegen's collection
auto-import and prefix logic removed.
