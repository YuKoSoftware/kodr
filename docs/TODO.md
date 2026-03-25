# Orhon — TODO

---

## Bugs

### ~~Codegen — cross-module struct ref-passing~~ — fixed v0.10 Phase 4

~~Codegen didn't know imported method parameter types.~~ Fixed: MIR `resolveCallSig`
now resolves cross-module instance method signatures for `value_to_const_ref` coercion.

### ~~Resolver — qualified generic types not validated~~ — fixed v0.10 Phase 4

~~Qualified generic types bypassed validation.~~ Fixed: resolver reports Orhon-level
errors when module is found but type doesn't exist in its DeclTable.

### ~~Ownership — const values treated as moved on by-value pass~~ — fixed v0.11 Phase 8

~~Const struct values counted as moves.~~ Fixed: const non-primitives now auto-borrow
as `const &` at call sites. Codegen emits `*const T` signatures and `&arg` at call sites.
`copy()` still works for explicit copies.

### Codegen — tester module fails to compile (cross-module codegen) — partially fixed v0.9.6

~~For-loop index variables, destructure name leaking, named tuple types, null literal
wrapping~~ — all fixed. ~~Pointer constructors and collection constructors migrated
to `.new()`/`.cast()` method-style syntax.~~ Collection `.new()` fixed in v0.10 Phase 4.
Pointer syntax simplified: `Ptr(T).cast(&x)` replaced by `const p: Ptr(T) = &x` — type
annotation carries pointer kind, `&` takes the address. `.cast()` removed.

### Module — sidecar path leaked (`error(gpa)`) — fixed v0.9.6

~~`module.zig:660` allocates a sidecar path string that is never freed.~~ Fixed: freed
in `Resolver.deinit()`.

### ~~`orhon test` — output format mismatch~~ — fixed v0.10 Phase 4 (v0.9 Phase 1)

~~Reports 0 passed/0 failed.~~ Fixed: test output parsing corrected.

### ~~Stdlib — string interpolation leaks memory~~ — fixed v0.10 Phase 6

~~`@{variable}` allocates temp buffers never freed.~~ Fixed: codegen emits
`defer std.heap.page_allocator.free(...)` after each `allocPrint`.

### ~~Codegen — `catch unreachable` in generated code~~ — fixed v0.10 Phase 5

~~Thread shared state allocation crashes on OOM.~~ Fixed: 4 compiler-side instances
replaced with `@panic` with diagnostic messages. 8 generated-code instances are
correct (error union narrowing) and remain.

### ~~Stdlib — silent error suppression (`catch {}`)~~ — fixed v0.10 Phase 5

~~103 instances of `catch {}` across 15 files.~~ Fixed: v0.9 Phase 2 fixed 75 instances,
v0.10 Phase 5 fixed remaining 8 data-loss sites (collections, stream). 20 fire-and-forget
I/O sites (console, tui, fs, system) intentionally retained.

---

## Polish

### Fuzz Testing

Use Zig's built-in `std.testing.fuzz` to fuzz the lexer and parser.

---

## Architecture

### Runtime Library Removal ✓

**Done.** Zero runtime libraries. The compiler injects no hardcoded imports. The only
hardcoded import is `const std = @import("std");`.

**What was removed:**
- `_orhon_collections` — collections are now a normal bridge module (`import std::collections`)
- `_orhon_str` — string ops are a normal bridge module (`import std::str`)
- `_orhon_rt` — **deleted entirely**. `_rt.zig` and `_rt.orh` no longer exist.
- All `_rt.` references in codegen replaced with native Zig equivalents
- `_str` and `_collections` hardcoded prefixes replaced with user import aliases
- `OrhonRing`/`OrhonORing` stubs removed

**Native type mapping (no wrappers):**
- `(null | T)` → `?T` (native Zig optional)
- `(Error | T)` → `anyerror!T` (native Zig error union)
- `Error("msg")` → `error.msg_sanitized` (native Zig error code)
- `typeid(x)` → `@intFromPtr(@typeName(@TypeOf(x)).ptr)` (inline)
- Allocator → `std.heap.page_allocator` (inline)
- `Handle(T)` → `_OrhonHandle(T)` (comptime helper emitted per file)

### PEG Parser — Error Recovery ✓

~~The PEG parser currently stops at the first error.~~ **Done in v0.9.3.** Grammar-level
error recovery via `error_skip` + `top_level_start` rules in `orhon.peg`. On top-level
parse failure, skips bad tokens until the next declaration keyword (`func`, `struct`, etc.)
and continues parsing. Multiple syntax errors collected via `BuildContext.syntax_errors`.

### MIR — Complete Self-Containment Migration ✓

~~MirNode now carries self-contained data fields populated during lowering. ~37 `m.ast.*`
accesses in codegen still read through the AST back-pointer.~~ **Done.** All semantic data
reads from MirNode. Added `LiteralKind` enum, `is_const`, `type_annotation`, `return_type`,
`backing_type`, `type_params`, `default_value`, `bit_members`, `arg_names`, `field_names`,
`captures`, `index_var`, `names`, `interp_parts` fields. Match arm children now include
pattern (`[pattern, body]`). `collectAssignedMir` traverses MirNode tree. 6 residual
`m.ast` accesses remain for: source location queries, current function node tracking,
and `type_expr`/`passthrough` (type trees are structural, not duplicated into MIR).

**Next:** split codegen into three layers:
- **Zig IR** — small explicit representation of target Zig AST (~15-20 node types)
- **Lowering** (MIR → Zig IR) — coercions, union wrapping, bridge imports
- **Zig Printer** (Zig IR → text) — trivial pretty-printer (~500 lines)

### Dependency-Parallel Module Compilation

Modules are processed sequentially in topological order. Independent modules (whose deps
are all complete) could be processed in parallel via a thread pool.

**Prerequisites:**
- Thread-safe `Reporter` (atomic append to error/warning lists)
- Per-module allocators (already arena-based, close to ready)
- Work-stealing queue with dependency tracking
- Careful DeclTable registration ordering for cross-module refs

The `SemanticContext` refactor (v0.9.3) lays groundwork — each pass now takes a shared
context rather than wiring individual fields, making per-thread state easier.

### PEG Parser — Syntax Documentation Generator

Auto-generate a formatted syntax reference from `src/orhon.peg`. Each rule name
becomes a section heading, alternatives become the documented forms.

### MIR Phase 4 — Optimization + Caching

Selective optimization passes — only where Orhon has type knowledge that Zig/LLVM lacks.
Inspired by vnmakarov/MIR's philosophy: pick high-impact passes, skip what the downstream compiler already handles.

**4a — SSA construction.** Flatten MirNode tree to basic blocks, build SSA form using Braun's
algorithm (simple, no dominance frontiers needed). Each value gets a single definition, phi
nodes at join points. This is the foundation — all subsequent passes run on SSA form.

**4b — Inlining.** Identify inline candidates: bridge wrappers, single-expression functions,
generated coercion wrappers. Substitute at call sites. SSA makes substitution clean (no
variable name collisions). Reduces emitted Zig volume and gives LLVM better input.

**4c — Dead code elimination.** Trivial on SSA: if an SSA value has no uses, delete it.
Reachability analysis from entry points, skip emission of unreachable code. Less emitted
Zig = faster Zig compilation.

**4d — Type-aware constant folding.** Fold `@type(x) == T` when statically known, eliminate
redundant wrap/unwrap coercion chains, simplify coercion sequences. Single definitions mean
constants propagate in one pass.

**4e — MIR caching.** Binary serialization/deserialization of SSA IR per module. Cache
invalidation via file content hashing. Skip annotation + lowering for unchanged modules on
incremental rebuilds.
