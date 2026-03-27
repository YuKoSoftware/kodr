# Phase 24: `#cimport` Unification - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the four separate C interop directives (`#linkC`, `#cInclude`, `#csource`, `#linkCpp`) with a single unified `#cimport` directive. One `#cimport` per C library across the entire project. Migrate the Tamga framework to the new syntax.

</domain>

<decisions>
## Implementation Decisions

### Deprecation Strategy
- **D-01:** Hard remove — old directives (`#linkC`, `#cInclude`, `#csource`, `#linkCpp`) become parse errors immediately. No deprecation warning period.

### Block Syntax
- **D-02:** Colon-suffix key format: `include: "...", source: "..."`
- **D-03:** Comma-separated entries only (no newline-as-separator)
- **D-04:** Multi-line blocks allowed (opening `{` on same line, entries on subsequent lines, closing `}` on its own line)
- **D-05:** Fixed keys only — `include` and `source`. Unknown keys produce a compile error.

### Include Requirement
- **D-06:** No auto-derive — `include:` is always required. Every `#cimport` must have at minimum `{ include: "..." }`. The bare `#cimport "lib"` form (no block) is invalid.

### Library Name
- **D-07:** The quoted name after `#cimport` is always required. It serves as both the linker name (`linkSystemLibrary`) and the identity key for project-wide deduplication. Source-only libraries (using `source:` without a system lib) still require the name for identity but skip the `linkSystemLibrary` call.

### Cross-Module Sharing
- **D-08:** One `#cimport` per library across the entire project — duplicates are compile errors (CIMP-03).
- **D-09:** Other modules access C types by `import`-ing the owning bridge module. No re-declaring `#cimport` for the same library.
- **D-10:** C types are transitively visible — importing a bridge module that declares `#cimport` gives access to the C types from that library. Matches current shared cImport module behavior.

### Claude's Discretion
- Implementation ordering of compiler passes (grammar, builder, declarations, main.zig metadata collection, zig_runner build.zig generation)
- How to detect source-only libraries vs system-linked libraries in zig_runner
- Test structure and organization

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Language Spec
- `docs/14-zig-bridge.md` — Bridge module system, C interop conventions
- `docs/11-modules.md` — Module system, import mechanics

### PEG Grammar
- `src/orhon.peg` — Current metadata grammar rules (lines 50-56), `#cimport` replaces lines 52-55

### Compiler Passes (C interop touchpoints)
- `src/peg/builder.zig` — `buildMetadata()` function (~line 439) parses metadata AST
- `src/declarations.zig` — `#linkC` bridge validation (~line 192), unit tests (~line 671)
- `src/main.zig` — Metadata collection loops for linkC/cInclude/csource/linkCpp (~line 1337+)
- `src/zig_runner.zig` — `MultiTarget` struct (line 905-911), `buildZigContent`/`buildZigContentMulti`, shared cImport generation (~line 799), artifact linking (~line 699+)
- `src/codegen.zig` — C header import emission (~line 460)

### Tamga (migration target)
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaSDL3/tamga_sdl3.orh`
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaVK3D/tamga_vk3d.orh`
- `/home/yunus/Projects/orhon/tamga_framework/src/TamgaVMA/tamga_vma.orh`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- PEG grammar `metadata_body` rule — extend with `cimport` variant, remove old 4 variants
- `buildMetadata()` in builder.zig — already handles metadata field+value, needs block parsing
- `MultiTarget` struct in zig_runner.zig — has `link_libs`, `c_includes`, `c_source_files`, `needs_cpp` fields that can be populated from `#cimport` instead of 4 separate metadata scans
- Shared cImport module generation (`generateSharedCImportFiles`) — stays as-is, just fed from `#cimport` data instead

### Established Patterns
- Metadata is parsed as `#field value` with field stored as string, value as AST node
- Main.zig collects metadata per-module with explicit string matching loops (`std.mem.eql(u8, meta.metadata.field, "linkC")`)
- zig_runner generates build.zig content via string emission (`buildZigContent`/`buildZigContentMulti`)

### Integration Points
- PEG grammar `metadata_body` rule — new `cimport` alternative
- Builder — new block parsing for `{ key: "value", ... }`
- Declarations — validation that `#cimport` appears only in bridge modules
- Main.zig — single collection loop replaces 4 separate loops
- zig_runner MultiTarget — populated from unified `#cimport` data
- Tamga `.orh` files — syntax migration

</code_context>

<specifics>
## Specific Ideas

### Tamga Migration Map

| Module | New syntax |
|--------|-----------|
| `tamga_sdl3` | `#cimport "SDL3" { include: "SDL3/SDL.h" }` |
| `tamga_vk3d` | `#cimport "vulkan" { include: "vulkan/vulkan.h" }` (gets SDL types via `import tamga_sdl3`) |
| `tamga_vma` | `#cimport "vma" { include: "vk_mem_alloc.h", source: "../../src/TamgaVMA/vma_impl.cpp" }` (gets Vulkan types via `import tamga_vk3d`) |

### Source-only detection
VMA has no system library — it's compiled from source. The presence of `source:` without a matching system lib means `linkSystemLibrary` is skipped but `addCSourceFiles` is emitted. C++ linking auto-detected from `.cpp`/`.cc`/`.cxx` extension.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 24-cimport-unification*
*Context gathered: 2026-03-27*
