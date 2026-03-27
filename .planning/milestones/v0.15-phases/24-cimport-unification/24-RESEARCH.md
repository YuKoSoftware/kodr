# Phase 24: `#cimport` Unification - Research

**Researched:** 2026-03-27
**Domain:** Orhon compiler — C interop directive replacement across PEG grammar, AST builder, declarations, main.zig metadata collection, zig_runner build generation, docs, and Tamga migration
**Confidence:** HIGH

## Summary

Phase 24 replaces four separate C interop metadata directives (`#linkC`, `#cInclude`, `#csource`, `#linkCpp`) with a single unified `#cimport "lib" { include: "...", source: "..." }` directive. All user decisions are locked and precise. The code changes are mechanical but touch six distinct compiler layers in a fixed dependency order: PEG grammar → AST builder → declarations validation → main.zig metadata collection (two separate code paths) → zig_runner build generation → docs and Tamga migration.

The existing infrastructure is well-suited for the change. `MultiTarget` struct already holds `link_libs`, `c_includes`, `c_source_files`, and `needs_cpp` fields — those just need to be populated from `#cimport` data instead of four separate scans. The shared `@cImport` module generation in `zig_runner.zig` (lines 799–847, 1062–1150) can remain unchanged; it consumes `c_includes` from `MultiTarget`, not the raw directives. The declarations validator for `#linkC` (lines 192–217 of `declarations.zig`) must be updated to validate `#cimport` instead.

One structural gap: the **single-target build path** (`main.zig` line 1631) currently calls `generateBuildZig()` which does NOT accept `c_includes`, `c_source_files`, or `needs_cpp` — only `link_libs`. This means the existing single-target path never wired `#cInclude`, `#csource`, or `#linkCpp` through to `buildZigContent()`. The `#cimport` phase must fix this gap: either add these parameters to `buildZigContent()` / `generateBuildZig()`, or (preferred) consolidate both paths to use `buildZigContentMulti()`. In practice, Tamga uses the multi-target path (multiple `#build = static` modules), so the gap may not surface there, but it should be fixed for correctness.

**Primary recommendation:** Implement in strict pass order — grammar first, then builder, then declarations, then main.zig (both paths), then zig_runner — with the Tamga migration and docs as the final wave.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Hard remove — old directives (`#linkC`, `#cInclude`, `#csource`, `#linkCpp`) become parse errors immediately. No deprecation warning period.
- **D-02:** Colon-suffix key format: `include: "...", source: "..."`
- **D-03:** Comma-separated entries only (no newline-as-separator)
- **D-04:** Multi-line blocks allowed (opening `{` on same line, entries on subsequent lines, closing `}` on its own line)
- **D-05:** Fixed keys only — `include` and `source`. Unknown keys produce a compile error.
- **D-06:** No auto-derive — `include:` is always required. Every `#cimport` must have at minimum `{ include: "..." }`. The bare `#cimport "lib"` form (no block) is invalid.
- **D-07:** The quoted name after `#cimport` is always required. It serves as both the linker name (`linkSystemLibrary`) and the identity key for project-wide deduplication. Source-only libraries (using `source:` without a system lib) still require the name for identity but skip the `linkSystemLibrary` call.
- **D-08:** One `#cimport` per library across the entire project — duplicates are compile errors (CIMP-03).
- **D-09:** Other modules access C types by `import`-ing the owning bridge module. No re-declaring `#cimport` for the same library.
- **D-10:** C types are transitively visible — importing a bridge module that declares `#cimport` gives access to the C types from that library. Matches current shared cImport module behavior.

### Claude's Discretion

- Implementation ordering of compiler passes (grammar, builder, declarations, main.zig metadata collection, zig_runner build.zig generation)
- How to detect source-only libraries vs system-linked libraries in zig_runner
- Test structure and organization

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CIMP-01 | `#cimport "lib"` directive replaces `#linkC`, `#cInclude`, `#csource`, `#linkCpp` | PEG grammar change in `metadata_body` rule; builder change in `buildMetadata()`; main.zig single and multi-target collection loops |
| CIMP-02 | Optional block syntax `#cimport "lib" { include: "...", source: "..." }` | New grammar alternative for block form; builder parses block children; new `CimportData` struct in `Metadata` node or a dedicated AST node variant |
| CIMP-03 | Duplicate `#cimport` for same library across project produces compile error | Duplicate detection at declarations pass (per-module) and/or at main.zig collection time (project-wide); a `StringHashMap` keyed by lib name works |
| CIMP-04 | Old directives removed or deprecated | Hard remove from PEG grammar (lines 52–55); remove from builder fallback; remove from declarations validation; remove from main.zig collection loops |
| CIMP-05 | Tamga framework migrated to `#cimport` syntax | Three `.orh` files: tamga_sdl3, tamga_vk3d, tamga_vma — exact new syntax in CONTEXT.md specifics |
| CIMP-06 | Example module and docs updated with `#cimport` usage | `docs/14-zig-bridge.md` rewrite of "Calling C Through Zig" section; `docs/11-modules.md` metadata directive list; example module new section on C interop |
</phase_requirements>

## Standard Stack

### Core (all Zig 0.15.2 stdlib — no external deps)
| Component | File | Purpose |
|-----------|------|---------|
| PEG Grammar | `src/orhon.peg` | Syntax definition — `metadata_body` rule, lines 50–56 |
| AST Builder | `src/peg/builder.zig` | `buildMetadata()` function ~line 439 |
| Declarations | `src/declarations.zig` | Bridge-presence validation ~line 192, unit tests ~line 671 |
| Main pipeline | `src/main.zig` | Metadata collection ~line 1337+ (multi-target) and ~line 1536+ (single-target) |
| Zig Runner | `src/zig_runner.zig` | `MultiTarget` struct line 900–912, `buildZigContent`, `buildZigContentMulti`, `generateSharedCImportFiles` |
| Parser types | `src/parser.zig` | `Metadata` struct definition ~line 163 |
| Docs | `docs/14-zig-bridge.md`, `docs/11-modules.md` | Must be updated |

## Architecture Patterns

### Established Metadata Pattern
Metadata nodes are parsed as `#field value` with `field` stored as a `[]const u8` and `value` as an `*Node`. The `Metadata` struct in `parser.zig` has `field`, `value`, and `extra` (`?*Node` used only for `#dep`).

For `#cimport`, `value` becomes the lib name string, and the block entries (`include:`, `source:`) need a home. Two options:

**Option A — Use existing `extra` field for the block (as a synthetic node):**
The block `{ include: "...", source: "..." }` is represented as two child nodes. Since `extra` is `?*Node`, attach a new synthetic node type that carries `include` and `source` as fields. This avoids changing the `Metadata` struct layout.

**Option B — Extend `Metadata` struct with new fields:**
Add `cimport_include: ?[]const u8` and `cimport_source: ?[]const u8` directly to the struct. Clean at the cost of a small struct change.

**Recommended: Option B.** The `Metadata` struct is only used for metadata nodes, the new fields are well-named, and all consumers just check `meta.metadata.field == "cimport"` then read `meta.metadata.cimport_include`. This avoids creating a new node type and keeps builder logic simple.

### CimportData Approach (alternative to Option B)
```zig
// src/parser.zig
pub const Metadata = struct {
    field: []const u8,
    value: *Node,
    extra: ?*Node = null,      // version node for #dep, null otherwise
    cimport_include: ?[]const u8 = null,  // include path from { include: "..." }
    cimport_source: ?[]const u8 = null,   // source file from { source: "..." }
};
```

### PEG Grammar Change

Current `metadata_body` (lines 50–56):
```peg
metadata_body
    <- 'dep' expr expr?                         # #dep "path" Version?
     / 'linkC' expr                             # #linkC "libname"
     / 'cInclude' expr                          # #cInclude "header.h"
     / 'csource' expr                           # #csource "file.cpp"
     / 'linkCpp'                                # #linkCpp (flag, no argument)
     / IDENTIFIER '=' expr                      # #field = value
```

Replacement:
```peg
metadata_body
    <- 'dep' expr expr?                         # #dep "path" Version?
     / 'cimport' expr cimport_block             # #cimport "lib" { include: "...", source?: "..." }
     / IDENTIFIER '=' expr                      # #field = value

cimport_block
    <- '{' _ cimport_entry (',' _ cimport_entry)* _ '}'

cimport_entry
    <- IDENTIFIER ':' _ expr
```

**Note on `top_level_start`:** The `#` token is already in the `top_level_start` lookahead set, so error recovery is unaffected by this change.

**Note on `cimport` keyword:** `cimport` must be added to `token_map.zig` `LITERAL_MAP` as a keyword token (consistent with how `linkC`, `cInclude`, etc. are handled). Verify the exact approach by checking whether existing metadata keywords are in `LITERAL_MAP` or matched as identifiers in the grammar.

### Builder Change

Current `buildMetadata()` (~line 439) reads `cap.children[0]` as the single value node. With `#cimport`, `cap.children[0]` is the lib name string and `cap.children[1..N]` are the block entries (identifier + string pairs from `cimport_entry`).

New `buildMetadata()` flow for `#cimport`:
```zig
if (std.mem.eql(u8, field, "cimport")) {
    // children[0] = lib name string literal
    // remaining children = cimport_entry captures (ident ":" string)
    const lib_name_node = try buildNode(ctx, &cap.children[0]);
    var include_val: ?[]const u8 = null;
    var source_val: ?[]const u8 = null;
    for (cap.children[1..]) |entry_cap| {
        // entry_cap has children: [ident, string]
        const key = tokenText(ctx, entry_cap.children[0].start_pos);
        const val_node = try buildNode(ctx, &entry_cap.children[1]);
        if (val_node.* == .string_literal) {
            const raw = val_node.string_literal;
            const unquoted = if (raw.len >= 2 and raw[0] == '"') raw[1..raw.len-1] else raw;
            if (std.mem.eql(u8, key, "include")) include_val = unquoted;
            if (std.mem.eql(u8, key, "source")) source_val = unquoted;
        }
        // Unknown key → report error
    }
    // Validate: include is required (D-06)
    // Store include_val + source_val in Metadata node
    return ctx.newNode(.{ .metadata = .{
        .field = "cimport",
        .value = lib_name_node,
        .cimport_include = include_val,
        .cimport_source = source_val,
    } });
}
```

### Declarations Validation Change

Current validation (`declarations.zig` ~line 192) checks for `#linkC` and requires bridge presence. Replace with `#cimport`:

```zig
// Replace:
if (std.mem.eql(u8, meta.metadata.field, "linkC")) { ... }
// With:
if (std.mem.eql(u8, meta.metadata.field, "cimport")) { ... }
```

The new validation must also check:
1. `#cimport` only in bridge modules (same rule as `#linkC`)
2. `include:` key is present (D-06) — but this may be better validated at build time (in builder or main.zig)

The existing unit test at line 671 ("declaration collector - #linkC without bridge is an error") must be updated to use `#cimport`.

### Main.zig Collection Loops

Both the **multi-target path** (lines 1337–1475) and **single-target path** (lines 1536–1631) must be updated.

**Multi-target replacement:** Replace four separate collection loops (linkC, cInclude, csource/linkCpp) with a single `#cimport` loop that populates `link_libs`, `c_includes`, `c_source_files`, and `needs_cpp` from the unified node. The lib name from `meta.metadata.value` goes into `link_libs` (unless source-only — see below). `meta.metadata.cimport_include` goes into `c_includes`. `meta.metadata.cimport_source` goes into `c_source_files` if present, triggering `needs_cpp` detection via extension.

**Source-only detection (Claude's discretion):** A library is source-only when its name does not correspond to a system library. Since `include:` is always required and `source:` is optional, the cleanest signal is: if `cimport_source` is set AND no system library is expected for this name. However, the compiler cannot know which names are system libraries and which are not — it just has the name string. The recommended approach: always call `linkSystemLibrary` for the lib name unless the lib name ends with `.a`/`.lib` or is explicitly a known non-system pattern. Per the Tamga example, `"vma"` has no system library — the user knows this. Document that if `linkSystemLibrary("vma")` fails, the user should use a placeholder or the build system will skip it. Actually, Zig's build system emits a hard error for unknown system libs.

**Better approach (from CONTEXT.md specifics):** Source-only = presence of `source:` without a real system lib. The compiler cannot detect this at parse time. The simplest implementation: always emit `linkSystemLibrary(lib_name)` — for VMA, the user must ensure it's available OR we need a way to suppress it. The CONTEXT.md says "The presence of `source:` without a matching system lib means `linkSystemLibrary` is skipped but `addCSourceFiles` is emitted." So the rule is: if `cimport_source` is set and the lib name matches no known system library... but the compiler cannot know that.

**Resolved approach:** Use an explicit signal: emit `linkSystemLibrary(lib_name)` always, BUT detect source-only by checking whether a system library with that name actually exists only at build time. The cleanest compiler-side rule: **skip `linkSystemLibrary` when `source:` is present and lib name contains no version separator (no `-` or `.`)**... This is ambiguous.

**Actual resolution (from Tamga analysis):** VMA uses `#cimport "vma" { include: "vk_mem_alloc.h", source: "..." }`. If `linkSystemLibrary("vma")` is emitted, the build fails. The user-facing contract from CONTEXT.md: "source-only libraries (using `source:` without a system lib) still require the name for identity but skip the `linkSystemLibrary` call." So the rule the compiler implements is: **if `cimport_source` is set, do NOT emit `linkSystemLibrary`**. The lib name is then only used for identity/deduplication.

This is a clean, unambiguous rule. Document it explicitly.

**Single-target path gap:** `generateBuildZig()` / `buildZigContent()` does NOT currently accept `c_includes`, `c_source_files`, or `needs_cpp`. The implementation must either:
- Add those parameters to `buildZigContent()` (more surgical)
- Consolidate single-target to use `buildZigContentMulti()` (bigger refactor, not in scope)

**Recommendation:** Add `c_includes: []const []const u8`, `c_source_files: []const []const u8`, `needs_cpp: bool` to `buildZigContent()` and `generateBuildZig()`. Wire them through `buildZigContentMulti` already handles this correctly.

### Duplicate Detection (CIMP-03)

The duplicate `#cimport` check spans the entire project, not just one module. Two modules declaring `#cimport "SDL3" { ... }` is an error.

Detection point: during the main.zig collection loop, maintain a `StringHashMap([]const u8)` mapping lib name → declaring module name. On duplicate, report an error citing both modules.

```zig
var cimport_registry = std.StringHashMapUnmanaged([]const u8){};
// On each #cimport found:
if (cimport_registry.get(lib_name)) |existing_module| {
    // error: duplicate #cimport "lib" — already declared in module X
} else {
    try cimport_registry.put(allocator, lib_name, module_name);
}
```

### Tamga Migration

Exact replacements (from CONTEXT.md):

| Module | Old | New |
|--------|-----|-----|
| `tamga_sdl3.orh` | `#linkC "SDL3"` | `#cimport "SDL3" { include: "SDL3/SDL.h" }` |
| `tamga_vk3d.orh` | `#linkC "vulkan"` + `#linkC "SDL3"` + `#cInclude "vulkan/vulkan.h"` | `#cimport "vulkan" { include: "vulkan/vulkan.h" }` (SDL types come via `import tamga_sdl3`) |
| `tamga_vma.orh` | `#linkC "vulkan"` + `#cInclude "vulkan/vulkan.h"` + `#csource "..."` + `#linkCpp` | `#cimport "vma" { include: "vk_mem_alloc.h", source: "../../src/TamgaVMA/vma_impl.cpp" }` (Vulkan types via `import tamga_vk3d`) |

**Cross-module type sharing still works:** tamga_vk3d currently declares `#linkC "SDL3"` redundantly. After migration, it drops that — SDL types arrive through `import tamga_sdl3`. This is the D-09 / D-10 mechanism and already works today via the existing shared cImport module generation.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Block parsing in builder | Manual token walking | Existing `cap.findChild()` / `cap.children` traversal pattern already used in `buildMetadata` and `buildFuncDecl` |
| Duplicate key detection in block | Custom nested loop | Simple `if (include_val != null)` guard before assignment |
| C++ auto-detection | New file extension logic | Existing extension check (`endsWith(".cpp")`, `endsWith(".cc")`) in main.zig lines 1452–1453 — reuse verbatim |
| cImport module naming | New stem derivation | Existing `generateSharedCImportFiles` stem logic (lines 815–825) — unchanged, consumes same `c_includes` slice |

## Common Pitfalls

### Pitfall 1: Grammar keyword vs. identifier
**What goes wrong:** The PEG engine matches `cimport` as an `IDENTIFIER` token if `cimport` is not in `token_map.zig` LITERAL_MAP, making the grammar rule for `'cimport'` match incorrectly.
**Why it happens:** Existing metadata keywords (`linkC`, `cInclude`, etc.) may or may not be in LITERAL_MAP — need to verify. Per CONTEXT.md decision note from Phase 22: "token_map.zig LITERAL_MAP: every new keyword token must have a string-to-TokenKind entry."
**How to avoid:** Add `"cimport"` to `LITERAL_MAP` in `src/peg/token_map.zig` as a new keyword token kind before touching the grammar.
**Warning signs:** Parser silently falls through to `IDENTIFIER '=' expr` alternative, emitting no error for missing `=`.

### Pitfall 2: Single-target path missing c_includes/c_sources
**What goes wrong:** `generateBuildZig()` does not accept `c_includes`, `c_source_files`, or `needs_cpp`. After migration, Tamga would compile (multi-target path) but a hypothetical single-module bridge would not emit the shared `@cImport` module in `build.zig`.
**Why it happens:** The single-target path was never updated when `#cInclude`/`#csource` were added to the multi-target path.
**How to avoid:** Extend `buildZigContent()` and `generateBuildZig()` signatures with the three new parameters, and wire them through the single-target collection loop.
**Warning signs:** Single-module bridge projects that use `#cimport` compile without the `@cImport` wrapper, causing "not found" errors in Zig sidecars.

### Pitfall 3: Tamga "SDL3" duplicate across modules
**What goes wrong:** After migration, tamga_sdl3 declares `#cimport "SDL3"` and tamga_vk3d still references SDL types. If tamga_vk3d attempts to also declare `#cimport "SDL3"`, the duplicate check fires.
**Why it happens:** The old code allowed multiple `#linkC "SDL3"` across modules.
**How to avoid:** tamga_vk3d must NOT re-declare `#cimport "SDL3"`. It already `import`s tamga_sdl3, which gives transitive access. The CONTEXT.md migration map already accounts for this.
**Warning signs:** Compiler error "duplicate #cimport SDL3" during Tamga build after migration.

### Pitfall 4: `include:` validation timing
**What goes wrong:** The builder parses `#cimport "lib" { source: "..." }` (missing `include:`) and stores `cimport_include = null`. Downstream code attempts `@cInclude(null)` or emits an empty `@cInclude("")`.
**Why it happens:** D-06 requires `include:` to always be present, but the builder may not enforce this.
**How to avoid:** In `buildMetadata()`, after parsing the block, check `include_val == null` and report a build error: "`#cimport` requires `include:` key". Report via the existing `reporter.report()` pattern.
**Warning signs:** Generated `_xxx_c.zig` contains `@cInclude("")`.

### Pitfall 5: Missing `extra` field re-use confusion
**What goes wrong:** The `Metadata` struct's `extra` field is `?*Node` and is currently used only for `#dep`. Someone might accidentally store block data in `extra` then break `#dep` processing.
**Why it happens:** Struct re-use confusion.
**How to avoid:** Use the new `cimport_include` / `cimport_source` fields (Option B) — do not touch `extra`. `#dep` processing is unaffected.
**Warning signs:** `#dep` processing errors after builder change.

## Code Examples

Verified from source code inspection:

### How existing `buildMetadata` reads children (builder.zig ~line 439)
```zig
// Source: src/peg/builder.zig
fn buildMetadata(ctx: *BuildContext, cap: *const CaptureNode) !*Node {
    const field_pos = cap.start_pos + 1; // after #
    const field = tokenText(ctx, field_pos);

    if (cap.children.len > 0) {
        const value = try buildNode(ctx, &cap.children[0]);
        var extra: ?*Node = null;
        if (cap.children.len > 1) {
            extra = try buildNode(ctx, &cap.children[1]);
        }
        return ctx.newNode(.{ .metadata = .{ .field = field, .value = value, .extra = extra } });
    }

    const dummy = try ctx.newNode(.{ .identifier = field });
    return ctx.newNode(.{ .metadata = .{ .field = field, .value = dummy } });
}
```

### How main.zig reads metadata for `#linkC` (pattern to replace)
```zig
// Source: src/main.zig ~line 1342
for (ast.program.metadata) |meta| {
    if (std.mem.eql(u8, meta.metadata.field, "linkC")) {
        if (meta.metadata.value.* == .string_literal) {
            const raw = meta.metadata.value.string_literal;
            const lib_name = if (raw.len >= 2 and raw[0] == '"')
                raw[1 .. raw.len - 1]
            else
                raw;
            try mt_link_libs.append(allocator, lib_name);
        }
    }
}
```

### How zig_runner generates shared @cImport file (stays unchanged)
```zig
// Source: src/zig_runner.zig ~line 831
const wrapper_content = try std.fmt.allocPrint(allocator,
    \\pub const c = @cImport({{
    \\    @cInclude("{s}");
    \\}});
    \\
, .{hdr});
// Written to _{stem}_c.zig; consumed by sidecars as: const c = @import("{stem}_c").c;
```

### MultiTarget struct (stays unchanged, populated from #cimport data)
```zig
// Source: src/zig_runner.zig ~line 900
pub const MultiTarget = struct {
    link_libs: []const []const u8 = &.{},        // lib name (skipped if source-only)
    c_includes: []const []const u8 = &.{},       // from cimport_include
    c_source_files: []const []const u8 = &.{},  // from cimport_source
    needs_cpp: bool = false,                      // auto-detected from .cpp/.cc extension
    // ...
};
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| `#linkC "lib"` + `#cInclude "h"` + `#csource "f"` + `#linkCpp` | `#cimport "lib" { include: "h", source: "f" }` | One directive = one C library dependency |
| Multiple `#linkC` allowed across modules | One `#cimport` per library project-wide | Enforces single-ownership, prevents C type duplication |

**Deprecated after this phase:**
- `#linkC`: hard removed from PEG grammar and all compiler passes
- `#cInclude`: hard removed
- `#csource`: hard removed
- `#linkCpp`: hard removed — C++ detection becomes automatic via `.cpp`/`.cc` extension on `source:` value

## Open Questions

1. **`cimport` as keyword vs. identifier in token_map.zig**
   - What we know: Phase 22 established that new keywords need a `LITERAL_MAP` entry in `token_map.zig`
   - What's unclear: Whether `linkC`, `cInclude`, etc. were proper keyword tokens or matched as identifiers — need to verify `token_map.zig` before writing the grammar rule
   - Recommendation: Read `src/peg/token_map.zig` at implementation start; add `kw_cimport` if consistent with how other metadata keywords are handled

2. **Single-target path consolidation vs. parameter extension**
   - What we know: `buildZigContent()` lacks c_includes/c_source/needs_cpp parameters; multi-target path has them
   - What's unclear: Whether full consolidation (single-target → use `buildZigContentMulti`) is safe without breaking single-module projects
   - Recommendation: Extend `buildZigContent()` with three new parameters (surgical, lower risk) rather than consolidating code paths

## Environment Availability

Step 2.6: SKIPPED — no external tool dependencies. All changes are source code edits in Zig and `.orh` files. Tamga libraries (SDL3, Vulkan, VMA) are runtime dependencies of the Tamga project, not the compiler itself.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig built-in test blocks + shell integration tests |
| Config file | none (zig build test runs all `test` blocks) |
| Quick run command | `zig build test` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CIMP-01 | `#cimport "lib" { include: "..." }` parses and populates `link_libs` + `c_includes` | unit | `zig build test` (declarations.zig + zig_runner.zig) | ❌ Wave 0 |
| CIMP-02 | Block form with both `include:` and `source:` populates all fields correctly | unit | `zig build test` | ❌ Wave 0 |
| CIMP-03 | Duplicate `#cimport` for same lib produces compile error | unit | `zig build test` | ❌ Wave 0 |
| CIMP-04 | Old directives `#linkC`/`#cInclude`/`#csource`/`#linkCpp` produce parse errors | integration | `test/11_errors.sh` | ❌ Wave 0 |
| CIMP-05 | Tamga builds successfully with new syntax | integration | manual Tamga build | ❌ Wave 0 |
| CIMP-06 | Example module and docs compile and contain `#cimport` | integration | `./testall.sh` (test 09) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `zig build test`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Unit test: `#cimport` parses and collects correctly — add to `declarations.zig` or a new test block
- [ ] Unit test: `buildZigContent()` emits correct `linkSystemLibrary` and `@cImport` wrapper when given cimport data
- [ ] Unit test: duplicate `#cimport` detection fires an error
- [ ] Fixture file: `test/fixtures/fail_old_linkc.orh` — contains `#linkC "SDL3"` to test parse error
- [ ] Shell test: `11_errors.sh` — add negative test verifying old directives are rejected

## Sources

### Primary (HIGH confidence)
- Direct inspection of `src/orhon.peg` lines 47–57 — current `metadata_body` grammar
- Direct inspection of `src/peg/builder.zig` lines 439–458 — `buildMetadata()` implementation
- Direct inspection of `src/declarations.zig` lines 192–217 — `#linkC` bridge validation
- Direct inspection of `src/declarations.zig` lines 671–704 — existing `#linkC` unit test
- Direct inspection of `src/main.zig` lines 1337–1475 — multi-target metadata collection
- Direct inspection of `src/main.zig` lines 1536–1631 — single-target metadata collection
- Direct inspection of `src/zig_runner.zig` lines 900–912 — `MultiTarget` struct
- Direct inspection of `src/zig_runner.zig` lines 799–848 — `generateSharedCImportFiles`
- Direct inspection of `src/zig_runner.zig` lines 437–485, 356–382 — `buildZigContent` / `generateBuildZig`
- Direct inspection of `src/zig_runner.zig` lines 1062–1150 — `buildZigContentMulti` cImport module logic
- Direct inspection of `src/parser.zig` lines 163–167 — `Metadata` struct
- Direct inspection of Tamga files: `tamga_sdl3.orh`, `tamga_vk3d.orh`, `tamga_vma.orh`
- Direct inspection of `docs/14-zig-bridge.md`, `docs/11-modules.md`
- Direct inspection of `test/11_errors.sh` — negative test patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all files read directly, no external sources needed
- Architecture: HIGH — implementation patterns traced through all six affected layers
- Pitfalls: HIGH — identified from actual code structure gaps (single-target path, duplicate detection timing, keyword token registration)

**Research date:** 2026-03-27
**Valid until:** Stable (compiler architecture changes rarely — valid until next milestone)
