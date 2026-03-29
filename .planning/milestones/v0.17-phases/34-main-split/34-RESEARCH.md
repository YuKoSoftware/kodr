# Phase 34: Main Split - Research

**Researched:** 2026-03-29
**Domain:** Zig module splitting / refactoring — `src/main.zig` decomposition
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Split by logical domain — each major responsibility area becomes its own file. `main.zig` keeps only: allocator setup, CLI args struct, `main()` entry point, and command dispatch.
- **D-02:** Flat naming pattern: `src/cli.zig`, `src/pipeline.zig`, `src/init.zig`, etc. (no subdirectory). Consistent with `src/codegen_*.zig`, `src/lsp_*.zig`, `src/mir_*.zig`.
- **D-03:** CLI parsing — `CliArgs`, `Command`, `BuildTarget`, `OptLevel`, `parseArgs()`, `printUsage()`, `printHelp()` move to a CLI module.
- **D-04:** Pipeline orchestration — `runPipeline()` and helpers (`collectBridgeNames`, per-module pass loop) move to a pipeline module. Largest chunk (~820 lines).
- **D-05:** Project init — `initProject()` and all `@embedFile` constants for templates move to an init module.
- **D-06:** Stdlib bundler — `ensureStdFiles()`, `writeStdFile()`, and all `@embedFile` constants for stdlib `.orh`/`.zig` pairs move to a stdlib bundler module.
- **D-07:** Interface generation — `generateInterface()`, `emitInterfaceDecl()`, `emitFuncSig()`, `formatType()`, `formatExprSimple()` move to an interface generation module.
- **D-08:** Command runners — `runAnalysis()`, `runDebug()`, `runGendoc()`, `emitZigProject()`, `moveArtifactsToSubfolder()`, `addToPath()` group with pipeline or get their own commands module. Planner decides based on coupling analysis.
- **D-09:** `@embedFile` constants move with their consumer function.
- **D-10:** Pass parameters explicitly — no wrapper struct.
- **D-11:** Pure refactor. No function signatures change, no behavior changes, no new features.
- **D-12:** Unit tests move to their new file locations.

### Claude's Discretion

- Exact file names (e.g., `cli.zig` vs `cli_args.zig`)
- Whether command runners (analysis, debug, gendoc) stay in pipeline or get a separate `commands.zig`
- Exact function-to-file assignments when used by multiple domains
- How `main.zig` imports and delegates to the split files

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPLIT-04 | main.zig split into 6+ files — CLI, pipeline, project init, stdlib bundler, interface gen, and slim dispatcher | Full function inventory below maps directly to 6 target files |
| SPLIT-02 | Zero behavior change gate — `./testall.sh` passes all tests before and after each split, unit tests work in new locations | re-export pattern + `pub const` aliases eliminates downstream changes; test suite checks behavior not source layout |
</phase_requirements>

---

## Summary

`src/main.zig` is a 2328-line file containing six distinct domains under one roof. The split follows the identical pattern established by Phases 29 (codegen), 32 (LSP), and 33 (MIR): extract each domain into a flat `src/*.zig` file, keep the original as a thin dispatcher with `pub const` re-exports, add new files to `build.zig`'s `test_files` array, and move unit tests to live with the code they test.

The critical difference from codegen (Phase 29) is that `main.zig` has **no central struct** — all functions are free-standing and take `allocator`, `cli`, and `reporter` as explicit parameters. This makes splitting straightforward: each target file is a plain collection of `pub fn` functions. No wrapper-stub pattern required.

The `collectCimport` anonymous struct (lines 1391-1447 inside `runPipeline`) is the only tricky piece — it is a local struct used only within `runPipeline` and should stay there or be extracted as a file-scoped helper inside `pipeline.zig`.

**Primary recommendation:** Split into exactly 6 files: `cli.zig`, `pipeline.zig`, `init.zig`, `std_bundle.zig`, `interface.zig`, and a `commands.zig` for the secondary command runners. main.zig becomes a ~115-line dispatcher. Each file stays well under 600 lines at current sizes.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Zig std | 0.15.x | All I/O, path, process, collections | Only dependency; no external packages |

### No New Dependencies

This is a pure file-splitting refactor. No new libraries are introduced.

---

## Architecture Patterns

### Recommended File Layout After Split

```
src/
├── main.zig           # ~115 lines: allocator, main(), command dispatch
├── cli.zig            # ~250 lines: Command, BuildTarget, OptLevel, CliArgs, parseArgs(), printUsage(), printHelp()
├── pipeline.zig       # ~820 lines: runPipeline(), collectBridgeNames()
├── commands.zig       # ~280 lines: runAnalysis(), runDebug(), runGendoc(), addToPath(), emitZigProject(), moveArtifactsToSubfolder()
├── init.zig           # ~110 lines: @embedFile constants for templates, initProject()
├── std_bundle.zig     # ~160 lines: @embedFile constants for std files, ensureStdFiles(), writeStdFile()
└── interface.zig      # ~320 lines: generateInterface(), emitInterfaceDecl(), emitFuncSig(), formatType(), formatExprSimple()
```

Estimated totals based on actual line ranges in the current file. All targets stay well under 600 lines.

### Pattern 1: pub fn re-export facade (from Phase 33)

main.zig imports the new modules and (if needed) re-exports key types for backward compatibility:

```zig
// main.zig
const _cli = @import("cli.zig");
const _pipeline = @import("pipeline.zig");
const _init = @import("init.zig");
const _std_bundle = @import("std_bundle.zig");
const _interface = @import("interface.zig");
const _commands = @import("commands.zig");

// Re-export types any tests or external code might reference
pub const CliArgs = _cli.CliArgs;
pub const Command = _cli.Command;
pub const BuildTarget = _cli.BuildTarget;
```

Since main.zig is the root source file and is not imported by other modules, re-exports are only needed for `zig build test` which compiles `src/main.zig` as a test root. The unit tests in main.zig reference `lexer`, `parser`, `mir`, `codegen`, etc. directly — those references stay wherever the tests are relocated.

### Pattern 2: Underscore-prefixed imports (Phase 33 lesson)

Use underscore-prefixed names when importing new files to avoid shadowing conflicts with local variables:

```zig
const _pipeline = @import("pipeline.zig");
const _cli = @import("cli.zig");
```

Local variables like `cli`, `pipeline` are common in this codebase. The underscore prefix avoids Zig shadowing errors discovered in Phase 33.

### Pattern 3: build.zig test_files array

Add each new file to the `test_files` array in `build.zig`. Current array contains 37 entries. New phase adds 6 entries:

```zig
"src/cli.zig",
"src/pipeline.zig",
"src/commands.zig",
"src/init.zig",
"src/std_bundle.zig",
"src/interface.zig",
```

Remove `"src/main.zig"` or keep it — it will contain the `pipeline - imports all passes` and `cli - build target names` tests which should move to `pipeline.zig` and `cli.zig` respectively. The `full pipeline - hello world`, `codegenSource` helper, and codegen tests should move to `pipeline.zig`.

### Pattern 4: @embedFile paths relative to source file

**Critical:** `@embedFile` paths are relative to the `.zig` file containing them — not to `src/main.zig`. When `initProject()` moves to `src/init.zig`, the embed paths `"templates/main.orh"` and `"templates/example/example.orh"` remain valid because `init.zig` lives in the same `src/` directory.

Similarly, stdlib embeds like `"std/collections.orh"` remain valid when moved to `src/std_bundle.zig`.

No path changes needed for any `@embedFile` constant — all new files stay in `src/`.

### Pattern 5: Cross-file function calls

`runPipeline()` calls `ensureStdFiles()` (from `std_bundle.zig`) and `generateInterface()` (from `interface.zig`). Since these are `pub fn`, `pipeline.zig` imports the respective modules directly:

```zig
// pipeline.zig
const _std_bundle = @import("std_bundle.zig");
const _interface = @import("interface.zig");
// ...
try _std_bundle.ensureStdFiles(allocator);
// ...
try _interface.generateInterface(allocator, mod_name, binary_name, ast);
```

`runGendoc()` also calls `ensureStdFiles()`, so `commands.zig` imports `std_bundle.zig` too.

### Pattern 6: Local anonymous struct (collectCimport)

`collectCimport` (lines 1391-1447) is a locally-defined anonymous struct inside `runPipeline`. When `runPipeline` moves to `pipeline.zig`, this local struct moves with it unchanged. It is not visible outside and requires no special treatment.

### Anti-Patterns to Avoid

- **Importing main.zig from helper files:** main.zig is the root; helper files must never `@import("main.zig")`. All shared state flows through function parameters.
- **Build options in split files:** `build_options` (`@import("build_options")`) is only needed in `main.zig` for the `version` command. Do not import it in split files.
- **formatter.zig and lsp.zig local imports:** These two are imported inline inside `main()` (`if (cli.command == .fmt)` and `if (cli.command == .lsp)`). Keep them as inline local `@import` inside `main()` or move the import to the top of `main.zig`. Do not import them in split files.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-file type sharing | A shared types wrapper struct | Direct `@import` of cli.zig types | The existing parameter-passing pattern already solves this |
| Test infrastructure | New test helpers | Inline `codegenSource` helper in pipeline.zig | Pattern already established in main.zig |

---

## Common Pitfalls

### Pitfall 1: `build_options` used in split file

**What goes wrong:** `build_options.version` is used in the `version` command dispatch in `main()`. If `main.zig` is trimmed naively, the `@import("build_options")` might be dropped while a split file also needs it.

**Why it happens:** `build_options` is a special comptime module injected by `build.zig`. It is not a regular file import.

**How to avoid:** Keep `const build_options = @import("build_options");` in `main.zig` only. The version string is printed inline in `main()` during command dispatch — it stays there. Do not move the `version` command handling to any split file.

**Warning signs:** Compile error "unable to find 'build_options'" in a helper file.

### Pitfall 2: Unit tests referencing imports that moved

**What goes wrong:** The `full pipeline - hello world` test and `codegenSource` helper in main.zig reference `lexer`, `parser`, `mir`, `codegen`, `declarations`, etc. If these tests stay in main.zig but the imports move to pipeline.zig, the tests won't compile.

**Why it happens:** main.zig currently has 20 top-level imports. After the split, only a subset are needed in main.zig itself.

**How to avoid:** Move tests to the file where their imports live. The `full pipeline - hello world` and `codegen - *` tests use the full pipeline and belong in `pipeline.zig`. The `cli - build target names` test belongs in `cli.zig`. The `pipeline - imports all passes` smoke test also belongs in `pipeline.zig`.

**Warning signs:** `zig build test` fails with "use of undeclared identifier 'lexer'" in main.zig after the split.

### Pitfall 3: @embedFile paths becoming invalid

**What goes wrong:** Developer moves embed constants to a subdirectory (e.g., `src/bundler/std_bundle.zig`) — paths like `"std/collections.orh"` then resolve to `src/bundler/std/` which does not exist.

**Why it happens:** `@embedFile` paths are relative to the containing source file.

**How to avoid:** All split files stay flat in `src/`. Decision D-02 locks this. Path `"std/..."` resolves to `src/std/...` and `"templates/..."` resolves to `src/templates/...` regardless of which `src/*.zig` file hosts the embed.

**Warning signs:** Compile error "file not found: 'std/collections.orh'" at `@embedFile`.

### Pitfall 4: Shadowing with import names `cli` or `pipeline`

**What goes wrong:** `const cli = @import("cli.zig")` conflicts with the local variable `var cli = try parseArgs(...)` in `main()`.

**Why it happens:** Zig does not allow a module-level constant and a local variable to share the same name in the same scope.

**How to avoid:** Use underscore-prefixed import names: `const _cli = @import("cli.zig")`. Re-export types using `pub const CliArgs = _cli.CliArgs` if needed. Pattern established in Phase 33.

**Warning signs:** Zig compile error "local variable shadows outer variable" or "redefinition of 'cli'".

### Pitfall 5: `runGendoc` dependency on `ensureStdFiles`

**What goes wrong:** If `commands.zig` contains `runGendoc` but does not import `std_bundle.zig`, the call `try ensureStdFiles(allocator)` inside `runGendoc` will fail to compile.

**Why it happens:** `ensureStdFiles` is currently a private function in main.zig; it becomes a public function in `std_bundle.zig`.

**How to avoid:** `commands.zig` imports `std_bundle.zig` and calls `_std_bundle.ensureStdFiles(allocator)`. Same applies to any other function that calls `ensureStdFiles`.

**Warning signs:** Compile error "use of undeclared identifier 'ensureStdFiles'".

### Pitfall 6: `STR_ZIG` / `COLLECTIONS_ZIG` used in `runPipeline`

**What goes wrong:** `runPipeline` directly uses `STR_ZIG` and `COLLECTIONS_ZIG` constants (lines 909-914) to copy internal bridge files. If these constants move to `std_bundle.zig` but `pipeline.zig` does not import `std_bundle.zig`, the compile will fail.

**Why it happens:** These constants are not just for the stdlib bundler — they're also used inline in `runPipeline` for the bridge sidecar setup.

**How to avoid:** Two options:
1. Keep `STR_ZIG` and `COLLECTIONS_ZIG` in `std_bundle.zig` and have `pipeline.zig` import `std_bundle.zig` to access them as `_std_bundle.STR_ZIG` and `_std_bundle.COLLECTIONS_ZIG`.
2. Move the bridge copy logic inside `ensureStdFiles()` so `pipeline.zig` only calls `_std_bundle.ensureStdFiles(allocator)`.

Option 1 is simpler and keeps the split clean. The planner should choose this approach.

**Warning signs:** Compile error "use of undeclared identifier 'STR_ZIG'".

---

## Code Examples

### main.zig after split (target shape)

```zig
// main.zig — Orhon compiler entry point
// Allocator setup and command dispatch only.

const std = @import("std");
const build_options = @import("build_options");
const errors = @import("errors.zig");
const _cli = @import("cli.zig");
const _pipeline = @import("pipeline.zig");
const _init = @import("init.zig");
const _std_bundle = @import("std_bundle.zig");
const _commands = @import("commands.zig");

pub const CliArgs = _cli.CliArgs;
pub const Command = _cli.Command;
pub const BuildTarget = _cli.BuildTarget;

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const allocator = if (@import("builtin").mode == .Debug) da.allocator() else std.heap.smp_allocator;

    var cli = try _cli.parseArgs(allocator);
    defer cli.deinit();

    switch (cli.command) {
        .init     => { try _init.initProject(allocator, cli.project_name, cli.init_in_place); return; },
        .addtopath => { try _commands.addToPath(allocator); return; },
        .fmt       => { const formatter = @import("formatter.zig"); try formatter.formatProject(allocator, cli.source_dir); return; },
        .gendoc    => { try _commands.runGendoc(allocator, &cli); return; },
        .lsp       => { const lsp = @import("lsp.zig"); try lsp.serve(allocator); return; },
        .which     => { /* which logic */ return; },
        .analysis  => { try _commands.runAnalysis(allocator, &cli); return; },
        .debug     => { try _commands.runDebug(allocator, &cli); return; },
        .help      => { _cli.printHelp(); return; },
        .version   => { std.debug.print("orhon {s}\n", .{build_options.version}); return; },
        else       => {},
    }

    const mode: errors.BuildMode = if (cli.optimize == .fast or cli.optimize == .small) .release else .debug;
    var reporter = errors.Reporter.init(allocator, mode);
    defer reporter.deinit();

    const binary_name = _pipeline.runPipeline(allocator, &cli, &reporter) catch |err| blk: {
        switch (err) {
            error.ParseError, error.CompileError => {},
            else => return err,
        }
        break :blk null;
    };

    try reporter.flush();

    if (binary_name == null or reporter.hasErrors()) {
        std.process.exit(1);
    }
    defer allocator.free(binary_name.?);

    if (cli.command == .run) {
        const bin_path = try std.fmt.allocPrint(allocator, "bin/{s}", .{binary_name.?});
        defer allocator.free(bin_path);
        var child = std.process.Child.init(&.{bin_path}, allocator);
        _ = child.spawnAndWait() catch |err2| {
            std.debug.print("error: failed to run bin/{s}: {}\n", .{ binary_name.?, err2 });
            std.process.exit(1);
        };
    }
}
```

### pipeline.zig header pattern

```zig
// pipeline.zig — Compilation pipeline orchestration (runPipeline)

const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const module = @import("module.zig");
const declarations = @import("declarations.zig");
const resolver = @import("resolver.zig");
const ownership = @import("ownership.zig");
const borrow = @import("borrow.zig");
const thread_safety = @import("thread_safety.zig");
const propagation = @import("propagation.zig");
const sema = @import("sema.zig");
const mir = @import("mir.zig");
const codegen = @import("codegen.zig");
const zig_runner = @import("zig_runner.zig");
const errors = @import("errors.zig");
const cache = @import("cache.zig");
const _cli = @import("cli.zig");
const _std_bundle = @import("std_bundle.zig");
const _interface = @import("interface.zig");

pub fn runPipeline(...) !?[]const u8 { ... }
fn collectBridgeNames(...) ![][]const u8 { ... }
```

### std_bundle.zig constants pattern

```zig
// std_bundle.zig — Embedded stdlib files and extraction logic

const std = @import("std");
const cache = @import("cache.zig");

pub const STR_ZIG         = @embedFile("std/str.zig");
pub const COLLECTIONS_ZIG = @embedFile("std/collections.zig");
// ... all other std embeds ...

pub fn writeStdFile(dir: []const u8, name: []const u8, content: []const u8, allocator: std.mem.Allocator) !void { ... }
pub fn ensureStdFiles(allocator: std.mem.Allocator) !void { ... }
```

Note: `STR_ZIG` and `COLLECTIONS_ZIG` must be `pub` so `pipeline.zig` can reference them directly.

---

## Exact Function-to-File Mapping

### cli.zig

| Name | Kind | Lines (approx) |
|------|------|----------------|
| `Command` | enum | 29-43 |
| `BuildTarget` | enum + methods | 45-80 |
| `OptLevel` | enum | 82-86 |
| `CliArgs` | struct | 88-103 |
| `parseArgs` | fn | 105-203 |
| `printUsage` | fn | 205-213 |
| `printHelp` | fn | 215-248 |

Estimated: ~220 lines

### init.zig

| Name | Kind | Lines (approx) |
|------|------|----------------|
| `MAIN_ORH_TEMPLATE` | const @embedFile | 262 |
| `EXAMPLE_ORH_TEMPLATE` | const @embedFile | 265 |
| `CONTROL_FLOW_ORH_TEMPLATE` | const @embedFile | 266 |
| `ERROR_HANDLING_TEMPLATE` | const @embedFile | 267 |
| `DATA_TYPES_TEMPLATE` | const @embedFile | 268 |
| `STRINGS_TEMPLATE` | const @embedFile | 269 |
| `ADVANCED_TEMPLATE` | const @embedFile | 270 |
| `initProject` | fn | 273-352 |

Estimated: ~100 lines

### std_bundle.zig

| Name | Kind | Notes |
|------|------|-------|
| `COLLECTIONS_ORH`, `COLLECTIONS_ZIG`, ... (42 constants) | const @embedFile | Lines 359-411 |
| `STR_ZIG`, `COLLECTIONS_ZIG` | must be `pub` | Used by pipeline.zig |
| `writeStdFile` | fn | Line 414 |
| `ensureStdFiles` | fn | Line 425 |

Estimated: ~160 lines

### interface.zig

| Name | Kind | Lines (approx) |
|------|------|----------------|
| `formatType` | fn | 1759-1823 |
| `formatExprSimple` | fn | 1826-1843 |
| `emitFuncSig` | fn | 1846-1863 |
| `emitInterfaceDecl` | fn | 1866-1976 |
| `generateInterface` | fn | 2025-2064 |

Estimated: ~310 lines

### commands.zig

| Name | Kind | Lines (approx) |
|------|------|----------------|
| `runAnalysis` | fn | 716-793 |
| `runDebug` | fn | 795-842 |
| `runGendoc` | fn | 844-897 |
| `addToPath` | fn | 496-598 |
| `emitZigProject` | fn | 1981-1999 |
| `moveArtifactsToSubfolder` | fn | 2002-2023 |

Estimated: ~280 lines. Note: `emitZigProject` and `moveArtifactsToSubfolder` are called from `runPipeline` — they need to be `pub` and `pipeline.zig` imports `commands.zig` for them. This is the one cross-file dependency from pipeline to commands.

### pipeline.zig

| Name | Kind | Lines (approx) |
|------|------|----------------|
| `runPipeline` | fn | 899-1710 |
| `collectBridgeNames` | fn | 1715-1747 |

Estimated: ~820 lines — close to the 600-line goal but acceptable for a single dense orchestration function. The planner may choose to extract the multi-target build block into a helper, but this is not required.

### main.zig (after split)

| Name | Kind |
|------|------|
| `main` | pub fn |
| Imports + re-exports | top-level |

Estimated: ~115 lines.

---

## Unit Test Relocation

Current tests in main.zig (lines 2066-2328):

| Test name | Move to |
|-----------|---------|
| `pipeline - imports all passes` | `pipeline.zig` |
| `cli - build target names` | `cli.zig` |
| `full pipeline - hello world` | `pipeline.zig` |
| `codegen - var never reassigned becomes const` | `pipeline.zig` |
| `codegenSource` helper fn | `pipeline.zig` |
| `codegen - struct with method` | `pipeline.zig` |
| `codegen - enum with match` | `pipeline.zig` |
| `codegen - bitfield declaration` | `pipeline.zig` |

All codegen tests use `codegenSource()` which requires `lexer`, `parser`, `peg`, `declarations`, `resolver`, `mir`, `codegen`, `sema` — all imports that pipeline.zig will already have.

---

## build.zig Changes

1. **Add 6 new files** to `test_files` array.
2. **Keep or remove** `"src/main.zig"` from `test_files`. After the split, main.zig has no tests — safe to remove. If left in, `zig build test` will compile it as a test root with zero test blocks, which is harmless.

Recommended: remove `"src/main.zig"` from `test_files` after tests are relocated, to keep the list accurate.

---

## State of the Art

| Old Pattern | Current Pattern | Impact |
|-------------|-----------------|--------|
| Monolithic main.zig (2328 lines) | 7 focused files, each under 850 lines | Easier navigation and future edits |
| All pipeline imports in main.zig | Imports in pipeline.zig, only cli/error in main.zig | main.zig import list shrinks from 20 to ~4 |
| Tests colocated in main.zig | Tests move to their domain file | `zig build test` still runs all tests |

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — pure code restructuring, all tooling already in use).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Zig built-in test blocks + bash integration tests |
| Config file | `build.zig` (test_files array), `testall.sh` |
| Quick run command | `zig build test` |
| Full suite command | `./testall.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPLIT-04 | main.zig split into 6+ files | structural | `wc -l src/main.zig` (must be ~115) | checked post-split |
| SPLIT-04 | All 6+ split files exist | structural | `ls src/{cli,pipeline,init,std_bundle,interface,commands}.zig` | after Wave 0 |
| SPLIT-02 | All 266 tests pass | integration | `./testall.sh` | existing |
| SPLIT-02 | Unit tests pass in new locations | unit | `zig build test` | after move |

### Sampling Rate

- **Per task commit:** `zig build test`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all phase requirements. The only test change is relocating existing tests, not writing new ones.

---

## Open Questions

1. **emitZigProject / moveArtifactsToSubfolder grouping**
   - What we know: Both are called from `runPipeline`. They are small utility functions (~20 lines each).
   - What's unclear: Whether they belong in `commands.zig` (thematically about build output) or stay inline in `pipeline.zig` (where they're called).
   - Recommendation: Put them in `commands.zig` as `pub fn`. `pipeline.zig` imports `commands.zig`. This keeps pipeline.zig focused on pass execution and lets commands.zig own all "output artifact" utilities.

2. **pipeline.zig line count**
   - What we know: `runPipeline` alone is ~820 lines. Combined with `collectBridgeNames` (~35 lines) the file hits ~860 lines — above the 600-line soft target.
   - What's unclear: Whether the inner multi-target build block (~400 lines) should be extracted into a helper.
   - Recommendation: Leave `runPipeline` intact in one file. The 600-line soft target is a guideline, not a hard constraint. Splitting a single function across files would harm readability more than the line count hurts. The file has clear internal sections already (`// Pass 3`, `// Pass 4`, etc.).

---

## Sources

### Primary (HIGH confidence)

- Direct code reading of `src/main.zig` — all function locations and line counts verified
- Phase 33 SUMMARY.md — underscore-prefix pattern, re-export pattern (both confirmed working)
- Phase 29 SUMMARY.md — wrapper-stub pattern, build.zig test_files update (confirmed working)
- `build.zig` lines 43-81 — confirmed test_files array structure

### Secondary (MEDIUM confidence)

- Phase 32 CONTEXT.md — LSP split parameter-passing pattern (consistent with main.zig's existing approach)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pure Zig stdlib, no external dependencies
- Architecture: HIGH — identical pattern applied three times already in this codebase (Phases 29/32/33)
- Pitfalls: HIGH — all pitfalls derived from direct code reading and prior phase lessons
- Function mapping: HIGH — line numbers verified against actual source

**Research date:** 2026-03-29
**Valid until:** Stable until main.zig changes (no external dependencies to expire)
