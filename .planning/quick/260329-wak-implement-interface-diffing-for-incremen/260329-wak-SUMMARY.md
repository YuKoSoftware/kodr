---
phase: quick
plan: 260329-wak
subsystem: cache + pipeline
tags: [incremental, interface-diffing, cache, performance]
dependency_graph:
  requires: []
  provides: [interface-diffing-incremental]
  affects: [cache.zig, pipeline.zig]
tech_stack:
  added: []
  patterns: [XxHash3 rolling seed, sorted-key deterministic hashing, prev/curr hash snapshot comparison]
key_files:
  created: []
  modified:
    - src/cache.zig
    - src/pipeline.zig
decisions:
  - "Snapshot loaded interface hashes before processing loop to detect per-build changes correctly"
  - "Use insertion sort for name sorting (small slices, no allocation)"
  - "Store interface hash for skipped modules too, so downstream dep checks work correctly"
  - "depInterfaceChanged() is minimal — actual comparison happens inline in pipeline where both values are available"
metrics:
  duration_seconds: 473
  completed: "2026-03-29"
  tasks_completed: 2
  files_modified: 2
---

# Quick Task 260329-wak: Interface Diffing for Incremental Compilation Summary

**One-liner:** Deterministic public-interface hashing via `hashInterface(DeclTable)` with per-build snapshot comparison in pipeline, eliminating unnecessary downstream recompilation when only function bodies change.

## What Was Done

### Task 1: Interface hashing and storage in cache.zig

Added to `src/cache.zig`:

- `INTERFACES_FILE` constant: `.orh-cache/interfaces`
- `interface_hashes: std.StringHashMap(u64)` field on `Cache` with proper init/deinit
- `loadInterfaceHashes()` / `saveInterfaceHashes()` — same pattern as `loadHashes()` / `saveHashes()`
- `depInterfaceChanged()` — stub method for API completeness; real comparison is inline in pipeline
- `hashInterface(decls: *const DeclTable) u64` — deterministic u64 from public declarations only:
  - Six categories (funcs/structs/enums/bitfields/vars/types), each prefixed by a marker byte
  - Names collected and sorted alphabetically via `sortNames()` (insertion sort) before hashing
  - Only `is_pub = true` entries contribute — private changes do not affect the hash
- `hashResolvedType(seed, rt)` — recursive helper hashing tag discriminant + inner data
- `sortNames([][]const u8)` — insertion sort for small slices (deterministic ordering)
- 4 unit tests: deterministic, ignores-private, changes-on-pub, load/save roundtrip

### Task 2: Pipeline integration

Modified `src/pipeline.zig`:

- Load interface hashes after `loadDeps()` with `comp_cache.loadInterfaceHashes()`
- Snapshot loaded hashes into `prev_iface_hashes` before the module processing loop
- Replace `moduleNeedsRecompile()` call with interface-aware inline check:
  - `own_source_changed`: any of the module's own `.orh` files changed
  - `dep_interface_changed`: any dependency's current hash (post-processing) differs from the snapshot
  - `needs_recompile = own_source_changed or dep_interface_changed`
- Store `current_iface_hash` in `comp_cache.interface_hashes` for BOTH recompiled and skipped modules
- After `saveDeps()`, call `comp_cache.saveInterfaceHashes()` to persist for next build

## Key Design Decision: Snapshot Pattern

HashMap iteration order is non-deterministic and `comp_cache.interface_hashes` is mutated as each module is processed. The snapshot (`prev_iface_hashes`) captures values from the previous build. Comparing the dep's current value (in `comp_cache.interface_hashes`, set when the dep was processed) against the previous value (in `prev_iface_hashes`) correctly detects interface changes within a single build run.

## Deviations from Plan

**1. [Rule 1 - Bug] depInterfaceChanged() semantics clarified**
- **Found during:** Task 2 design review
- **Issue:** The plan described `depInterfaceChanged()` as the comparison point, but the comparison requires two values (previous and current hash) that are only available together in the pipeline, not inside cache.zig alone.
- **Fix:** `depInterfaceChanged()` kept minimal (checks for absent hash); actual comparison done inline in pipeline.zig with a `prev_iface_hashes` snapshot. This is cleaner — no hidden state in cache.zig.
- **Files modified:** src/cache.zig, src/pipeline.zig

**2. [Rule 2 - Missing functionality] Skipped modules need interface hash stored**
- **Found during:** Task 2 analysis
- **Issue:** The plan only mentioned storing interface hash "after codegen" (recompile path). Skipped modules also need their hash stored so downstream dependents can detect changes correctly.
- **Fix:** Added interface hash storage in the `!needs_recompile` skip path as well.
- **Files modified:** src/pipeline.zig

## Verification

- `zig build test`: 756/756 tests passed (including 4 new interface hashing tests)
- `./testall.sh`: 269/269 tests passed — zero regressions

## Self-Check: PASSED

- `src/cache.zig` modified with hashInterface, loadInterfaceHashes, saveInterfaceHashes
- `src/pipeline.zig` modified with interface-aware incremental logic
- Commits: 227b2fe (cache.zig), 2038b50 (pipeline.zig)
- All tests pass
