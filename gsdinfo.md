# Orhon Compiler & Tamga Framework — Project History and Reference

## Orhon Compiler

### Project Summary

Orhon is a compiled, memory-safe programming language that transpiles to Zig. Written in Zig 0.15.x, it targets developers who want Rust-level safety with Zig-level simplicity. The compiler implements a 12-pass pipeline from source to native binary, with ownership tracking, borrow checking, thread safety analysis, and incremental compilation.

**Current state (as of 2026-03-31):** v0.17 shipped, 277 tests across 11 stages, 8 milestones completed (36 phases, 50 plans).

### Milestone History

| Milestone | Theme | Shipped | Key Stats |
|-----------|-------|---------|-----------|
| v0.10 | Bug Fix & Cleanup | 2026-03-24 | Phases 1-7 |
| v0.11 | Language Simplification | 2026-03-25 | 4 phases, 35 files changed, +2812/-256 lines |
| v0.12 | Quality & Polish | 2026-03-25 | Phases 12-14; fuzz testing, test reliability |
| v0.13 | Tamga Compatibility | 2026-03-26 | Phases 15-18; enum values, type aliases, cross-module is |
| v0.14 | Build System | 2026-03-27 | Phases 19-21; named bridge modules, flexible allocators |
| v0.15 | Language Ergonomics | 2026-03-27 | Phases 22-24; throw, pattern guards, #cimport |
| v0.16 | Bug Fixes | 2026-03-28 | Phases 25-28; bridge codegen, build system, cross-compile |
| v0.17 | Codegen Refactor & Error Quality | 2026-03-29 | 8 phases, 139 files, +28519/-14516, 119 commits |

### What Each Milestone Accomplished

**v0.10 — Bug Fix & Cleanup**
- Cross-module const & argument passing in codegen
- Qualified generic type validation across modules
- Const struct by-value passing without false move errors
- Working `orhon test` command
- String interpolation temp buffer cleanup via MIR defer injection
- OOM error propagation in codegen (eliminated `catch unreachable` on allocPrint)
- Stdlib `catch {}` sweep: 103 instances classified and fixed/documented
- `Ptr(T).cast(addr)` method-style pointer constructors
- LSP per-request arena memory, header buffer hardening, content-length guard

**v0.11 — Language Simplification**
- Const auto-borrow: `const` non-primitive values auto-pass as `const &` at call sites
- Ptr syntax simplified: `const p: Ptr(T) = &x` replaces verbose `.cast()`
- Old `Ptr(T).cast(&x)` and `Ptr(T, &x)` syntax removed with clear compile error
- `.Error` fallback codegen fixed: correct Zig `if/else` pattern instead of `catch`

**v0.12 — Quality & Polish**
- Fuzz testing for lexer and parser using `std.testing.fuzz`
- Standalone fuzz harness with 5 strategies
- Tester module cross-module codegen fix
- Intermittent unit test failure fix (std.testing.tmpDir)

**v0.13 — Tamga Compatibility**
- Enum variants with explicit integer values (`A = 4` in typed enums)
- `is` operator with module-qualified types (`ev is mod.Type`)
- `void` accepted in error unions (`Error | void`)
- `const Alias: type = T` type alias syntax (transparent/structural, not nominal)

**v0.14 — Build System**
- Bridge .zig files as named Zig modules (createModule/addImport)
- 9 compiler bugs fixed for Tamga end-to-end build
- Flexible allocators: .new(alloc) with 3 modes (default SMP, inline, external)
- Shared @cImport wrapper modules for C/C++ source compilation

**v0.15 — Language Ergonomics**
- `throw x` keyword across all 7 compiler passes with error narrowing
- Pattern guards: `(x if x > 0) => { ... }` with parenthesized syntax
- Unified `#cimport = { name: "lib", include: "h" }` replacing 4 old directives

**v0.16 — Bug Fixes**
- `is_bridge` flag on FuncSig to prevent incorrect const auto-borrow on bridge calls
- Sidecar pub fixup via read-modify-write
- Unary negation in PEG grammar, cross-module `is` union tag comparison
- Build system fixes: infinite-loop pub-fixup scanner, cimport include paths, linkSystemLibrary
- Use-after-free on cross-compilation target flag, .zig-cache leak after optimized builds
- Dead `Async(T)` removed entirely

**v0.17 — Codegen Refactor & Error Quality**
- codegen.zig split from 4354-line monolith into 5 focused files (938-1082 lines each)
- "Did you mean?" typo suggestions using adaptive Levenshtein
- "Expected X, got Y" type mismatch display
- Ownership/borrow/thread fix hints in error messages
- PEG engine accumulates all expected tokens at furthest failure position
- lsp.zig split into 9 modules, mir.zig into 6, main.zig into 6, zig_runner into 4, builder into 6

### Quick Tasks (post-v0.17)

- Remove dead types (VersionRule, Dependency) from BUILTIN_TYPES
- Semantic token-stream hashing for incremental cache
- Interface diffing for incremental compilation
- Comma-separated library names in #cimport name field
- PEG labeled failures: 42 total rules annotated
- MIR residual AST audit: 4 migrated, 6 documented as permanent boundary
- Codegen snapshot tests: 4 fixture pairs, diff-based regression detection
- std::async bridge module: Atomic(T) wrapping std.atomic.Value(T)
- const& and mut& compound borrow tokens: lexer, PEG, AST rename, 38 files migrated
- Single-target bridge_mods scoping NOT implemented: direct-import approach breaks transitive bridge resolution

### Key Design Decisions

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
| 5-file codegen split (not 3-4) | Match/compiler-func section larger than estimated |
| Adaptive Levenshtein threshold | 1 for names <=4 chars, 2 for longer |
| Hub + satellite split pattern | All large file splits use same pattern |

### Deferred / Future Items

**Architecture:**
- Zig IR layer (split codegen into IR structs, lowering, printer)
- Dependency-parallel module compilation via thread pool
- MIR optimization passes (SSA, inlining, DCE, constant folding)
- MIR binary serialization and caching
- PEG syntax documentation auto-generator

**Language Features:**
- Blueprints / traits — struct Point: Eq {}, auto-derive + manual override, no impl blocks
- Non-lexical lifetimes (NLL) borrow checking — borrow ends at last use
- Closures
- Cross-module error context

**Future roadmap candidates (v0.18+):** compt introspection → blueprints → NLL

---

## Tamga Framework

### Project Summary

Tamga is a comprehensive collection of multimedia, gaming, and GUI libraries for the Orhon programming language. It sits above Orhon's standard library as the heavier, higher-level building blocks — windowing, rendering, audio, and GUI. Also serves as a primary stress test for the Orhon compiler.

Location: `/home/yunus/Projects/orhon/tamga_framework/`

### Current State

- Phase 1 (Platform Foundation / TamgaSDL3): COMPLETE
- Phase 2 (Vulkan 3D Renderer): 5 of 7 plans executed, stopped at textured lit mesh rendering
- Phases 3-5: Not started

### Architecture

Strict 4-layer dependency graph:

```
Layer 3: TamgaGUI | TamgaVK2D | TamgaVK3D   (high-level)
Layer 2: TamgaAudio | shared Vulkan types      (standalone)
Layer 1: TamgaSDL3                             (platform)
Layer 0: Zig bridge sidecars / SDL3 / Vulkan / stb / VMA  (native)
```

**Key invariant:** No module above the platform layer imports `tamga_sdl3` at the Orhon level. Renderers and GUI receive only an opaque `WindowHandle` (`Ptr(u8)` type alias).

| Module | Type | Depends On |
|--------|------|-----------|
| `tamga_sdl3` | Platform bridge | C bridge only |
| `tamga_vk3d` | Vulkan 3D renderer | tamga_sdl3 (window handle only) |
| `tamga_vk2d` | Vulkan 2D renderer | tamga_sdl3 (window handle only) |
| `tamga_audio` | Audio playback | C bridge only (fully standalone) |
| `tamga_gui` | GUI library | tamga_vk2d (draw calls only) |

### Technology Stack

- **SDL3** (3.x): Window, input, event polling, Vulkan surface creation
- **Vulkan** (1.0 minimum): GPU rendering for both 2D and 3D
- **VMA** (Vulkan Memory Allocator 3.x): GPU memory suballocation
- **stb_image** (2.29+): PNG/JPG texture loading
- **stb_vorbis** (1.22+): OGG Vorbis decoding for music streaming
- **SPIR-V offline shaders**: GLSL compiled with `glslc` to `.spv` at build time

### Key Architecture Decisions

- **Opaque handle isolation:** Renderers receive `Ptr(u8)`, never import SDL3 directly
- **Bridge-thin, Orhon-fat:** Zig sidecars handle raw C interop only
- **Separate 2D and 3D renderers:** Each optimized for its domain, sibling modules
- **GUI emits draw calls to VK2D:** GUI never owns its own Vulkan pipeline
- **Audio callback architecture:** Mixer on audio thread, command queue from main thread
- **Stay on Vulkan 1.0 render passes** for VK2D (consistent with VK3D)
- **VMA extern fn pattern:** C++ header compiled in vma_impl.cpp, declared as extern fn in Zig sidecar
- **MSAA capped at 4x** cross-vendor
- **Descriptor set layout:** Set 0 = CameraUBO + LightUBO (per-frame), Set 1 = MaterialUBO + sampler2D (per-material), push constants = model matrix 64 bytes

### Phase Roadmap

1. **Platform Foundation (COMPLETE)** — TamgaSDL3 windowing, input, events, frame loop
2. **Vulkan 3D Renderer (IN PROGRESS)** — VMA, shaders, depth, pipeline, mesh, textures, materials, lighting, MSAA. Remaining: render graph, depth prepass, pipeline cache, debug geometry
3. **Audio (NOT STARTED)** — WAV SFX, OGG streaming, mixing, thread-safe callback
4. **Vulkan 2D Renderer (NOT STARTED)** — Sprite batching, font atlas, shapes, draw list API
5. **GUI Library (NOT STARTED)** — Immediate mode first, retained mode second, standalone-capable

### Research Gaps

- Font atlas strategy: Bitmap vs SDF (affects VK2D and GUI)
- Unified GUI API feasibility: retained-on-immediate depends on Orhon closure/generic support
- Sprite batching strategy: instanced rendering vs merged vertex buffer vs texture array

### Known Compiler Bugs Found During Tamga Development

- `(null | MultiUnion)` codegen broken — pollEvent uses NoEvent sentinel instead of null
- `cast(Enum, int)` codegen broken — scancode/button fields stay u32/u8
- Relative include paths in sidecar @cImport broken — extern fn used instead
- Auto-borrow failure on error-union return — value pass used for Texture in createMaterial
- 'size' is reserved keyword — use byte_size/byte_count as bridge parameter names
- VK3D Zig sidecar must import tamga_sdl3_bridge.zig (not tamga_sdl3.zig) for WindowHandle type identity

### Explicitly Out of Scope

OpenGL renderer, physics engine, ECS library, networking, game loop/scene tree, scripting/hot-reload, asset management/virtual FS, video playback, vendor-specific GPU optimizations, mesh/task shaders, raytraced shadows/GI, built-in deferred renderer, SDL_gpu, FMOD-style proprietary audio
