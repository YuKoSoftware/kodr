# Per-module `.zon` Build Config — Design Spec

## Goal

Replace `#cimport` with paired `.zon` files next to `.zig` modules for C build configuration. All C dependency information lives in the Zig ecosystem — no Orhon-side directives needed.

## Convention

```
src/
  mylib.zig       ← Zig module source
  mylib.zon       ← build config (optional, only if C deps exist)
```

Module name pairing: `mylib.zig` pairs with `mylib.zon`. No `.zon` = no C dependencies.

## Format

```zig
.{
    .link = .{ "SDL2", "openssl" },
    .include = .{ "vendor/" },
    .source = .{ "vendor/stb_image.c" },
    .define = .{ "SDL_MAIN_HANDLED" },
}
```

All fields are optional. Each field is a string tuple (`.{ "a", "b" }`).

### Fields

| Field | Purpose | build.zig call |
|-------|---------|---------------|
| `.link` | System libraries | `linkSystemLibrary("X")` |
| `.include` | Header search paths | `addIncludePath(b.path("X"))` |
| `.source` | C/C++ source files | `addCSourceFiles(.{ .files = &.{ "X" } })` |
| `.define` | Preprocessor macros | `addMacro("X", "1")` or `addMacro("K", "V")` for `K=V` format |

### Auto-detection

- Local `.c`/`.cpp`/`.cc`/`.cxx` files in the same directory as the `.zig` file are auto-detected and compiled without needing `.source`.
- `.cpp`/`.cc`/`.cxx` files auto-trigger `linkLibCpp()`.
- `.source` is only needed for C files in other directories.

### Define format

Simple defines: `.define = .{ "SDL_MAIN_HANDLED" }` → `-DSDL_MAIN_HANDLED`

Key-value defines: `.define = .{ "VERSION=2" }` → `-DVERSION=2`

Split on first `=`: everything before is the macro name, everything after is the value.

## Parsing

`.zon` files are valid Zig syntax. Parse with `std.zig.Ast.parse(allocator, source, .zon)`. Walk the root struct literal for known field names. Unknown fields are ignored (forward compatibility).

## Data flow

1. `zig_module.discoverAndConvert()` discovers `mylib.zig`
2. Check for `mylib.zon` in the same directory
3. If found, parse and extract `ZonConfig` struct: `link`, `include`, `source`, `define` slices
4. Auto-scan for adjacent `.c`/`.cpp` files, merge into `source`
5. Attach config to the module (new field on `ZigModuleEntry` or passed through pipeline)
6. Pipeline passes config to build.zig generator
7. `zig_runner_multi.zig` emits `linkSystemLibrary`, `addIncludePath`, `addCSourceFiles`, `addMacro` calls

## What gets removed

- `#cimport` grammar rule from `src/peg/orhon.peg`
- `cimport` metadata handling in `src/peg/builder_decls.zig`
- `cimport_include`, `cimport_source` fields from parser metadata node
- `#cimport` validation in `src/declarations.zig`
- `collectCimport` helper in `src/pipeline.zig`
- `#cimport` metadata extraction in single-target and multi-target build paths
- `cimport_registry` duplicate detection (`.zon` per-module makes duplicates impossible)

## What stays

- `@cImport`/`@cInclude` in the `.zig` file — that's Zig code, untouched
- The build.zig generation infrastructure in `zig_runner_multi.zig` — just changes input source

## Stdlib impact

Check which stdlib modules currently use `#cimport`. If any do (e.g., compression, crypto), their C config moves to a paired `.zon` file in `src/std/`.

## Error handling

- `.zon` parse failure → report error with file path and line
- Unknown field in `.zon` → silently ignore (forward compatibility)
- `.source` file not found → report error
- `.include` path not found → report error
- `.link` library not found → deferred to Zig compiler (link-time error)

## Testing

- Unit tests for `.zon` parsing in `zig_module.zig`
- Integration test: fixture with `.zig` + `.zon` + C source, verify compilation
- Negative test: malformed `.zon` gives clear error
- Verify existing `#cimport` tests are replaced or updated
