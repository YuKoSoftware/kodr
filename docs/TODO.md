# Orhon — TODO

Master tracking file. Everything is organized into phases ordered by dependency. Each phase has explicit blockers and a brief rationale. Severity tags: 🔴 Critical · 🟠 High · 🟡 Medium · 🟢 Low. Deferred/future work lives in [[future]].

## Current status

- **Completed:** Phase 0 — Correctness blockers ✓ | Phase A — AST/SoA rebuild ✓ | Phase B — MIR rebuild ✓ | Phase C — Codegen migration ✓ | Phase D — Cleanup ✓
- **Active project:** Phase 5 (Medium/Low Cleanup Sweep) — M4 done (v0.53.49). P1-P7, I1-I5, M1-M3, B1-B6 all done.
- **Tracking source:** Audit findings from `2026-04-14` recorded as **CB#** (correctness blockers), **H#** (architectural walls), **M#** (medium cleanup). Preserved so each item is traceable to its audit origin.

## Phase dependency graph

```
Phase 0 (correctness) ──┬─> Phase R (rebuild) ──┬─> Phase 1 (semantic)
                        │                       ├─> Phase 2 (diagnostics + testing)
Phase 4 (CLI + config) ─┘                       ├─> Phase 3 (parallelism + LSP)
                                                └─> Phase 5 (medium/low sweep — opportunistic)
```

Phase 0 must precede Phase R — the correctness bugs would be baked into the new storage otherwise.
Phase 4 can run parallel to Phase R (no overlap with AST/MIR code).
Phase 1, 2, 3 are all post-rebuild and can overlap, with internal ordering documented below.
Phase 5 is opportunistic — pick up items as time permits.

---

## Phase 0 — Correctness blockers `~3-5 days` `BEFORE REBUILD`

Silent bugs shipping today. Each fix is small (50-200 lines). Must land before Phase R so the rebuild doesn't carry the bugs forward into new storage.

- [x] **CB1** 🔴 **Borrow checker method collision** — `src/borrow.zig:172-181` says "first struct that has a method with this name wins." Two structs with same-named methods collide → wrong `self` mutability used → silent miscompilation of borrow safety. Fix: thread `type_map` from pass 5 into the borrow checker, resolve method via receiver type.
- [x] **CB2** 🔴 **NLL is statement-of-current-block, not non-lexical** — `src/borrow.zig:64-80, 225-320`. `buildLastUseMap` records stmt indices relative to current block; recursing into nested blocks writes parent indices into the child's map. Borrows crossing block boundaries drop at wrong scopes. Fix: guard `dropExpiredBorrows` so it skips borrows whose `scope_depth < self.scope_depth` — outer-scope borrows are only expired by their own block's NLL pass. Regression test added.
- [x] **CB3** 🔴 **Generic type params detected via length≤4 uppercase heuristic** — `src/resolver.zig:712-724`. Any user struct named `Vec3`, `Iter`, `Cell`, `Node`, `List`, `Pair` silently classified as type parameter; `typesCompatible` returns true against anything → type checking silently disabled for short-uppercase-named types. Fix: tie type-param identity to binder (`func foo<T>`), introduce `.type_param` variant in `ResolvedType` with explicit binder reference.
- [x] **CB4** 🔴 **Propagation pass is value-flow blind** — `src/propagation.zig:128-197`. Only recurses into `.block`; unions returned from function calls inside if/match/for/while bodies are invisible. Assignment tracking only handles bare-identifier RHS. "All errors must be handled" guarantee is mostly aspirational once code nests. Fix: recurse `checkNode` over all statement-bearing variants; treat any subexpression yielding a union as creating a tracked temporary.
- [x] **CB5** 🔴 **Interface hash silently truncates at 256 symbols** — `src/cache.zig:407-414, 435-441, 471-477`. `[256][]const u8` fixed buffer drops symbols past cap → different interfaces hash equal → incremental cache skips rebuilds that should happen → stale binaries passing tests. Fix: replace `NameBuf` with `ArrayListUnmanaged([]const u8)`, no cap.
- [x] **CB6** 🔴 **Parser bails on first error; no recovery** — `src/peg/engine.zig`, `src/main.zig:130-136`. First PEG mismatch aborts the whole pipeline. Must land before or as part of Phase A so the new `AstStore` builder isn't baked with the old assumption. Fix: add `^sync` markers to `orhon.peg` at `func_decl`/`struct_decl`/statement boundaries; engine skips to next sync on failure, records diagnostic, resumes.
- [x] **CB-verify** Add regression tests for each CB# fix under `test/fixtures/` (one minimal repro per bug, assert the fix holds).

---

## Phase R — Architecture Rebuild (Index-Based SoA) `3-6 weeks` `DONE ✓`

Full rebuild of parser/AST and MIR storage from pointer-based trees to index-based struct-of-arrays. See [`docs/superpowers/specs/2026-04-14-orhon-arch-rebuild-design.md`](superpowers/specs/2026-04-14-orhon-arch-rebuild-design.md) for full design.

**Blockers:** Phase 0 must be complete before Phase A starts.
**Scope:** each chunk is one commit, `./testall.sh` green at every boundary.
**Bundled audit items:** H3a (source spans) lands in A8; H4d (golden files) expanded in D3.

### Phase A — Parser / AST rebuild `DONE` ✓ merged 2026-04-16, tagged `phase-a-complete`

- [x] **A1** Land `StringPool` utility with interning + tests
- [x] **A2** Scaffold `AstStore` types, `extraData` / `appendExtra` helpers, no population
- [x] **A3** Create `ast_typed.zig` — typed wrapper struct per `AstKind` with pack/unpack round-trip tests
- [x] **A4** PEG builder dual output — `src/peg/builder.zig` produces `AstStore` alongside `*parser.Node` tree, parity harness
- [x] **A5** Migrate `src/resolver.zig` to read `AstStore` (bridge via `reverse_map`)
- [x] **A6** Migrate `src/propagation.zig` to read `AstStore`
- [x] **A7** Migrate `src/declarations.zig` to read `AstStore`
- [x] **A8** Centralize `nodeLocFromIdx` in `SemanticContext` — source location resolution via `AstNodeIndex`
- [x] **A9** MIR temporary adapter — `MirAnnotator` + `MirLowerer` entry points read `AstStore`, internal `*parser.Node` bridge remains
- [x] **A10** Drop dual output — remove `buildASTWithStore`/`DualBuildResult` + parity harness
- [ ] **A11** Delete old pointer-based `parser.Node` type entirely — **deferred to Phase C** (codegen, borrow/ownership checkers, module system still depend on it)
- [x] **A12** Phase A merge — `testall.sh` green (361/361), merged to main, tagged `phase-a-complete`

### Phase B — MIR rebuild `1-2 weeks`

- [x] **B1** Land `TypeStore` with `TypeId` interning + tests — `src/type_store.zig`; 8 tests covering round-trip, dedup, named/primitive/special/slice/generic; 361/361 testall green
- [x] **B2** Scaffold `MirStore` types, helpers, no population — `src/mir_store.zig`; `MirNodeIndex`, `MirExtraIndex`, `MirEntry`, `MirData`, `MirStore` with `TypeStore`+`StringPool`; 7 tests; 361/361 green
- [x] **B3** Create `mir_typed.zig` — typed wrapper per `MirKind` with pack/unpack round-trip tests — all 32 MirKind variants covered; 12 tests one per data shape; 361/361 green
- [x] **B4** `MirBuilder` skeleton with fusion + internal phase separation (`classifyNode`, `inferCoercion`, `lowerNode`), emits `passthrough` only
- [x] **B5** Populate declarations cluster
- [x] **B6** Populate statements cluster
- [x] **B7** Populate expressions cluster
- [x] **B8** Populate types + members + injected
- [x] **B9** Delete parity harness — `MirBuilder` is the sole producer
- [x] **B10** Delete `MirAnnotator`, `MirAnnotator_nodes`, `MirLowerer`, old `MirNode`, `NodeMap`
  - Phase C progress (C1–C6 complete): all codegen signatures migrated to MirNodeIndex; bridge infra with synthetic fallback for nodes not yet in MirStore. B10 can now proceed.
- [x] **B11** Phase B merge — final `testall.sh`, merge to main, tag

### Phase B — pre-flight hygiene

Small items from the 2026-04-16 readiness audit. Do before or alongside B1.

- [x] **BH1** Add "pre-rebuild architecture" caveat banner to top of `docs/COMPILER.md` — the pipeline diagram is stale post-Phase A (no `AstStore`; still shows `*parser.Node` end-to-end). Full rewrite stays at D5; this is a signpost so readers don't treat the current doc as current.
- [x] **BH2** Audit codegen child access — 30 `.children[` accesses in 4 codegen files (`codegen.zig`×1, `codegen_decls.zig`×9, `codegen_stmts.zig`×2, `codegen_exprs.zig`×18); 19 more in `mir_node.zig`+`mir_lowerer.zig`. Scope is mechanical (~50 call sites across 6 files) — confirmed manageable at B9/B10.
- [x] **BH3** Baseline MirNode peak memory on Tamga (40 generated Zig files, full pipeline): **226 MB peak RSS** (2.83 s wall time). Orhon pipeline completes; Zig subprocess exits 1 on missing system headers (SDL3/Vulkan), so the number cleanly reflects MirNode + all passes 1–10.

### Phase B — risks to watch

Invariants to preserve during fusion. Tracked from the 2026-04-16 readiness audit; not blockers, but each one is a silent-miscompile risk if missed.

- [ ] **BR1** `MirNode.ast` back-pointer lifetime — `AstStore` must outlive `MirStore`. Already true (AstStore lives for the whole compilation per design). Document the contract explicitly in the `MirStore` scaffold at B2 so nothing in B5–B8 accidentally frees the AST early.
- [ ] **BR2** `var_types` two-layer fallback — `MirLowerer.resolveSourceUnionRT()` (`src/mir/mir_lowerer.zig:546`) falls back to `var_types` when a narrowed MirNode type hides the source union. Fused `MirBuilder` must copy `var_types` into builder state or the lookup silently returns the wrong union shape.
- [ ] **BR3** Interpolation counter threading — `interp_counter: u32` mutates during lowering. Thread through fused phases or refactor to a per-block counter. Aligns with P7's broader `pre_stmts` discipline — assert empty at function boundary.
- [ ] **BR4** Classify → coerce → lower ordering inside `MirBuilder` — narrowing extraction reads classification output; union-tag stamping runs after classification. Keep explicit internal phase separation (`classifyNode` / `inferCoercion` / `lowerNode`) in the fused builder to prevent invariant loss at B4.

### Phase C — Codegen migration `0.5-1 week`

> **Phase C complete (2026-04-19)** — all codegen signatures migrated to MirNodeIndex; 361/361 green.
> **Phase B complete (2026-04-19)** — MIR rebuild done; old infra deleted; 361/361 green on main.

**C-prep — semantic completion (do before C1):**
- [x] **CP1** Add `coercion_kind: u8` to `MirEntry` in `src/mir_store.zig`; add `coercionFromKind`/`coercionToKind` helpers + round-trip tests
- [x] **CP2** Implement `inferCoercion` in `src/mir_builder.zig` by porting from `src/mir/mir_annotator_nodes.zig`; update all `appendNode` call sites in builder satellites
- [x] **CP3** Extend `IfStmt.Record` in `src/mir_typed.zig` with `narrowing_extra: MirExtraIndex`; add `IfNarrowingExtra` + `NarrowBranchExtra` records
- [x] **CP4** Implement narrowing detection in `src/mir_builder_stmts.zig` `lowerIfStmt`, porting from `src/mir/mir_annotator_nodes.zig`
- [x] **CP5** Fix `mir_builder.build()` to iterate all top-level decls (program root was passthrough, MirStore was never populated); fix 3 latent sentinel/assert bugs exposed

**C1–C6 — codegen migration (one commit each, `testall.sh` green after each):**
- [x] **C1** `src/codegen/codegen.zig` — add `mir_store`, `mir_root_idx`, `mir_type_store`, `mir_builder_var_types` fields; `span_to_mir` reverse map; wire new fields from pipeline alongside old compat wiring
- [x] **C1b** `src/codegen/codegen.zig` + `src/mir_builder.zig` — `build()` returns Block (top-level list); `generate()` iterates from MirStore via span→old-MirNode bridge; `mir_typed` import added
- [x] **C2** `src/codegen/codegen_decls.zig` — all signatures migrated to MirNodeIndex + bridge
- [x] **C3** `src/codegen/codegen_exprs.zig` — all signatures migrated to MirNodeIndex + bridge
- [x] **C4** `src/codegen/codegen_stmts.zig` — all signatures migrated to MirNodeIndex + bridge
- [x] **C5** `src/codegen/codegen_match.zig` — all signatures migrated to MirNodeIndex + bridge
- [x] **C6** bridge infra in codegen.zig: synth fallback maps for nodes not in MirStore; 361/361 green
- [x] **C7** Phase C merge — 361/361 green, committed 2026-04-19 (v0.51.8)
> - `m.union_tag` on Binary nodes → MirStore Binary has no union_tag; must compute from var_types at call site

> **Phase D complete** (v0.53.0, 2026-04-20, 367/367 green). Phase 1 (Semantic Layer Cleanup) is next.

> Phase 1 complete (S6 done, v0.53.6, 2026-04-24). Phase 2 started.

### Phase D — Cleanup `0.5 week`

- [x] **D1** `AstStore` pretty-printer + debug dump
- [x] **D2** `MirStore` pretty-printer + debug dump
- [x] **D3** Golden-file fixtures for canonical `.orh` inputs (one `.ast.golden` + `.mir.golden` per fixture). **Bundle H4d here:** expand coverage to one snapshot per language feature category (~20 files covering compt, blueprints, generics, handles, interpolation, slicing, defer, ownership-edge, borrow-edge).
- [x] **D4** Dead code sweep (grep for removed types, delete orphaned helpers)
- [x] **D5** Update `docs/COMPILER.md` to reflect new architecture (also fixes F20 stale pipeline diagram)
- [x] **D6** Update this file — close obsolete entries, mark newly unblocked projects
- [x] **D7** Version bump, final `testall.sh`, merge

### Cross-phase invariants

- `./testall.sh` green at every commit
- One phase merged before next starts
- Incremental cache format NOT changed (avoid on-disk compatibility pressure)
- No MIR serialization work during the rebuild
- Branch per phase; PR + review before merge

### Unblocked by this project (future work)

- MIR serialization / incremental cache at MIR level
- Second backend (LLVM, C, native, WASM)
- MIR-level optimization passes (dead narrowing, match reachability, constant folding)
- SSA layer (`OrhonAir`) on same primitives
- Parallel compilation (prerequisite for Phase 3)
- Fast LSP with feature-gated passes (prerequisite for Phase 3)
- **Watch mode / continuous compile loop** — not currently tracked or scaffolded in `pipeline.zig`. Depends on P1 (`ModuleCompile` struct) so a single changed module can be re-compiled in isolation. File as a future project after Phase 3 completes.

---

## Phase 1 — Semantic Layer Cleanup `~2-3 weeks` `POST-REBUILD`

**Blockers:** Phase R must be complete. AST/MIR indices make the symbol table rewrite substantially easier.
**Internal ordering:** S1 (easy win, reduces noise) → S2 (Symbols) → S3 (resolver split, needs S2) → S4 (stateless, needs S3) → S5 (shadowing, independent) → S6 (type param model, needs S2).

- [x] **S1** 🟠 **Fold `K.Type.*` stringly-typed special types into `Primitive` enum** [H1c] — 88 `std.mem.eql` compares across 27 files for `ERROR`, `NULL`, `ANY`, `THIS`. Centralize in `types.Primitive` so every codegen site goes through `Primitive.fromName(s) → enum`, then single `switch` per emission point.
- [x] **S2** 🟠 **Replace `DeclTable`'s 7 parallel StringHashMaps with a unified `Symbols` table** [H1a, absorbs existing "DeclTable 7 maps" item] — `src/declarations.zig:84-193`. Every consumer re-glues the 7-way split (`hasDecl`, `validateType`, cross-module hint loops are O(modules × kinds × decls)). Replace with `StringHashMap(Symbol)` over a `SymbolKind` tagged union. Cross-module resolution becomes one hashmap lookup.
- [x] **S3** 🟠 **Split `resolver.zig` along pass 4/5 boundary** [H1b, absorbs existing item] — done 2026-04-24 — 2038 lines mixing declaration registration, type resolution, expression checking, scoping in one file. `var_decl` case does four passes worth of work. Split into (a) `Symbols` builder (extend DeclCollector from S2), (b) `TypeChecker` that walks expressions and produces `type_map`, (c) `Validator` for shadowing/exhaustiveness/reservedness.
- [x] **S4** 🟠 **Stateless resolver via `ResolveCtx` passed down** [H1e] — done v0.53.4, 2026-04-24 — `current_node`, `param_names`, `in_is_condition`, `loop_depth`, `type_decl_depth`, `current_return_type`, `in_generic_struct`, `in_anytype_arg` were mutable per-instance fields on `TypeResolver`. Blocks per-function/per-module parallelism. Packed into `ResolveCtx` value passed by copy down recursion.
- [x] **S5** 🟠 **Uniform shadowing detection for every binder** [H1d] — done v0.53.5, 2026-04-24 — `var_decl` and `destruct_decl` checked shadowing; function params, for captures, match arm bindings didn't. Added `is_func_root: bool` scope marker; single `defineUnique(scope, name, loc)` helper every binder calls.
- [x] **S6** 🟠 **Real type parameter binder model** [H1f, requires CB3 already landed] — done v0.53.6, 2026-04-24 — `ResolvedType` gains `.type_param` variant with explicit binder reference. Foundation for future constraint checks (`T: Eq`), better generic error messages, and explicit instantiation tracking. HKT remains out of scope.

---

## Phase 2 — Diagnostics + Testing Overhaul `~2 weeks` `POST-REBUILD`

**Blockers:** Phase R (Phase A delivers source spans via A8). Can overlap with Phase 1.
**Internal ordering:** T1 → T2 (T2 needs T1), T3 in parallel, T4 needs T3 landed, T5 uses T3+T4.
**Grouping rationale:** reporter rewrite and test runner rewrite are interdependent — tests want to assert on error codes, codes need the reporter to emit them.

### Sub-project 2a — Reporter rewrite

- [x] **T1** 🟠 **Error code catalog (`src/error_codes.zig`)** [H3b / F3] — done v0.53.7, 2026-04-25 — `ErrorCode enum(u16)` with 102 stable codes; `OrhonError.code: ?ErrorCode`; `reportFmt`/`warnFmt` require code first arg; `printDiagnostic` shows `[Exxxx]`; all ~110 call sites annotated.
- [x] **T2** 🟠 **JSON / machine-readable diagnostic output** [H3c / F4] — done v0.53.8, 2026-04-25 — `src/diag_format.zig` satellite; `DiagFormat enum { human, json, short }`; `Reporter.diag_format` field (default `.human`); `flush()` dispatches to `flushHuman/flushJson/flushShort`; `--diag-format=` CLI flag; 4 unit tests.

- [x] **T3** 🟡 **`NO_COLOR` / TTY detection + `--color=auto|always|never`** [H3d / F5] — done v0.53.10, 2026-04-25 — `ColorMode` enum + `detectColor()` in `errors.zig`; `use_color: bool` on `Reporter`; `esc()` helper gates all ANSI in `diag_format.zig`; `--color=auto|always|never` CLI flag; 2 unit tests.

- [x] **T4** 🟡 **Warning gradient with notes** [F8] — done v0.53.11, 2026-04-25 — `Severity = .err | .warning | .note | .hint`; unified flat `diagnostics` list; `report()`/`warn()` return `!u32` index; `note()`/`noteFmt()` with explicit parent index; `-Werror` CLI flag; `hasErrors()` respects `werror`; human/JSON/short renderers updated; `lsp_analysis.zig` migrated; 4 unit tests.

- [x] **T5** 🟡 **Fix reporter ownership convention** [F7] — done v0.53.12, 2026-04-25 — Added `storeDiagOwned` (no-dupe internal path) + public `reportOwned`; `reportFmt`/`warnFmt`/`noteFmt` now use owned path (single allocation, no defer free). Migrated 2 manual `allocPrint`+`report`+`defer free` sites (`module_parse.zig`, `zig_runner.zig`) to `reportOwned`. Contract: `report`/`warn`/`note` dupe (safe for string literals); `reportOwned` takes ownership (message must be from `reporter.allocator`); `reportFmt`/`warnFmt`/`noteFmt` allocate once internally.

- [x] **T6** 🟡 **Cache source file contents in reporter** [F6] — done v0.53.13, 2026-04-25 — `source_cache: StringHashMapUnmanaged([]const u8)` on `Reporter`; `getSourceLine` reads + caches file content on first access, returns slice into cached data (no static buffer, no page_allocator per diagnostic); `flush`/`flushHuman`/`printDiagnostic` take `*Reporter`; `deinit` frees cache; old `readSourceLine`/`copyToLineBuf`/`line_buf` removed from `diag_format.zig`.

- [x] **T7** 🟡 **Top-level `main()` ICE handler** [F24] — done v0.53.14, 2026-04-25 — `writeIceMessage` in `errors.zig`; pipeline `else` branch now prints "internal compiler error: {err}" + report URL + exits 70 instead of leaking Zig stack traces.

> **Session bookmark** (v0.53.49, 2026-05-02). M4 done — two-arena split in ModuleCompile + TypeResolver.scratch_arena. M1b/M1c/M2/M3/B1-B6 all done. Type alias chain resolution, scope rewrite, generic for-loop capture, and all review findings addressed.

### Sub-project 2b — Test runner rewrite

- [x] **T8** 🟠 **Zig-based test runner** [H4c / F14] — done v0.53.17, 2026-04-25 — `test/runner.zig` compiles each `fail_*.orh` fixture and matches `(code, line)` pairs from JSON diagnostics against `//> [Exxxx]` inline annotations; `zig build test-diag` step in `build.zig`; 38/38 enrolled fixtures pass, 22 unenrollable skipped; all corresponding `run_fixture` bash calls retired from `11_errors.sh`; `run_fixture` helper kept for 4 structural/warning-only fixtures.
- [x] **T9** 🟡 **Fixture reorganization** [F15] — subdirs `fixtures/parse/`, `fixtures/borrow/`, `fixtures/runtime/`, `fixtures/codegen/`. Per-fixture `.expect` sidecar with expected exit code, error codes, stderr snippets.
- [x] **T10** 🟡 **Expand snapshot coverage** — one snapshot per language feature category. Land on top of D3's golden-file infrastructure.
- [x] **T11** 🟡 **Perf baseline tests** [F17] — done v0.53.21, 2026-04-26 — `test/13_perf.sh` times `orhon build` for all 16 golden fixtures, appends results to `test/perf.log`, prints per-fixture wall-time deltas vs. previous run.
- [x] **T12** 🟡 **Property-based pipeline tests** — done v0.53.22, 2026-04-26 — `test/14_props.sh` checks `zig ast-check` validity and formatter idempotence across all 16 golden fixtures; wired into `testall.sh`.

---

## Phase 3 — Parallelism + LSP + Codegen Quality `~2-3 weeks` `POST-REBUILD`

**Blockers:** Phase R. Best after Phases 1 and 2 (stateless resolver from S4, per-module compile struct depends on it).
**Internal ordering:** P1 foundational → P2 and P3 both depend on P1 → P4-P7 independent, do in parallel.

### Sub-project 3a — Parallelism foundation

- [x] **P1** 🟠 **`ModuleCompile` struct with per-module arena** [H2d] — done v0.53.23, 2026-04-26 — `src/pipeline_context.zig` defines `BuildContext` (12-field shared-state bundle) and `ModuleCompile` (per-module arena + decl collector). `runPipeline` constructs an `ArrayList(ModuleCompile)` with capacity reserved up front; arenas live until end of build (decl tables remain valid for cross-module resolution via `all_module_decls`). 185-line per-module loop body extracted to `compileOne(ctx, mc) !void`; soft compile errors return `error.AbortBuild`. `runSemanticAndCodegen` collapsed from 13 params to 6. `decl_collector_ptrs` removed. Single-threaded execution preserved; structure parallelism-ready. Peak-memory split (iface vs body arena) deferred to M4.
- [x] **P2** 🟠 **Transitive cache invalidation** [H2e, absorbs existing "BuildGraph" item] — done v0.53.25, 2026-04-26 — `collectTransitiveDeps` computes full reachable-dep set per module once after `validateAndOrder`; `compileOne` updates `comp_cache.deps` from `mod_ptr.imports` each build (core bug: dep map was loaded but never written, so `dep_interface_changed` was always false); transitive closure replaces direct-dep check. `moduleNeedsRecompile` deleted. `writeZonCache` now writes `.tmp` then renames atomically. `dfsCircularCheck` records full DFS path and emits complete cycle string (e.g. `A → B → C → A`). Doc-comment exclusion from `hashSemanticContent` documented and proven safe (`.doc` field never read in codegen). Unit tests: diamond-graph deduplication, missing-dep skip, full cycle path, no-cycle baseline.
- [x] **P3** 🟠 **LSP reuses pipeline via `runPasses(stop_after:)` entry point** [H3e / existing "LSP feature-gated passes" and "LSP incremental sync" items] — `src/lsp/*` is 3500 lines re-implementing parsing. No feature gating, no cancellation, no debouncing. Fix: `Pipeline.runPasses(modules, stop_after: Pass)` entry point; LSP reuses the per-module compile struct from P1. Gate passes by request type: completion→1-4, hover→1-5, diagnostics→1-9.

### Sub-project 3b — Codegen quality

- [x] **P4** 🟠 **Rewrite `typeToZig` as pure function over `ResolvedType`** [H2a] — done v0.53.27, 2026-04-26 — `zigOfRT(ResolvedType)` replaces dual AST-walking paths; `binary_expr` branch deleted; `anyopaque` fallbacks replaced by internal error
- [x] **P5** 🟠 **Rewrite `checkUnusedImports` to use resolver data** [H2b] — done v0.53.28, 2026-04-26 — `TypeResolver.used_imports` set populated when identifier resolves as module name prefix; `checkUnusedImports` does set lookup instead of file I/O + substring search; moved to after pass 5 inside `runSemanticAndCodegen`
- [x] **P6** 🟠 **Source-location propagation from generated Zig to `.orh`** [H2c] — done v0.53.30, 2026-04-26 — all of `src/codegen/*.zig`. Zig errors currently show `.orh-cache/generated/foo.zig:412:9`; users reverse-map. Fix: populate `(generated_file, line) → (orh_file, line)` side-table during emit. `reformatZigErrors` becomes an exact lookup.
- [x] **P7** 🟠 **`pre_stmts` interpolation hoisting as stack of frames** [H2g] — done v0.53.31, 2026-04-26 — `pre_stmts: ArrayListUnmanaged(u8)` replaced with `pre_stmts_stack`; `pushPreStmtsFrame`/`popPreStmtsFrame`/`topPreStmts` helpers; statement loop pushes frame before each stmt + depth assertion; `generateInterpolatedStringMirFromStore` builds decl in local buffer with per-arg capture frames; manual save/restore in `generateBlockMir` and `emitNarrowedBlockFromStore` removed. Codegen is now ready for full `@{}` expression support (I1–I5).

---

## Phase 4 — CLI + Config + Stability `~1-2 weeks` `INDEPENDENT`

**Blockers:** none. Can run parallel to Phase R (touches entirely different files).
**Internal ordering:** X1 → X2-X6 in parallel.

- [x] **X1** 🟠 **Table-driven CLI parser** [H4a / F9] — done v0.53.32, 2026-04-27 — `FlagEffect` tagged-union + `FlagSpec`/`CommandSpec` comptime table; `applyFlag` centralizes all `CliArgs` mutations; `parseArgs` rewritten to ~85 lines. Flags normalized to single-dash space-separated (`-werror`, `-diag-format`, `-color`, `-line-length`). Undocumented `--version`/`--help`/`-addtopath` aliases dropped.
- [x] **X2** 🟠 **`orhon.project` manifest** [H4b / F10] — done v0.53.33, 2026-04-27 — `src/manifest.zig` with `ProjectManifest`/`ManifestTarget`; single-target (`#build` top-level) and multi-target (`#target name` sections); `#build`/`#version` in `.orh` files are hard errors (E1013); E1012 for missing manifest, E1014 for unknown keys; `orhon init` generates `orhon.project`; all test fixtures migrated (380/380 green).
- [x] **X3** 🟡 **`orhon init -update` migration** [F11] — done v0.53.35, 2026-04-27 — stamp file `.orh-cache/init.stamp` written by `orhon init` (inside project dir for both named and in-place); `orhon init -update` re-writes all 8 example files when stamp differs from running version; user files never touched; 390/390 green.
- [x] **X4** 🟡 **`orhon check` command** [F22] — done v0.53.34, 2026-04-27 — passes 1-8 only (no MIR/codegen/Zig invocation); fast path in `compileOne` + early return in `runPipeline`; `runSemanticOnly` in `pipeline_passes.zig`; 380/380 green.
- [x] **X5** 🟡 **Safer `addtopath`** [F21] — done v0.53.36, 2026-04-27 — `computeAddToPathContent` pure helper + `backupPath`; backup written before any edit; atomic tmp→rename write; `-dry-run` flag shows what would change without writing; already-in-PATH path honours dry-run; 5 unit tests; 392/392 green.
- [x] **X6** 🟡 **Versioning policy doc + CI workflow** — done v0.53.37, 2026-04-27 — `docs/versioning.md` defines pre-1.0 breaking-change policy; `.github/workflows/ci.yml` runs `./testall.sh` on push/PR to main via `mlugg/setup-zig@v1` + Zig 0.15.2.
- [x] **X7** 🟡 **Per-command help** — done v0.53.38, 2026-04-27 — `printCommandHelp` renders from `CommandSpec`; `-help` anywhere in args dispatches to it; `orhon help <cmd>` also works; hint line added to global `printHelp`; 392/392 green.

---

## Phase 5 — Medium/Low Cleanup Sweep `opportunistic` `ANY TIME POST-REBUILD`

No dependencies. Pick up items as time permits, in any order. Grouped by subsystem for scannability.

### String interpolation — full expression support `~2-3 days`

`@{...}` currently accepts only bare identifiers — the lexer emits the entire string as
one token, so the builder extracts expression text with a raw `}` scan and stores it as
`.identifier`. Supporting arbitrary expressions (`@{x + 1}`, `@{obj.field}`, `@{f(a, b)}`)
requires threading the full token stream through `@{...}`. Codegen (P7) is already ready.
**Internal ordering:** I1 → I2 → I3 → I4 → I5 (sequential dependency chain).

- [x] **I1** 🟠 **Lexer: sub-expression tokenization inside string literals** — done v0.53.39, 2026-04-27 — stateful `LexerMode` state machine (`.normal`/`.string_body`/`.string_interp{depth}`); `string_part`/`string_interp_start`/`string_interp_end` token kinds; `containsInterpolation()` fast-path check; `lexStringBody()`/`nextInInterp()` helpers; grammar rule `string_literal` extended with `STRING_INTERP_START (!STRING_INTERP_END .)* STRING_INTERP_END`; token_map updated; builder dispatches to I3 placeholder; 8 unit tests; 392/392 tests passing.
- [x] **I2** 🟡 **Grammar: update `string_literal` rule for interleaved tokens** — `src/peg/orhon.peg`. Replace `STRING_LITERAL` with a rule that matches `string_part* (@{ expr } string_part*)* string_end` using the new token types from I1.
- [x] **I3** 🟡 **PEG builder: emit real AST expression nodes from `buildStringLiteral`** — done v0.53.40 — `src/peg/builder_exprs.zig`. Deleted `buildInterpFromTokens` token-stream placeholder; `buildStringLiteral` now walks the capture tree's `interp_segment` children, calls `builder.buildNode` on expr sub-captures to produce real AST nodes per `@{...}` slot. 392/392 green.
- [x] **I4** 🟡 **MIR builder: lower arbitrary expression parts in interpolation** — `src/mir_builder_exprs.zig`. Interpolation parts are currently lowered as name lookups. With real AST nodes from I3, call `lowerNode` on each part expression instead — arbitrary expressions fold in naturally; type_class inference for format specifier selection (`{s}` vs `{}`) needs to handle any expression type.
- [x] **I5** 🟡 **Resolver: type-check expressions inside `@{}`** — `src/resolver_exprs.zig`. Interpolated string parts currently resolve as identifier lookups. With real expression nodes from I3, call `checkExpr` on each part — type errors inside `@{}` surface with proper locations. Add negative fixture `fail_interp_bad_expr.orh`.

### Semantic layer — medium

- [x] **M1** 🟡 **Type aliases resolve to `.inferred`** — Fixed. `collectVar` in `src/declarations.zig:474-484` extracts target name from identifier RHS and registers as `.type_alias`. `resolveTypeAnnotationInScope` in `src/resolver.zig:156-187` resolves `.type_alias` symbols to their target primitives or named types. Test fixtures: `fail_type_alias_mismatch.orh` (E2077), `fail_type_alias_struct_mismatch.orh` (E5005), `type_alias_basic.orh`. Limitation: local (function-scoped) type aliases still resolve to `.inferred` — deferred to follow-up.
- [x] **M1b** 🟢 **Type alias transitive chains single-hop only** — `A: type = B; B: type = i64` resolves `A` to `B` (not `i64`). `resolveTypeAnnotationInScope` stops at one level. Add loop in `resolveAliasTarget` or store resolved chain end in `type_alias` payload. — done v0.53.44, 2026-05-02 — `resolveNamedType` helper follows module-level `.type_alias` chains transitively (depth limit 32); `resolveTypeAnnotationInScope` and `resolveAliasTarget` updated; 3 test fixtures (runtime chain, negative mismatch, struct chain via tester framework)
- [x] **M1c** 🟢 **Duplicated `Primitive→RT` switch** — `resolver.zig:164-170` and `:271-276` have identical logic. Extract to a shared helper. — done v0.53.44, 2026-05-02 — extracted `ResolvedType.fromPrimitive()` shared helper; `classifyNamed` and `resolveNamedType` both delegate to it.
- [x] **M2** 🟡 **`inferCaptureType` limited to range/str/slice/array** — `src/resolver.zig:700-710`. Iterating a `List(T)` or `Map(K,V)` yields `.inferred` because those are `.generic`. Needs a generic-aware iterator protocol (depends on S6). — done v0.53.45, 2026-05-02 — `inferCaptureType`/`inferCaptureTypeIdx` now handle `.generic` types: returns first generic arg as element type (works for List(T), Set(T), Map(K,V), and any user-defined single-arg generic). No hardcoded stdlib names — follows zero-magic rule.
- [x] **M3** 🟡 **Scope is hashmap-per-frame with allocation per block** — done v0.53.46, 2026-05-02 — replaced per-frame `StringHashMap` + parent chain with single flat `ArrayList(Binding)` + `frames: ArrayList(FrameInfo)` start-index stack. New API: `pushFrame()`/`pushFuncFrame()`/`popFrame()`, `containsInCurrentFrame()`, `containsInEnclosingFrames()`, `currentFrameBindings()`, `isInsideFunction()`. All 6 consumer files updated (resolver.zig, resolver_stmts.zig, resolver_exprs.zig, propagation.zig, ownership.zig, ownership_checks.zig). 396/396 tests passing.
- [x] **M4** 🟡 **Type arena never freed mid-compile** — `src/declarations.zig:97`. Grows monotonically. Fix: split into permanent arena (types stored in DeclTable signatures) and scratch arena (expression-level temporaries, reset per function). — done v0.53.49, 2026-05-02 — `ModuleCompile` arena split into `iface_arena` (whole-build, holds DeclTable signatures) and `body_arena` (per-module scratch); `TypeResolver.scratch_arena` added for expression-level ResolvedType allocations; resolver satellites use `scratchAllocator()`.
- [ ] **M5** 🟡 **Linear scans in union helpers** — `src/types.zig:223-251`. `unionContainsError`, `unionContainsNull`, `unionInnerType`, `findDuplicateUnionMember` (O(n²)) called hot. Fix: store `is_error_union: bool` and `is_null_union: bool` on union variant at construction.
- [ ] **M6** 🟡 **`topologicalOrder` recursive DFS; single back-edge reported** — `src/module.zig:386-438`. Stack-overflow risk on adversarial inputs; bad cycle UX (prints `A → B` instead of `A → B → C → A`). Fix: iterative DFS with explicit stack, full cycle path recording.
- [ ] **M7** 🟡 **Cross-module "did you mean" loops are O(mod × kinds)** — `src/resolver_validation.zig:189-206`, mirrored in `src/resolver_exprs.zig:86-104`. Per unknown identifier. Fix: single global `name → (module, kind, is_pub)` reverse index built once after pass 4.
- [ ] **M8** 🟡 **`is_zig_module` path-based magic** — `src/declarations.zig:314, 365`, `src/resolver_validation.zig:166-169`, `src/pipeline_passes.zig:90-92`. Tests `std.mem.startsWith(u8, l.file, cache.ZIG_MODULES_DIR)`. Violates zero-magic rule loosely. Fix: explicit `Module.is_synthetic: bool` flag set at construction.

### Codegen layer — medium

- [ ] **M9** 🟡 **`codegen_match.zig` junk drawer split** [existing item, H2f, absorbed] — 1058 lines hosting match, intrinsics (`@cast`/`@overflow`/`@wrap`/`@sat`), interpolation, string matching. Split into `codegen_match.zig` (match only) + `codegen_intrinsics.zig` + `codegen_strings.zig`.
- [ ] **M10** 🟡 **`zig_runner_multi.zig` builds 700-line `build.zig` via `appendFmt`** — exactly the anti-pattern CLAUDE.md warns about. Literal `{`/`}` everywhere handled via `{{`/`}}` escaping, brittle. Cross-wire shared modules block at `:250-263` is O(N²) in shared module count. Additionally: `sorted_libs` topological sort silently emits the remainder "as-is" on a cycle (`:94-102`) instead of reporting an error; `lib_targets` map (`:54`) holds borrowed pointers aliasing `targets` with no lifetime documentation. Fix: `Writer` builder, no `appendFmt` of multiline strings; emit cross-wires only when `mod_imports` demand them; treat lib-graph cycle as a hard error with full cycle path; document `lib_targets` lifetime.
- [ ] **M11** 🟡 **Hardcoded type name strings in codegen** — `codegen.zig:586` (`K.Type.ERROR`→`anyerror`), `:613` (`"null"` compared as string), `:658` (`K.Type.VECTOR`→`@Vector`), `:587-592` (`THIS`/`SELF_DEPRECATED`→`@This()`). Folded into S1 long-term; short-term centralize in `types.Primitive`.
- [ ] **M12** 🟡 **Silent `else => "anyopaque"` fallbacks in `typeToZig`** — `src/codegen/codegen.zig:769, 710`. User-triggerable parser shape reaching unhandled type-node arm → silent `anyopaque` → confusing Zig error far from cause. Fix: replace with `reporter.report(...internal...)` and `error.CompileError`.
- [ ] **M13** 🟡 **`@panic` in `generateCompilerFuncMir`** — `src/codegen/codegen_match.zig:816`. Hard-crashes on malformed MIR. Fix: replace with internal-error report.
- [ ] **M14** 🟡 **Stdlib `.zig` import rewriting is text substitution** — `src/pipeline.zig:80-119`. Naive `@import("foo.zig")` → `"foo_zig"` replacement misses whitespace variations, multi-line imports. `readFileAlloc` per build even when nothing changed. Fix: structural rewrite via `zig_module.discoverAndConvert`'s AST output, cache-aware extraction.
- [ ] **M15** 🟡 **`init.zig` template list duplicated 3× with hardcoded count** — `src/init.zig:14-21, 75-84, 102`. Adding an example file touches two const blocks and a success-message count. Same pattern in `std_bundle.zig` ×30. Fix: comptime-walked tuple or `.{ name, content }` array.
- [ ] **M16** 🟡 **`writeZonCache` has no atomic rename** — `src/cache.zig:79-87`. Partial writes leave stale files. Fix: `tmp + rename` helper.
- [ ] **M17** 🟡 **Duplicate bootstrapping in `commands.zig`** — `runDebug` (`:96-143`), `runGendoc` (`:172-208`), `runPipeline`'s init phase, `lsp_analysis.zig`. ~80 lines of duplicated "set up reporter + resolver + scan" boilerplate. Fix: shared `bootstrapAnalysis(allocator) → struct { reporter, resolver }` helper.
- [ ] **M18** 🟡 **`readToEndAlloc(10MB)` for Zig subprocess stdout/stderr** — `src/zig_runner.zig:172-173`. Long Zig build hits OOM instead of graceful "build had a lot of output". Fix: streaming read or larger cap with explicit error.
- [ ] **M19** 🟡 **POSIX `STDOUT_FILENO` hardcoded** — `src/commands.zig:60-67` and similar. `File{ .handle = ... }` manual construction. Breaks Windows. Fix: `std.fs.File.stdout()`.
- [ ] **M19b** 🟡 **`orhon addtopath` is POSIX-only** — `src/commands.zig:addToPath`. Reads `$HOME` (not set on Windows; use `USERPROFILE`), reads `$SHELL` (no equivalent on Windows), emits `export PATH=...` (invalid in PowerShell/cmd), uses `:` as PATH separator (Windows uses `;`). On Windows the command will error or silently produce wrong output. Fix: detect `builtin.os.tag == .windows`, read `USERPROFILE`, emit `[System.Environment]::SetEnvironmentVariable(...)` for PowerShell or `setx PATH` for cmd; alternatively print a manual instruction and exit 0.
- [ ] **M20** 🟡 **Pipeline errors via `std.debug.print`** — `src/pipeline.zig:147-152`. Source-dir-not-found prints to stderr directly instead of `reporter.report`. Inconsistent error path.
- [ ] **M20b** 🟢 **`canonicalUnionRef` calls `typeToZig` twice per member** — once as sort key, once for output. Redundant work on every union emission. Trivially cacheable. Folds into P4 (`typeToZig` rewrite) naturally — will disappear when types are pre-lowered to `ResolvedType`.

### CLI / init / testing — medium-low

- [ ] **M21** 🟡 **`std_bundle` re-extracts 30 files on every build** [F13] — `src/std_bundle.zig:69-109`. Pollutes cache with files the user never imports. Embedded payload bloats orhon binary linearly with stdlib. Fix: lazy extraction driven by import graph; consider packed blob instead of 30× `@embedFile`.
- [ ] **M22** 🟢 **No verbosity / quiet flag** [F23] — `-q`, `-vv`, `ORHON_VERBOSE` env. Scripting/CI ergonomics.
- [ ] **M23** 🟢 **Hide `orhon analysis` from user help** [F18] — `src/cli.zig:243`. Developer-only debugging command listed alongside `build`/`run`/`test`. Move under `orhon -dev analysis` namespace.
- [ ] **M24** 🟢 **Stale doc: `orhon analysis` description** [F19] — `docs/13-build-cli.md:21` says "dump parse tree analysis" but actual command runs PEG grammar validation. Trivial fix.
- [ ] **M25** 🟢 **Clarify testing doc: user `test {}` blocks vs compiler test suite** [F25] — `docs/15-testing.md`. Conflates the two audiences.
- [ ] **M26** 🟢 **Dependency manager consideration** — not mentioned in `docs/future.md`. Will become urgent once external Orhon packages exist. Ties into X2 (`orhon.zon` manifest).
- [ ] **M27** 🟢 **Tree-sitter grammar** — listed `medium` in `docs/future.md`. Will become urgent once Orhon hits adoption (Neovim/Helix/Zed users demand it).
- [ ] **M28** 🟢 **Source mapping `.orh.map`** — mentioned in `docs/future.md` under "debugger integration" and "source mapping" but not tracked. Related to P6.

---

## Notes on absorbed items

These previously tracked items have been folded into audit-driven entries above:

| Old entry | Absorbed into |
|-----------|---------------|
| `MirNode` 20-field god struct | Resolved by Phase R (Phase B rebuild) |
| `DeclTable` 7 parallel StringHashMaps | S2 |
| `resolver.zig` 2038-line pass split | S3 |
| Implicit dep tracking / BuildGraph | P2 |
| `codegen_match.zig` junk drawer | M9 |
| LSP feature-gated passes | P3 |
| LSP incremental document sync | P3 |
| Property-based pipeline testing | T12 |

---

## Architectural Decisions (Settled)

| Decision | Rationale |
|----------|-----------|
| Fix bugs before architecture work | Correctness before performance/elegance |
| Pointers in std, not compiler | Borrows handle safe refs; std::ptr is the escape hatch |
| Transparent (structural) type aliases | `Speed == i32`, not a distinct nominal type |
| Allocator via `.withAlloc(alloc)`, not generic param | Keeps generics pure (types only) |
| SMP as default allocator | GeneralPurposeAllocator optimized for general use |
| Zig-as-module for Zig interop | `.zig` files auto-convert to Orhon modules |
| Explicit error propagation via `if/return` | No hidden control flow, no special keywords |
| Parenthesized guard syntax `(x if expr)` | Consistent with syntax containment rule |
| Hub + satellite split pattern | All large file splits use same pattern for consistency |
| `is` restricted to if/elif only | Narrowing only works in if/elif; `@typeOf` covers other contexts |
| `blueprint` for traits, not `impl` blocks | Everything visible at the definition site |
| No Zig IR layer in codegen | Direct string emission. MIR/SSA is the optimization target |
| Index-based SoA storage for parser and MIR | Future-proof, adopted from Zig's `Ast.zig` + Carbon's typed wrappers (Phase R) |

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
| Arena allocator pairing syntax | `.withAlloc(alloc)` already covers composed allocators via Zig module |
| `#derive` auto-generation | Blueprints require explicit implementation. No implicit anything |
| `#extern` / `#packed` struct layout | `.zig` modules already support these natively |
| `async` keyword | Wait for Zig's new async design, then map cleanly. `std::thread` + `thread.Atomic` covers parallelism |
| Compound `is` (`and`/`or`) | Narrowing can't handle multiple simultaneous type checks. Use nested ifs |
| `is` outside if/elif | `is` is a narrowing construct, not a general operator. Use `@typeOf` for type checks |
| `capture()` / closures | No anonymous functions. State passed as arguments — explicit, obvious |

## Bugs (encountered, deferred)

Bugs found during development that are confirmed but not yet fixed.

- [x] **B1** 🟡 **Local type alias constructor fails (Perms E2048)** — `const Perms: type = bitfield.Bitfield(...)` inside a `test` block, then `Perms{}` fails with `'Perms' is not callable`. `resolver_exprs.zig:316` only matches `.primitive == .@"type"` for constructor detection but local aliases resolve to `.named` via scope. Affects `src/templates/example/advanced.orh:209` and cascades to 30 `testall.sh` failures across stages 05-09. Introduced in commit `dec891d`. *(constructor path was already working pre-B2 fix — scope stores the declared type annotation .primitive == .@"type" which matches the check at resolver_exprs.zig:316)*
- [x] **B2** 🟡 **Local (function-scoped) type aliases resolve to `.inferred`** — `const Userid: type = i64` inside `main()` followed by `const id: Userid = "hello"` silently passes instead of emitting E2077. Module-level aliases work (fixed in M1); local alias resolution path is separate and returns `.inferred`. *Fixed 2026-05-02 — added local_type_aliases map to TypeResolver; resolveTypeAnnotationInScope now looks up target type for local .primitive == .@"type" aliases. Negative test: fail_local_type_alias_mismatch.orh.*
- [x] **B3** 🟡 **Silent cycle detection at depth limit 32** — `resolveNamedType` in `src/resolver.zig` silently returns `.named(name)` when the alias chain exceeds 32 hops (cyclic aliases). No diagnostic emitted, user gets confusing "unknown type" error elsewhere. From M1b review. Fix: emit `cyclic_type_alias = 2087` diagnostic. — done v0.53.48, 2026-05-02 — added E2087 diagnostic + guard for self-referencing sentinel.
- [x] **B4** 🟠 **`lookupPtr` pointer stability test fragile** — `src/scope.zig:207-224` obtains a pointer via `lookupPtr` then calls `define` which may reallocate the `vars` ArrayList, dangling the pointer. Test passes today but is implementation-dependent. From M3 review. Fix: ensure capacity before obtaining the pointer. — done v0.53.48, 2026-05-02 — added ensureTotalCapacity before lookupPtr.
- [x] **B5** 🟡 **`popFrame` silently ignores underflow** — `src/scope.zig:88-91` uses `self.frames.pop() orelse return` which silently swallows popFrame-on-empty-stack bugs instead of failing fast. From M3 review. Fix: `std.debug.assert(self.frames.items.len > 0)`. — done v0.53.48, 2026-05-02 — replaced orelse return with std.debug.assert.
- [x] **B6** 🟡 **`currentFrameBindings` returns raw slice without doc warning** — `src/scope.zig:137-138` returns `[]Binding` slice into internal `vars.items`. Subsequent `define`/`pushFrame`/`pushFuncFrame`/`popFrame` calls invalidate the slice, but caller has no documentation warning. From M3 review. Fix: add doc comment noting the lifetime constraint. — done v0.53.48, 2026-05-02 — added doc comment with lifetime warning.
