# Incremental Compilation: Semantic Hashing - Research

**Researched:** 2026-03-29
**Domain:** Cache invalidation / incremental compilation
**Confidence:** HIGH

## Summary

The current incremental compilation system in `cache.zig` uses filesystem `mtime` timestamps to determine whether a module needs recompilation. This causes unnecessary rebuilds when files are touched but not changed (git checkout, save-without-edit, CI artifact restoration). The fix is to replace timestamp comparison with content hashing.

**Primary recommendation:** Hash raw file bytes using `std.hash.XxHash3` (already in Zig stdlib, used nowhere in compiler yet). Store hashes in the existing timestamps file format. This is the simplest change with the highest reliability.

## Project Constraints (from CLAUDE.md)

- All compiler code is Zig 0.15.2+
- No external dependencies -- Zig stdlib only
- `./testall.sh` must pass after changes (266 tests, 11 stages)
- No hacky workarounds -- clean fixes only
- Changes must not break existing `.orh` programs

## Current Implementation Analysis

### How it works now

1. **`cache.zig`** stores `StringHashMap(i128)` mapping file paths to `mtime` values
2. **`Cache.hasChanged(path)`** compares current `stat.mtime` against cached value
3. **`Cache.moduleNeedsRecompile(module, files)`** calls `hasChanged` for each file, then checks dependency graph
4. **`pipeline.zig`** calls `moduleNeedsRecompile` per module. If false, skips passes 4-12 and replays cached warnings
5. After successful compilation, `updateTimestamp` stores current mtime
6. Format in `.orh-cache/timestamps`: `path timestamp\n` (one per line, space-separated)

### Why timestamps are fragile

- `git checkout` / `git stash pop` changes mtime even if content is identical
- Editors that "save without changes" bump mtime
- CI/CD that restores build caches from archives changes mtimes
- File copy/move operations change mtime
- Clock skew on network filesystems

## Architecture: What to Hash

### Option A: Raw file bytes (RECOMMENDED)

Hash the raw source bytes of each `.orh` file before any processing.

**Pros:**
- Simplest -- no dependency on lexer or parser
- Catches ALL changes (including comment changes that affect doc generation)
- Can be computed before lexing, so failure in lexer does not block caching
- No risk of hash collisions from normalization

**Cons:**
- Comment-only or whitespace-only changes trigger rebuild (acceptable -- these are rare and could affect doc comments)

### Option B: Token stream hash

Hash the token kinds + text after lexing.

**Pros:**
- Ignores whitespace/comment changes
- "Semantic" -- only meaningful changes trigger rebuild

**Cons:**
- Requires lexing every file even for cache checks (lexer runs anyway, but couples cache to lexer)
- Comment changes that affect `///` doc comments would be missed
- More complex, more fragile
- Token stream is not currently available at cache-check time in pipeline.zig

**Verdict:** Option A. The timestamp file is checked BEFORE lexing in the pipeline flow (line 144 in pipeline.zig). Switching to raw-byte hashing keeps the same control flow -- just read + hash instead of stat. Token-stream hashing would require restructuring the pipeline to lex first, then check cache, which is unnecessary complexity for marginal benefit.

## Hash Function Selection

### Available in Zig 0.15.x `std.hash`

| Function | Speed | Quality | Use Case |
|----------|-------|---------|----------|
| `std.hash.XxHash3` | Very fast | Excellent (64-bit) | Non-crypto hashing, checksums |
| `std.hash.Wyhash` | Very fast | Good (64-bit) | Already used in `peg/engine.zig` |
| `std.hash.CityHash64` | Fast | Good | General purpose |
| `std.hash.Crc32` | Medium | OK (32-bit) | Legacy, smaller output |
| `std.crypto.hash.sha2.Sha256` | Slow | Crypto-grade | Overkill for this |

**Recommendation:** Use `std.hash.XxHash3`. It is purpose-built for content checksumming -- fast on both small and large inputs, 64-bit output (collision probability ~1 in 2^64 for any two files), and available in Zig stdlib. No need for crypto-grade hashing since this is a build cache, not a security mechanism.

Alternatively, `Wyhash` is already used in the codebase (peg/engine.zig line 63) and would also work fine. Either is acceptable.

**Hash output type:** `u64` -- fits cleanly into the existing `i128` slot in the timestamps hashmap (just change the value type to `u64`), or store as `u128` if using the `XxHash3.hash` convenience function.

## Implementation Plan

### Changes to `cache.zig`

1. Change `ModuleEntry.last_modified: i128` to `content_hash: u64`
2. Change `Cache.timestamps: StringHashMap(i128)` to `StringHashMap(u64)` (rename field to `hashes`)
3. Replace `hasChanged`:
   ```zig
   pub fn hasChanged(self: *Cache, path: []const u8) !bool {
       const content = std.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch return true;
       defer self.allocator.free(content);
       const current_hash = std.hash.XxHash3.hash(0, content);
       const cached_hash = self.hashes.get(path) orelse return true;
       return current_hash != cached_hash;
   }
   ```
4. Replace `updateTimestamp` with `updateHash`:
   ```zig
   pub fn updateHash(self: *Cache, path: []const u8) !void {
       const content = try std.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024);
       defer self.allocator.free(content);
       const hash = std.hash.XxHash3.hash(0, content);
       const result = try self.hashes.getOrPut(path);
       if (!result.found_existing) {
           result.key_ptr.* = try self.allocator.dupe(u8, path);
       }
       result.value_ptr.* = hash;
   }
   ```
5. Rename `loadTimestamps`/`saveTimestamps` to `loadHashes`/`saveHashes` -- same file format but values are now hash integers
6. Rename constants: `TIMESTAMPS_FILE` stays as `.orh-cache/timestamps` (or rename to `.orh-cache/hashes` -- minor)

### Changes to `pipeline.zig`

Minimal -- just rename method calls:
- `comp_cache.loadTimestamps()` -> `comp_cache.loadHashes()`
- `comp_cache.updateTimestamp(file)` -> `comp_cache.updateHash(file)`
- `comp_cache.saveTimestamps()` -> `comp_cache.saveHashes()`

### Performance consideration

Current approach: `stat()` per file (1 syscall).
New approach: `open() + read() + close()` per file (3 syscalls + memory).

For unchanged modules, this is slightly more expensive. But:
- Source files are small (typically < 50KB)
- XxHash3 hashes at ~10 GB/s -- negligible
- The read is dwarfed by the compilation time saved when hash matches
- The file will be read anyway during lexing if changed, so only the "unchanged" case adds I/O

**Optimization opportunity (optional):** Do a stat-first check: if mtime matches cached mtime AND hash matches, skip. If mtime differs, hash to check. This avoids reading files when timestamps happen to be stable. But this adds complexity for marginal gain -- not recommended for v1.

## Edge Cases

| Case | Behavior |
|------|----------|
| New file (not in cache) | `hashes.get()` returns null -> returns `true` (needs compile) |
| Deleted file | `readFileAlloc` fails -> `catch return true` (needs compile) |
| File touched but unchanged | Hash matches -> `false` (skip compile) -- THIS IS THE FIX |
| Dependency changed, source unchanged | `moduleNeedsRecompile` already checks deps separately -- no change needed |
| Cache file format migration | Old `timestamps` file has i128 mtime values; new code reads them as u64 hashes. First build after upgrade: parseInt will succeed but hashes won't match old values -> full rebuild on first run, then correct from there. Acceptable. |
| Empty file | XxHash3 of empty input is a valid u64 -> works fine |

## File Format

Keep the same format: `path value\n`. The value changes from mtime (i128) to hash (u64). Since `std.fmt.parseInt` works for both, old cache files will parse but produce wrong hashes, triggering a one-time full rebuild. This is correct behavior -- no migration code needed.

Consider renaming the file from `timestamps` to `hashes` to make the format change explicit and avoid confusion. Old `timestamps` file would be ignored (FileNotFound on new name), triggering a clean full rebuild.

## Common Pitfalls

### Pitfall 1: Double file read
**What goes wrong:** Reading the file once for hashing and again for lexing.
**How to avoid:** The hash check happens in `moduleNeedsRecompile` before lexing. If the module needs recompile, the file is read again in `module.zig` line 384. This double-read is acceptable for correctness and simplicity. Do NOT try to cache the file content between hash check and lexing -- that would require threading content through the pipeline and is not worth the complexity.

### Pitfall 2: Hash collision paranoia
**What goes wrong:** Using a slow crypto hash "for safety."
**How to avoid:** XxHash3 with 64 bits gives collision probability of ~1 in 10^19 for any pair. With thousands of files, still astronomically unlikely. This is a build cache, not a security boundary. If a collision somehow occurs, the worst case is a skipped rebuild -- user runs `orhon build` again and it works.

### Pitfall 3: Forgetting to update hash after successful compile
**What goes wrong:** Hash is checked but never updated -> module recompiles every time.
**How to avoid:** The existing `updateTimestamp` call site (pipeline.zig line 313) already runs after successful codegen. Just rename to `updateHash`.

## Sources

### Primary (HIGH confidence)
- `src/cache.zig` -- full source read, 282 lines
- `src/pipeline.zig` -- cache integration points identified at lines 65-68, 144, 299, 311-319
- `src/lexer.zig` -- token structure analyzed, confirmed not needed for hashing
- `src/peg/engine.zig` line 63 -- precedent for `std.hash.Wyhash` usage in codebase

### Secondary (MEDIUM confidence)
- Zig stdlib hash functions: `std.hash.XxHash3`, `std.hash.Wyhash` -- available in 0.15.x based on codebase evidence (Wyhash already imported and used)

## Metadata

**Confidence breakdown:**
- Implementation approach: HIGH -- direct code analysis of all touchpoints
- Hash function choice: HIGH -- XxHash3/Wyhash are well-established, already in stdlib
- Edge cases: HIGH -- all paths traced through code
- Performance: MEDIUM -- theoretical analysis, not benchmarked

**Research date:** 2026-03-29
**Valid until:** 2026-04-28 (stable domain, no fast-moving dependencies)
