---
phase: quick-260329-rnl
plan: 01
subsystem: cache
tags: [incremental, cache, hashing, performance]
dependency_graph:
  requires: []
  provides: [content-hash-cache]
  affects: [src/cache.zig, src/pipeline.zig, test/05_compile.sh]
tech_stack:
  added: [std.hash.XxHash3]
  patterns: [content-hashing, cache-invalidation]
key_files:
  created: []
  modified:
    - src/cache.zig
    - src/pipeline.zig
    - test/05_compile.sh
decisions:
  - Renamed cache file from .orh-cache/timestamps to .orh-cache/hashes so old caches are cleanly ignored on upgrade, triggering a one-time full rebuild
  - Used XxHash3 (not Wyhash) for content hashing — purpose-built for checksumming, 64-bit output, already in Zig stdlib
  - File-content hashing approach (not token-stream) preserves existing control flow — hash check happens before lexing
metrics:
  duration: 4m
  completed: "2026-03-29T17:08:37Z"
  tasks_completed: 3
  files_modified: 3
---

# Quick Task 260329-rnl: Incremental Compilation Semantic Hashing — Summary

**One-liner:** XxHash3 content-hash cache invalidation replacing mtime timestamps, so touched-but-unchanged files skip recompilation.

## What Was Done

Replaced the timestamp-based incremental compilation cache in `cache.zig` with XxHash3 content hashing. Previously, any file whose mtime changed (e.g., `git checkout`, save-without-edit, CI artifact restoration) would trigger unnecessary recompilation. Now the compiler reads file content and compares a 64-bit XxHash3 hash — only files with actual content changes trigger a rebuild.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Replace timestamp cache with XxHash3 content hashing in cache.zig | ac0e7ca | src/cache.zig |
| 2 | Update pipeline.zig call sites to hash-based API | 2316409 | src/pipeline.zig |
| 3 | Full test suite + fix incremental test checking old filename | ac7d897 | test/05_compile.sh |

## API Changes

| Old | New |
|-----|-----|
| `TIMESTAMPS_FILE = ".orh-cache/timestamps"` | `HASHES_FILE = ".orh-cache/hashes"` |
| `Cache.timestamps: StringHashMap(i128)` | `Cache.hashes: StringHashMap(u64)` |
| `ModuleEntry.last_modified: i128` | `ModuleEntry.content_hash: u64` |
| `loadTimestamps()` | `loadHashes()` |
| `saveTimestamps()` | `saveHashes()` |
| `updateTimestamp(path)` | `updateHash(path)` |
| `hasChanged` used `stat().mtime` | `hasChanged` reads file, computes XxHash3 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated test/05_compile.sh incremental test**
- **Found during:** Task 3 (full test suite)
- **Issue:** Test checked `[ -f .orh-cache/timestamps ]` — old filename no longer created
- **Fix:** Updated test to check `[ -f .orh-cache/hashes ]` and renamed test description to "cache hashes exist"
- **Files modified:** test/05_compile.sh
- **Commit:** ac7d897

## Test Results

- All 269 tests pass (was 269 before; 1 test description updated)
- New unit tests added: "cache unchanged file has same hash", "cache detects content change"
- Incremental compilation path exercised by test/05_compile.sh

## Self-Check

### Created/modified files exist:
- src/cache.zig — FOUND
- src/pipeline.zig — FOUND
- test/05_compile.sh — FOUND

### Commits exist:
- ac0e7ca — FOUND
- 2316409 — FOUND
- ac7d897 — FOUND

## Self-Check: PASSED
