# Phase 35: Zig Runner Split - Research

**Researched:** 2026-03-29
**Domain:** Zig module refactoring — split zig_runner.zig into 4 focused files
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Split into 4 files by responsibility: runner core (ZigRunner struct + invocation), single-target build.zig generation, multi-target build.zig generation, and Zig binary discovery.
- **D-02:** Follow the flat `zig_runner_*.zig` naming pattern consistent with Phases 29/32/33/34.
- **D-03:** Runner core — `zig_runner.zig` keeps: ZigRunner struct (init, deinit), buildAll, build, buildLib, runTests, generateBuildZig, writeTestOutput.
- **D-04:** Single-target build gen — `buildZigContent()` and its helper functions (emitLinkLibs, emitIncludePath, generateSharedCImportFiles, emitCSourceFiles) move to a dedicated file (~560 lines). These helpers are also imported by the multi-target file.
- **D-05:** Multi-target build gen — `buildZigContentMulti()` and the `MultiTarget` struct move to a dedicated file (~593 lines). Imports shared helpers from the single-target file.
- **D-06:** Zig discovery — `findZig()`, `findZigInPath()`, `zigBinaryName()` move to a small dedicated file (~45 lines). Called only by ZigRunner.init().
- **D-07:** Shared build-gen helpers live in the single-target build gen file. The multi-target file imports them.
- **D-08:** Pass parameters explicitly — no wrapper structs needed (build gen functions already take allocator + data as parameters).
- **D-09:** Pure refactor. No function signatures change, no behavior changes. Generated build.zig output must be identical.
- **D-10:** Unit tests move to the file containing the function they test.

### Claude's Discretion

- Exact file names beyond the `zig_runner_*` prefix (e.g., `zig_runner_build.zig` vs `zig_runner_single.zig`)
- Whether `zig_runner.zig` uses `pub usingnamespace` or explicit re-exports for backward compatibility
- Exact placement of edge-case helpers that serve both build gen files

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPLIT-05 | zig_runner.zig split into 4+ files — runner core, single-target build gen, multi-target build gen, and Zig discovery | Full code audit complete — function boundaries, line counts, test distribution, and import graph all documented below |
| SPLIT-02 | Zero behavior change gate — `./testall.sh` passes all tests before and after each split, unit tests work in new locations | Pattern established in Phases 29/32/33/34; test relocation strategy documented below |

</phase_requirements>

---

## Summary

`src/zig_runner.zig` is 1952 lines covering four distinct responsibilities: the `ZigRunner` struct and invocation logic, single-target `build.zig` generation, multi-target `build.zig` generation, and Zig binary discovery. These responsibilities are cleanly separated at function boundaries with no interleaving — making this a straightforward extraction, identical in complexity to the Phase 33 MIR split (which completed in ~10 minutes).

The split follows the exact same pattern used in Phases 29, 32, 33, and 34. The key established lesson is to use underscore-prefixed module import names (e.g., `_zig_runner_build`) to avoid Zig shadowing conflicts with local variables. The main `zig_runner.zig` becomes a re-export facade so `pipeline.zig` — the sole caller — requires zero changes.

The one non-obvious complexity is the shared helper dependency: `buildZigContentMulti` calls `emitLinkLibs`, `emitIncludePath`, `emitCSourceFiles`, and `generateSharedCImportFiles` — all of which live in the single-target file (D-07). The multi-target file must import these from the single-target file. This creates a directed dependency (multi → single) which is clean and unidirectional.

**Primary recommendation:** One plan, one task. Extract all three satellite files simultaneously (pattern is well-proven), move tests, update `build.zig`, verify `./testall.sh` passes.

---

## Standard Stack

No new libraries. This is a pure Zig refactor using only the existing Zig standard library.

**Installation:** None required.

---

## Architecture Patterns

### Recommended File Structure After Split

```
src/
├── zig_runner.zig           # ~400 lines — ZigRunner struct, invocation, re-exports
├── zig_runner_build.zig     # ~560 lines — buildZigContent() + 4 shared helpers + tests
├── zig_runner_multi.zig     # ~593 lines — buildZigContentMulti() + MultiTarget + tests
└── zig_runner_discovery.zig # ~50 lines  — findZig(), findZigInPath(), zigBinaryName() + 1 test
```

(Exact names are Claude's discretion per D-02. `_build` and `_multi` communicate purpose clearly and follow the `_decls`/`_stmts`/`_exprs` naming precedent from Phase 29.)

### Pattern 1: Re-export Facade (established by Phase 33)

`zig_runner.zig` imports satellite modules with underscore prefixes, then re-exports all public types and functions that downstream callers use.

```zig
// zig_runner.zig — after split
const _build = @import("zig_runner_build.zig");
const _multi = @import("zig_runner_multi.zig");
const _discovery = @import("zig_runner_discovery.zig");

// Re-exports for backward compatibility (pipeline.zig uses these)
pub const MultiTarget = _multi.MultiTarget;
pub const buildZigContent = _build.buildZigContent;
pub const buildZigContentMulti = _multi.buildZigContentMulti;
pub const findZig = _discovery.findZig;

// ZigRunner struct + ZigResult + writeTestOutput stay here
pub const ZigResult = struct { ... };
pub const ZigRunner = struct { ... };
fn writeTestOutput(...) !void { ... }
```

`pipeline.zig` imports only `zig_runner.zig` and already accesses `zig_runner.ZigRunner` and `zig_runner.MultiTarget` — zero changes required.

### Pattern 2: Underscore-Prefixed Module Imports (established by Phase 33)

When importing satellite modules, use the underscore prefix to avoid Zig shadowing errors:

```zig
// CORRECT — avoids shadowing local variables
const _zig_runner_build = @import("zig_runner_build.zig");

// WRONG — may shadow a local variable named zig_runner_build
const zig_runner_build = @import("zig_runner_build.zig");
```

This was the only bug discovered in Phase 33 (MirLowerer had local vars named `mir_node`). Check `zig_runner_multi.zig` for any local variables that could conflict with the import names.

### Pattern 3: Cross-File Helper Import in Multi-Target File

`buildZigContentMulti` in `zig_runner_multi.zig` calls four helpers that live in `zig_runner_build.zig`:

```zig
// zig_runner_multi.zig
const _build = @import("zig_runner_build.zig");

// Then inside buildZigContentMulti:
try _build.emitLinkLibs(&buf, allocator, t.link_libs, var_name);
try _build.emitIncludePath(&buf, allocator, t.source_dir.?, var_name);
try _build.emitCSourceFiles(&buf, allocator, t.c_source_files, t.needs_cpp, var_name);
```

**Action required:** Change these four helpers from `fn` (private) to `pub fn` in `zig_runner_build.zig` so they are accessible from `zig_runner_multi.zig`.

`generateSharedCImportFiles` is already `pub fn` (it is called from `ZigRunner.buildAll` in the runner core). It must also be re-exported via `zig_runner.zig` so `ZigRunner.buildAll` can access it.

### Pattern 4: build.zig test_files Registration

Each new `.zig` file must be added to the `test_files` array in `build.zig`:

```zig
// build.zig — add these 3 new entries after "src/zig_runner.zig"
"src/zig_runner_build.zig",
"src/zig_runner_multi.zig",
"src/zig_runner_discovery.zig",
```

`src/zig_runner.zig` stays in the list (it retains `writeTestOutput` and its 2 formatTestOutput tests).

### Anti-Patterns to Avoid

- **Leaving helpers private:** `emitLinkLibs`, `emitIncludePath`, `emitCSourceFiles` are currently private (`fn`). They MUST become `pub fn` in `zig_runner_build.zig` so `zig_runner_multi.zig` can import them. Not doing this causes a compile error.
- **Skipping re-exports in zig_runner.zig:** `pipeline.zig` uses `zig_runner.MultiTarget` and `zig_runner.ZigRunner`. If `MultiTarget` moves to `zig_runner_multi.zig` without a re-export in `zig_runner.zig`, `pipeline.zig` breaks.
- **Moving `builtin` import:** `findZigInPath` uses `builtin.os.tag` — the `const builtin = @import("builtin");` at line 1690 must move to `zig_runner_discovery.zig`.

---

## Don't Hand-Roll

This phase has no library concerns. The only "don't hand-roll" principle is: use the established re-export facade pattern from Phase 33 rather than updating all callers.

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Backward compatibility after moving types | Update all callers of zig_runner | `pub const` re-exports in zig_runner.zig facade | Zero downstream changes, proven in phases 33 and 34 |
| Import name conflicts | Rename local variables | Underscore-prefix module imports | Established lesson from Phase 33 |

---

## Exact Code Inventory

### Functions Staying in zig_runner.zig (~400 lines)

| Symbol | Type | Lines (approx) |
|--------|------|----------------|
| `ZigResult` | pub struct | 12-22 |
| `ZigRunner` | pub struct | 25-423 |
| `ZigRunner.init` | pub fn | 31-43 |
| `ZigRunner.deinit` | pub fn | 45-47 |
| `ZigRunner.buildAll` | pub fn | 49-176 |
| `ZigRunner.build` | pub fn | ~178-270 |
| `ZigRunner.buildLib` | pub fn | ~272-360 |
| `ZigRunner.runTests` | pub fn | ~362-375 |
| `ZigRunner.generateBuildZig` | pub fn | ~377-422 |
| `writeTestOutput` | fn (private) | 427-473 |
| Re-exports for MultiTarget, buildZigContent, buildZigContentMulti, findZig | pub const | new |
| Tests: "formatTestOutput - all passed..." | test | 1924-1933 |
| Tests: "formatTestOutput - failure reports..." | test | 1936-1952 |

### Functions Moving to zig_runner_build.zig (~560 lines)

| Symbol | Type | Visibility Change |
|--------|------|-------------------|
| `buildZigContent` | pub fn | unchanged |
| `emitLinkLibs` | fn → pub fn | must be pub for multi-target import |
| `emitIncludePath` | fn → pub fn | must be pub for multi-target import |
| `generateSharedCImportFiles` | pub fn | unchanged |
| `emitCSourceFiles` | fn → pub fn | must be pub for multi-target import |
| Tests: "buildZigContent - exe" through "buildZigContent - no linkC..." (8 tests) | test | move with function |

### Functions Moving to zig_runner_multi.zig (~593 lines)

| Symbol | Type | Notes |
|--------|------|-------|
| `MultiTarget` | pub struct | 1030-1043; also re-exported from zig_runner.zig |
| `buildZigContentMulti` | pub fn | 1047-1640; calls helpers from zig_runner_build.zig |
| Tests: "buildZigContentMulti - exe with dynamic lib" through "buildZigContentMulti - csource directive..." (7 tests) | test | move with function |

### Functions Moving to zig_runner_discovery.zig (~50 lines)

| Symbol | Type | Notes |
|--------|------|-------|
| `findZig` | pub fn | 1645-1664; called by ZigRunner.init() via re-export |
| `findZigInPath` | fn (private) | 1666-1684 |
| `zigBinaryName` | fn (private) | 1686-1688 |
| `const builtin = @import("builtin")` | import | line 1690; moves here |
| Tests: "zig runner - find zig path format" (1 test) | test | move with function |

### Test Distribution Summary

| File | Tests Staying/Moving |
|------|----------------------|
| zig_runner.zig | 2 (formatTestOutput tests) |
| zig_runner_build.zig | ~8 (all buildZigContent tests) |
| zig_runner_multi.zig | ~7 (all buildZigContentMulti tests) |
| zig_runner_discovery.zig | 1 (find zig path format test) |
| **Total** | **16 (unchanged count)** |

---

## Common Pitfalls

### Pitfall 1: Private Helper Visibility

**What goes wrong:** `emitLinkLibs`, `emitIncludePath`, and `emitCSourceFiles` are currently private (`fn`, not `pub fn`). If they move to `zig_runner_build.zig` and stay private, `zig_runner_multi.zig` cannot import them — compile error.

**Why it happens:** In Zig, non-pub declarations are file-private. They cannot be accessed via `@import` from another file even in the same directory.

**How to avoid:** Change all three to `pub fn` when extracting to `zig_runner_build.zig`.

**Warning signs:** `error: 'emitLinkLibs' is not marked 'pub'` during `zig build test`.

### Pitfall 2: Missing builtin Import in Discovery File

**What goes wrong:** `findZigInPath` references `builtin.os.tag`. The `const builtin = @import("builtin");` at line 1690 of the current file must move to `zig_runner_discovery.zig`. If forgotten, the discovery file fails to compile.

**How to avoid:** Include `const builtin = @import("builtin");` at the top of `zig_runner_discovery.zig`.

### Pitfall 3: Missing Re-exports for pipeline.zig

**What goes wrong:** `pipeline.zig` uses `zig_runner.MultiTarget` (line 392), `zig_runner.ZigRunner` (lines 323, 371), and `zig_runner.buildZigContent` / `zig_runner.buildZigContentMulti` indirectly via ZigRunner methods. If `MultiTarget` moves to `zig_runner_multi.zig` without a `pub const MultiTarget = _multi.MultiTarget;` re-export in `zig_runner.zig`, pipeline.zig breaks.

**How to avoid:** Add explicit `pub const` re-exports in `zig_runner.zig` for every public symbol that moves to a satellite file.

### Pitfall 4: generateSharedCImportFiles Called from ZigRunner.buildAll

**What goes wrong:** `ZigRunner.buildAll` (staying in `zig_runner.zig`) calls `generateSharedCImportFiles` directly (line 67). After extraction, this becomes a cross-file call. It must be accessible via either a re-export or direct import of the build file.

**How to avoid:** Either re-export `generateSharedCImportFiles` from `zig_runner.zig`, or import `_zig_runner_build` directly inside `zig_runner.zig` for this one call. Direct import is cleaner.

### Pitfall 5: ZigRunner.generateBuildZig Calls buildZigContent

**What goes wrong:** `ZigRunner.generateBuildZigWithTests` (private method staying in runner core) calls `buildZigContent` at line 405. After split, this is a cross-file call that requires `zig_runner.zig` to import `zig_runner_build.zig`.

**How to avoid:** Import `_zig_runner_build` at the top of `zig_runner.zig` and call `_zig_runner_build.buildZigContent(...)`.

---

## Code Examples

### Import Structure in zig_runner.zig After Split

```zig
// zig_runner.zig — after split
// Source: established pattern from src/mir.zig (Phase 33)

const std = @import("std");
const errors = @import("errors.zig");
const cache = @import("cache.zig");
const module = @import("module.zig");
const _zig_runner_build = @import("zig_runner_build.zig");
const _zig_runner_multi = @import("zig_runner_multi.zig");
const _zig_runner_discovery = @import("zig_runner_discovery.zig");

// Re-exports — backward compat for pipeline.zig
pub const MultiTarget = _zig_runner_multi.MultiTarget;
pub const buildZigContent = _zig_runner_build.buildZigContent;
pub const buildZigContentMulti = _zig_runner_multi.buildZigContentMulti;
pub const findZig = _zig_runner_discovery.findZig;
```

### Import Structure in zig_runner_multi.zig

```zig
// zig_runner_multi.zig
// Source: established pattern from src/mir_lowerer.zig (Phase 33)

const std = @import("std");
const errors = @import("errors.zig");
const cache = @import("cache.zig");
const _build = @import("zig_runner_build.zig");  // for shared helpers

// Usage inside buildZigContentMulti:
// try _build.emitLinkLibs(&buf, allocator, t.link_libs, var_name);
// try _build.emitIncludePath(&buf, allocator, t.source_dir.?, var_name);
// try _build.emitCSourceFiles(&buf, allocator, ...);
```

### build.zig test_files Update

```zig
// Before:
"src/zig_runner.zig",

// After:
"src/zig_runner.zig",
"src/zig_runner_build.zig",
"src/zig_runner_multi.zig",
"src/zig_runner_discovery.zig",
```

---

## Runtime State Inventory

Not applicable — this is a greenfield refactor with no rename/migration component. No stored data, live service config, OS-registered state, secrets, or build artifacts reference `zig_runner` by name.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is a pure code restructuring with no external dependencies beyond the existing Zig toolchain, which is already confirmed operational (266 tests pass on current branch).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Zig built-in `test` blocks |
| Config file | `build.zig` (test_files array) |
| Quick run command | `zig build test` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| SPLIT-05 | zig_runner.zig split into 4 focused files | structural | `zig build test` + `./testall.sh` | ✅ existing tests, relocated |
| SPLIT-02 | Zero behavior change — all 266 tests pass | integration | `./testall.sh` | ✅ full suite |

### Sampling Rate

- **Per task commit:** `zig build test`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** `./testall.sh` all 266 tests green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all phase requirements. All 16 unit tests already exist in `zig_runner.zig`; they move to their new files.

---

## Sources

### Primary (HIGH confidence)

- Direct source audit of `src/zig_runner.zig` (1952 lines) — all function boundaries, visibility, line ranges
- Direct source audit of `src/pipeline.zig` — confirms `zig_runner.ZigRunner` and `zig_runner.MultiTarget` usage
- `build.zig` — confirms `test_files` array structure and exact entry format
- Phase 33 SUMMARY (`33-01-SUMMARY.md`) — underscore-prefix lesson documented from actual execution
- Phase 34 SUMMARY (`34-02-SUMMARY.md`) — latest split iteration, confirms pattern stability

### Secondary (MEDIUM confidence)

- Phase 33 CONTEXT and 34 CONTEXT — strategy decisions that apply directly
- REQUIREMENTS.md — SPLIT-05 and SPLIT-02 requirement text

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; pure Zig stdlib
- Architecture: HIGH — verified against actual source code and 4 prior split phases
- Pitfalls: HIGH — all identified pitfalls rooted in actual code inspection (visibility, cross-imports, `builtin` dependency)

**Research date:** 2026-03-29
**Valid until:** Stable — zig_runner.zig content verified against current main branch (commit 7719b44)
