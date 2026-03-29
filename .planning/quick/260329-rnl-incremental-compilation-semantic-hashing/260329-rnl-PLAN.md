---
phase: quick-260329-rnl
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/cache.zig
  - src/pipeline.zig
autonomous: true
requirements: [INCR-HASH]
must_haves:
  truths:
    - "Files touched but not changed (git checkout, save-without-edit) do not trigger recompilation"
    - "Files with actual content changes still trigger recompilation"
    - "First build after upgrade triggers full rebuild (old cache format ignored)"
    - "All 11 test stages pass"
  artifacts:
    - path: "src/cache.zig"
      provides: "Content-hash-based cache invalidation using XxHash3"
      contains: "XxHash3"
    - path: "src/pipeline.zig"
      provides: "Pipeline using hash-based cache API"
      contains: "loadHashes"
  key_links:
    - from: "src/pipeline.zig"
      to: "src/cache.zig"
      via: "loadHashes/saveHashes/updateHash calls"
      pattern: "comp_cache\\.(loadHashes|saveHashes|updateHash)"
---

<objective>
Replace timestamp-based cache invalidation with content hashing (XxHash3) so that files touched but not changed (git checkout, save-without-edit) skip recompilation.

Purpose: Avoid unnecessary rebuilds when file mtime changes but content is identical.
Output: Updated cache.zig and pipeline.zig with hash-based invalidation.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@src/cache.zig
@src/pipeline.zig
@.planning/quick/260329-rnl-incremental-compilation-semantic-hashing/260329-rnl-RESEARCH.md
</context>

<interfaces>
<!-- From src/cache.zig — current API that will be renamed -->
pub const TIMESTAMPS_FILE = ".orh-cache/timestamps";
pub const ModuleEntry = struct { name, files, last_modified: i128 };
pub const Cache = struct {
    timestamps: std.StringHashMap(i128),
    pub fn loadTimestamps(self: *Cache) !void;
    pub fn saveTimestamps(self: *Cache) !void;
    pub fn hasChanged(self: *Cache, path: []const u8) !bool;
    pub fn updateTimestamp(self: *Cache, path: []const u8) !void;
    pub fn moduleNeedsRecompile(self: *Cache, module_name: []const u8, files: []const []const u8) !bool;
};

<!-- From src/pipeline.zig — call sites (lines 65-68, 144, 313, 318-319) -->
comp_cache.loadTimestamps();   // line 67
comp_cache.moduleNeedsRecompile(mod_name, mod_ptr.files);  // line 144
comp_cache.updateTimestamp(file);  // line 313
comp_cache.saveTimestamps();   // line 318
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Replace timestamp cache with content hashing in cache.zig</name>
  <files>src/cache.zig</files>
  <behavior>
    - Test: cache init has empty hashes map (count == 0)
    - Test: hasChanged returns true for nonexistent file
    - Test: hasChanged returns false for file whose content matches cached hash
    - Test: hasChanged returns true for file whose content differs from cached hash
    - Test: updateHash stores correct XxHash3 hash for a real file
  </behavior>
  <action>
    Replace the timestamp-based cache with content hashing. All changes in cache.zig:

    1. Add import: `const XxHash3 = std.hash.XxHash3;`

    2. Rename constant: `TIMESTAMPS_FILE` -> `HASHES_FILE = ".orh-cache/hashes"` (new filename so old cache is cleanly ignored on upgrade, triggering full rebuild)

    3. Change `ModuleEntry.last_modified: i128` -> `content_hash: u64`

    4. Change `Cache.timestamps: std.StringHashMap(i128)` -> `hashes: std.StringHashMap(u64)`

    5. Update `init`: initialize `hashes` field instead of `timestamps`

    6. Update `deinit`: iterate `self.hashes` instead of `self.timestamps`, free keys

    7. Replace `loadTimestamps` with `loadHashes`:
       - Open HASHES_FILE instead of TIMESTAMPS_FILE
       - Parse values as `u64` instead of `i128`: `std.fmt.parseInt(u64, hash_str, 10)`
       - Put into `self.hashes`

    8. Replace `saveTimestamps` with `saveHashes`:
       - Create HASHES_FILE instead of TIMESTAMPS_FILE
       - Write from `self.hashes` iterator

    9. Replace `hasChanged`:
       ```zig
       pub fn hasChanged(self: *Cache, path: []const u8) !bool {
           const content = std.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch return true;
           defer self.allocator.free(content);
           const current_hash = XxHash3.hash(0, content);
           const cached_hash = self.hashes.get(path) orelse return true;
           return current_hash != cached_hash;
       }
       ```

    10. Replace `updateTimestamp` with `updateHash`:
        ```zig
        pub fn updateHash(self: *Cache, path: []const u8) !void {
            const content = try std.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024);
            defer self.allocator.free(content);
            const hash_val = XxHash3.hash(0, content);
            const result = try self.hashes.getOrPut(path);
            if (!result.found_existing) {
                result.key_ptr.* = try self.allocator.dupe(u8, path);
            }
            result.value_ptr.* = hash_val;
        }
        ```

    11. `moduleNeedsRecompile` — no changes needed (it calls `hasChanged` which is already updated)

    12. Update existing tests and add new tests:
        - Update "cache init and deinit" to check `cache.hashes.count()`
        - "cache has changed - nonexistent file" — no change needed (same API)
        - Add test "cache unchanged file has same hash": write a temp file, call updateHash, then hasChanged returns false
        - Add test "cache detects content change": write temp file, updateHash, modify file, hasChanged returns true

    13. Update file header comment: `// cache.zig — Orhon incremental compilation cache (content hashing)`
  </action>
  <verify>
    <automated>cd /home/yunus/Projects/orhon/orhon_compiler && zig build test 2>&1 | tail -20</automated>
  </verify>
  <done>cache.zig uses XxHash3 content hashing instead of mtime timestamps. All unit tests pass including new hash-specific tests.</done>
</task>

<task type="auto">
  <name>Task 2: Update pipeline.zig call sites</name>
  <files>src/pipeline.zig</files>
  <action>
    Rename the 4 cache method calls in pipeline.zig:

    1. Line 67: `comp_cache.loadTimestamps()` -> `comp_cache.loadHashes()`
    2. Line 313: `comp_cache.updateTimestamp(file)` -> `comp_cache.updateHash(file)`
    3. Line 318: `comp_cache.saveTimestamps()` -> `comp_cache.saveHashes()`

    No other changes needed. The `moduleNeedsRecompile` call on line 144 is unchanged (same signature, internally uses updated `hasChanged`).
  </action>
  <verify>
    <automated>cd /home/yunus/Projects/orhon/orhon_compiler && zig build 2>&1 | tail -5</automated>
  </verify>
  <done>Pipeline compiles with no errors, calling the renamed hash-based cache API.</done>
</task>

<task type="auto">
  <name>Task 3: Full test suite validation</name>
  <files></files>
  <action>
    Run the full 11-stage test suite to confirm nothing is broken:
    ```bash
    ./testall.sh
    ```

    Expected: all stages pass. The incremental compilation tests in test/05_compile.sh exercise the cache path.

    If any test fails due to old `.orh-cache/timestamps` file being present in test fixtures or test setup, ensure the test cleans `.orh-cache/` before running (tests already do this — verify).
  </action>
  <verify>
    <automated>cd /home/yunus/Projects/orhon/orhon_compiler && ./testall.sh 2>&1 | tail -30</automated>
  </verify>
  <done>All 11 test stages pass. Incremental compilation works with content hashing.</done>
</task>

</tasks>

<verification>
1. `zig build test` — unit tests pass (including new hash tests)
2. `zig build` — compiler builds cleanly
3. `./testall.sh` — all 11 stages pass
4. Manual smoke test: build a project, touch a file without changing it, rebuild — should skip recompilation
</verification>

<success_criteria>
- cache.zig uses XxHash3 content hashing instead of filesystem mtime
- HASHES_FILE is ".orh-cache/hashes" (not old "timestamps" name)
- pipeline.zig calls loadHashes/saveHashes/updateHash
- All 269+ tests pass
- Files touched but not changed skip recompilation
</success_criteria>

<output>
After completion, create `.planning/quick/260329-rnl-incremental-compilation-semantic-hashing/260329-rnl-SUMMARY.md`
</output>
