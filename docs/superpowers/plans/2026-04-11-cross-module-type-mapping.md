# Cross-Module Type Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix GAP-001 — make `mapTypeEx()` resolve cross-module qualified types (`.field_access` nodes) when the qualifier is a known sibling Zig module, so functions with cross-module parameter/return types are no longer silently skipped.

**Architecture:** Add an `ImportAliasMap` struct that maps local Zig import aliases to sibling module names. Build it once per module from the AST root declarations. Thread it through the call chain as a single optional parameter. In `mapTypeEx`, use it to resolve `.field_access` nodes to qualified Orhon type names.

**Tech Stack:** Zig 0.15, std.zig.Ast

---

## File Structure

| File | Role |
|------|------|
| `src/zig_module.zig` | All changes — ImportAliasMap struct, mapTypeEx field_access logic, signature threading |

Single-file change. All functions live in `zig_module.zig`.

---

### Task 1: Add ImportAliasMap struct

**Files:**
- Modify: `src/zig_module.zig:17` (after PASSTHROUGH_PRIMITIVES)

- [ ] **Step 1: Add the ImportAliasMap struct**

In `src/zig_module.zig`, add after `PASSTHROUGH_PRIMITIVES` (after line 17):

```zig
/// Maps local Zig import aliases to sibling module names.
/// Built from top-level `const sdl = @import("tamga_sdl3_bridge.zig")` declarations.
const ImportAliasMap = struct {
    /// alias → module name: "sdl" → "tamga_sdl3_bridge"
    map: std.StringHashMapUnmanaged([]const u8) = .{},
    /// Known sibling module names (from scanZigImports)
    sibling_modules: []const []const u8 = &.{},

    fn deinit(self: *ImportAliasMap, allocator: Allocator) void {
        self.map.deinit(allocator);
    }

    /// Check if a module name is a known sibling
    fn isSibling(self: *const ImportAliasMap, name: []const u8) bool {
        for (self.sibling_modules) |s| {
            if (std.mem.eql(u8, s, name)) return true;
        }
        return false;
    }

    /// Resolve an alias to its module name, or return the name itself if it's a direct sibling
    fn resolve(self: *const ImportAliasMap, name: []const u8) ?[]const u8 {
        if (self.map.get(name)) |mod| return mod;
        if (self.isSibling(name)) return name;
        return null;
    }
};
```

- [ ] **Step 2: Verify it compiles**

Run: `zig build 2>&1 | head -20`
Expected: Clean build (struct is not referenced yet).

- [ ] **Step 3: Commit**

```bash
git add src/zig_module.zig
git commit -m "feat: add ImportAliasMap struct for cross-module type resolution"
```

---

### Task 2: Add buildImportAliasMap function

**Files:**
- Modify: `src/zig_module.zig` (after ImportAliasMap struct)

- [ ] **Step 1: Add buildImportAliasMap function**

Add after the `ImportAliasMap` struct:

```zig
/// Builds an ImportAliasMap from the AST root declarations.
/// Scans for `const X = @import("Y.zig")` patterns and maps X → Y (stem).
fn buildImportAliasMap(tree: *const Ast, sibling_modules: []const []const u8, allocator: Allocator) ImportAliasMap {
    var result = ImportAliasMap{ .sibling_modules = sibling_modules };

    const root_decls = tree.rootDecls();
    for (root_decls) |decl_node| {
        const tag = tree.nodeTag(decl_node);
        if (tag != .simple_var_decl and tag != .global_var_decl) continue;

        // Get the var decl — must be const (mut_token is 'const')
        const mut_token = tree.nodeMainToken(decl_node);
        if (tree.tokenTag(mut_token) != .keyword_const) continue;

        // Get the name (token after 'const')
        const name_token = mut_token + 1;
        if (name_token >= tree.tokens.len) continue;
        if (tree.tokenTag(name_token) != .identifier) continue;
        const alias_name = tree.tokenSlice(name_token);

        // Get the init node — must be a builtin_call (@import)
        const init_node = if (tag == .simple_var_decl)
            tree.nodeData(decl_node).opt_node_and_opt_node[1].unwrap() orelse continue
        else
            tree.nodeData(decl_node).opt_node_and_opt_node[1].unwrap() orelse continue;

        const init_tag = tree.nodeTag(init_node);
        if (init_tag != .builtin_call_two and init_tag != .builtin_call_two_comma and
            init_tag != .builtin_call and init_tag != .builtin_call_comma) continue;

        // Check that it's @import
        const builtin_token = tree.nodeMainToken(init_node);
        const builtin_name = tree.tokenSlice(builtin_token);
        if (!std.mem.eql(u8, builtin_name, "@import")) continue;

        // Get the first argument — must be a string literal
        const arg_node = if (init_tag == .builtin_call_two or init_tag == .builtin_call_two_comma)
            tree.nodeData(init_node).opt_node_and_opt_node[0].unwrap() orelse continue
        else
            continue; // multi-arg builtin_call — not @import("x.zig")

        if (tree.nodeTag(arg_node) != .string_literal) continue;
        const str_token = tree.nodeMainToken(arg_node);
        const raw = tree.tokenSlice(str_token);

        // Strip quotes: "foo.zig" → foo.zig
        if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') continue;
        const import_path = raw[1 .. raw.len - 1];

        // Must end with .zig
        if (!std.mem.endsWith(u8, import_path, ".zig")) continue;

        // Extract module stem
        const mod_name = import_path[0 .. import_path.len - 4];

        // Only map if it's a known sibling
        var is_sibling = false;
        for (sibling_modules) |s| {
            if (std.mem.eql(u8, s, mod_name)) {
                is_sibling = true;
                break;
            }
        }
        if (!is_sibling) continue;

        result.map.put(allocator, alias_name, mod_name) catch continue;
    }

    return result;
}
```

- [ ] **Step 2: Verify it compiles**

Run: `zig build 2>&1 | head -20`
Expected: Clean build (function is not called yet).

- [ ] **Step 3: Commit**

```bash
git add src/zig_module.zig
git commit -m "feat: add buildImportAliasMap — scans AST for const X = @import patterns"
```

---

### Task 3: Update mapTypeEx to resolve .field_access

**Files:**
- Modify: `src/zig_module.zig:40-42` (mapType)
- Modify: `src/zig_module.zig:44` (mapTypeEx signature)
- Modify: `src/zig_module.zig:80-98` (recursive calls)
- Modify: `src/zig_module.zig:134` (recursive call in ptr_type)
- Modify: `src/zig_module.zig:142-146` (.field_access case)

- [ ] **Step 1: Add import_aliases parameter to mapTypeEx**

Change the signature at line 44 from:

```zig
fn mapTypeEx(tree: *const Ast, node: Node.Index, allocator: Allocator, out: *TypeBuf, self_replacement: ?[]const u8) anyerror!bool {
```

to:

```zig
fn mapTypeEx(tree: *const Ast, node: Node.Index, allocator: Allocator, out: *TypeBuf, self_replacement: ?[]const u8, import_aliases: ?*const ImportAliasMap) anyerror!bool {
```

- [ ] **Step 2: Update mapType to pass null**

Change line 41 from:

```zig
    return mapTypeEx(tree, node, allocator, out, null);
```

to:

```zig
    return mapTypeEx(tree, node, allocator, out, null, null);
```

- [ ] **Step 3: Update all recursive mapTypeEx calls to pass import_aliases through**

In the `.optional_type` case (line 83), change:
```zig
            const ok = try mapTypeEx(tree, child, allocator, out, self_replacement);
```
to:
```zig
            const ok = try mapTypeEx(tree, child, allocator, out, self_replacement, import_aliases);
```

In the `.error_union` case (line 94), change:
```zig
            const ok = try mapTypeEx(tree, rhs, allocator, out, self_replacement);
```
to:
```zig
            const ok = try mapTypeEx(tree, rhs, allocator, out, self_replacement, import_aliases);
```

In the `.ptr_type*` one-pointer case (line 134), change:
```zig
                    return try mapTypeEx(tree, ptr_info.ast.child_type, allocator, out, self_replacement);
```
to:
```zig
                    return try mapTypeEx(tree, ptr_info.ast.child_type, allocator, out, self_replacement, import_aliases);
```

- [ ] **Step 4: Replace .field_access case with resolution logic**

Replace lines 142-146:

```zig
        // --- field_access: lhs.rhs — qualified names like std.mem.Allocator ---
        .field_access => {
            // Qualified names are unmappable (std.mem.Allocator, etc.)
            return false;
        },
```

with:

```zig
        // --- field_access: lhs.rhs — qualified names ---
        .field_access => {
            const aliases = import_aliases orelse return false;

            // RHS is the type name token (e.g., WindowHandle)
            const rhs_token = tree.nodeData(node).node_and_token[1];
            const type_name = tree.tokenSlice(rhs_token);

            // LHS is the qualifier node
            const lhs_node = tree.nodeData(node).node_and_token[0];
            const lhs_tag = tree.nodeTag(lhs_node);

            // Case 1: identifier qualifier (e.g., sdl.WindowHandle)
            if (lhs_tag == .identifier) {
                const lhs_name = tree.tokenSlice(tree.nodeMainToken(lhs_node));
                if (aliases.resolve(lhs_name)) |mod_name| {
                    try out.append(allocator, mod_name);
                    try out.append(allocator, ".");
                    try out.append(allocator, type_name);
                    return true;
                }
                return false;
            }

            // Case 2: @import("sibling.zig").TypeName
            if (lhs_tag == .builtin_call_two or lhs_tag == .builtin_call_two_comma) {
                const builtin_token = tree.nodeMainToken(lhs_node);
                const builtin_name = tree.tokenSlice(builtin_token);
                if (!std.mem.eql(u8, builtin_name, "@import")) return false;

                const arg_node = tree.nodeData(lhs_node).opt_node_and_opt_node[0].unwrap() orelse return false;
                if (tree.nodeTag(arg_node) != .string_literal) return false;
                const raw = tree.tokenSlice(tree.nodeMainToken(arg_node));
                if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return false;
                const import_path = raw[1 .. raw.len - 1];

                // Strip .zig extension if present
                const mod_name = if (std.mem.endsWith(u8, import_path, ".zig"))
                    import_path[0 .. import_path.len - 4]
                else
                    import_path;

                if (aliases.isSibling(mod_name)) {
                    try out.append(allocator, mod_name);
                    try out.append(allocator, ".");
                    try out.append(allocator, type_name);
                    return true;
                }
                return false;
            }

            return false;
        },
```

- [ ] **Step 5: Verify it compiles**

Run: `zig build 2>&1 | head -20`
Expected: May get errors from callers of `mapTypeEx` that need the new parameter — those are fixed in the next task.

- [ ] **Step 6: Commit**

```bash
git add src/zig_module.zig
git commit -m "feat: mapTypeEx resolves .field_access for sibling module types"
```

---

### Task 4: Thread import_aliases through the call chain

**Files:**
- Modify: `src/zig_module.zig:158-159` (extractFn)
- Modify: `src/zig_module.zig:167-174` (extractFnInner)
- Modify: `src/zig_module.zig:177-184` (extractFnInnerEx)
- Modify: `src/zig_module.zig:243` (mapTypeEx call in extractFnInnerEx)
- Modify: `src/zig_module.zig:265` (mapTypeEx call for return type)
- Modify: `src/zig_module.zig:289-296` (extractStructFn)
- Modify: `src/zig_module.zig:409` (extractFnInnerEx call in extractGenericStruct)
- Modify: `src/zig_module.zig:592-596` (extractStruct)
- Modify: `src/zig_module.zig:620` (extractStructFn call in extractStruct)
- Modify: `src/zig_module.zig:642-646` (generateModule)
- Modify: `src/zig_module.zig:660-662` (extractFn/extractGenericStruct calls)

- [ ] **Step 1: Update extractFnInnerEx signature and mapTypeEx calls**

Change signature at line 177 from:

```zig
fn extractFnInnerEx(
    tree: *const Ast,
    node: Node.Index,
    struct_name: []const u8,
    prefix: []const u8,
    allocator: Allocator,
    self_replacement: ?[]const u8,
    allow_unmappable_as_any: bool,
) anyerror!?[]const u8 {
```

to:

```zig
fn extractFnInnerEx(
    tree: *const Ast,
    node: Node.Index,
    struct_name: []const u8,
    prefix: []const u8,
    allocator: Allocator,
    self_replacement: ?[]const u8,
    allow_unmappable_as_any: bool,
    import_aliases: ?*const ImportAliasMap,
) anyerror!?[]const u8 {
```

Update the two `mapTypeEx` calls inside `extractFnInnerEx`:

Line 243 — change:
```zig
                const ok = try mapTypeEx(tree, type_node, allocator, &type_buf, self_replacement);
```
to:
```zig
                const ok = try mapTypeEx(tree, type_node, allocator, &type_buf, self_replacement, import_aliases);
```

Line 265 — change:
```zig
    const ret_ok = try mapTypeEx(tree, ret_node, allocator, &ret_buf, self_replacement);
```
to:
```zig
    const ret_ok = try mapTypeEx(tree, ret_node, allocator, &ret_buf, self_replacement, import_aliases);
```

- [ ] **Step 2: Update extractFnInner**

Change signature at line 167 to add import_aliases:

```zig
fn extractFnInner(
    tree: *const Ast,
    node: Node.Index,
    struct_name: []const u8,
    prefix: []const u8,
    allocator: Allocator,
    import_aliases: ?*const ImportAliasMap,
) anyerror!?[]const u8 {
    return extractFnInnerEx(tree, node, struct_name, prefix, allocator, null, false, import_aliases);
}
```

- [ ] **Step 3: Update extractFn**

Change at line 158:

```zig
pub fn extractFn(tree: *const Ast, node: Node.Index, allocator: Allocator, import_aliases: ?*const ImportAliasMap) anyerror!?[]const u8 {
    return extractFnInner(tree, node, "", "pub func ", allocator, import_aliases);
}
```

- [ ] **Step 4: Update extractStructFn**

Change at line 290:

```zig
fn extractStructFn(
    tree: *const Ast,
    node: Node.Index,
    struct_name: []const u8,
    allocator: Allocator,
    import_aliases: ?*const ImportAliasMap,
) anyerror!?[]const u8 {
    return extractFnInner(tree, node, struct_name, "    pub func ", allocator, import_aliases);
}
```

- [ ] **Step 5: Update extractStruct**

Change signature at line 592:

```zig
pub fn extractStruct(
    tree: *const Ast,
    node: Node.Index,
    name: []const u8,
    allocator: Allocator,
    import_aliases: ?*const ImportAliasMap,
) anyerror!?[]const u8 {
```

Update the `extractStructFn` call at line 620:

```zig
            if (try extractStructFn(tree, member, name, allocator, import_aliases)) |sig| {
```

- [ ] **Step 6: Update extractGenericStruct**

Change signature at line 301:

```zig
pub fn extractGenericStruct(tree: *const Ast, node: Node.Index, allocator: Allocator, import_aliases: ?*const ImportAliasMap) anyerror!?[]const u8 {
```

Update the `extractFnInnerEx` call at line 409:

```zig
            if (try extractFnInnerEx(tree, member, fn_name, "    pub func ", allocator, self_replacement, true, import_aliases)) |sig| {
```

- [ ] **Step 7: Update generateModule**

Change signature at line 642:

```zig
pub fn generateModule(
    mod_name: []const u8,
    tree: *const Ast,
    allocator: Allocator,
    sibling_imports: []const []const u8,
) anyerror!?[]const u8 {
```

After the header_len line (line 654), build the alias map:

```zig
    var import_alias_map = buildImportAliasMap(tree, sibling_imports, allocator);
    defer import_alias_map.deinit(allocator);
```

Update the switch at line 660-662:

```zig
        const decl_str: ?[]const u8 = switch (tag) {
            .fn_decl, .fn_proto, .fn_proto_multi, .fn_proto_one, .fn_proto_simple => try extractGenericStruct(tree, decl_node, allocator, &import_alias_map) orelse try extractFn(tree, decl_node, allocator, &import_alias_map),

            .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => try extractConst(tree, decl_node, allocator),

            else => null,
        };
```

- [ ] **Step 8: Verify it compiles**

Run: `zig build 2>&1 | head -30`
Expected: May get errors from `discoverAndConvert` or other callers of `generateModule` / `extractFn` — fixed in the next task.

- [ ] **Step 9: Commit**

```bash
git add src/zig_module.zig
git commit -m "feat: thread import_aliases through extract call chain"
```

---

### Task 5: Update discoverAndConvert — move scanZigImports before generateModule

**Files:**
- Modify: `src/zig_module.zig:843-847` (reorder scanZigImports and generateModule)

- [ ] **Step 1: Move scanZigImports before generateModule and pass sibling list**

In `discoverAndConvert()`, the current order is:

```zig
        const orh_text = generateModule(entry.module_name, &tree, allocator) catch continue orelse continue;
        defer allocator.free(orh_text);

        const zig_imports = scanZigImports(source_bytes, source_dir, allocator) catch &.{};
```

Change to:

```zig
        // Scan for sibling @import("x.zig") references BEFORE generating module
        // so the import context is available for cross-module type mapping
        const zig_imports = scanZigImports(source_bytes, source_dir, allocator) catch &.{};
        defer {
            for (zig_imports) |imp| allocator.free(imp);
            if (zig_imports.len > 0) allocator.free(zig_imports);
        }

        const orh_text = generateModule(entry.module_name, &tree, allocator, zig_imports) catch continue orelse continue;
        defer allocator.free(orh_text);
```

And **remove** the old `zig_imports` declaration and its defer block that was after `generateModule` (the one at lines 847-851).

- [ ] **Step 2: Check for other callers of generateModule and extractFn**

Search for any other call sites that need updating:

```bash
grep -n "generateModule\|extractFn(" src/zig_module.zig
```

If there are other callers of `generateModule`, pass `&.{}` (empty sibling list) to preserve existing behavior. If there are other callers of `extractFn`, pass `null` for the import_aliases parameter.

- [ ] **Step 3: Verify it compiles**

Run: `zig build 2>&1 | head -20`
Expected: Clean build.

- [ ] **Step 4: Commit**

```bash
git add src/zig_module.zig
git commit -m "feat: move scanZigImports before generateModule for cross-module type context"
```

---

### Task 6: Verify with the full test suite

- [ ] **Step 1: Run the full test suite**

Run: `./testall.sh 2>&1 | tail -20`
Expected: All tests pass. The change is backwards-compatible — modules without sibling imports behave identically.

- [ ] **Step 2: If any failures, read test_log.txt and fix**

Run: `cat test_log.txt | head -100`

Common issues:
- Compilation errors from missed callers (grep for `extractFn\|extractStruct\|generateModule` to find them all)
- Test expectations that check generated `.orh` content may need updating if they involve Zig modules with cross-module imports

- [ ] **Step 3: Commit any fixes**

```bash
git add -u
git commit -m "fix: resolve test failures for cross-module type mapping"
```

---

### Task 7: Integration test with tamga-style fixture

**Files:**
- Create: `test/fixtures/zig_cross_module/` (test directory)

- [ ] **Step 1: Create two sibling .zig files that exercise cross-module types**

Create `test/fixtures/zig_cross_module/module_a.zig`:

```zig
pub const HandleA = *anyopaque;

pub fn createHandle() HandleA {
    return @as(HandleA, @ptrFromInt(0));
}
```

Create `test/fixtures/zig_cross_module/module_b.zig`:

```zig
const mod_a = @import("module_a.zig");

pub const Result = struct {
    value: i32,
};

pub fn useHandle(h: mod_a.HandleA) Result {
    _ = h;
    return .{ .value = 42 };
}

pub fn useHandleInline(h: @import("module_a.zig").HandleA) Result {
    _ = h;
    return .{ .value = 1 };
}
```

- [ ] **Step 2: Write a test that converts both modules and checks the output**

Add a test in the appropriate test stage. Since this exercises the Zig module converter, add it as a unit test block at the end of `src/zig_module.zig`:

```zig
test "cross-module type mapping — alias and inline import" {
    const allocator = std.testing.allocator;

    // Simulate sibling modules
    const sibling_modules: []const []const u8 = &.{"module_a"};

    // Parse module_b source
    const source =
        \\const mod_a = @import("module_a.zig");
        \\
        \\pub const Result = struct {
        \\    value: i32,
        \\};
        \\
        \\pub fn useHandle(h: mod_a.HandleA) Result {
        \\    _ = h;
        \\    return .{ .value = 42 };
        \\}
        \\
        \\pub fn useHandleInline(h: @import("module_a.zig").HandleA) Result {
        \\    _ = h;
        \\    return .{ .value = 1 };
        \\}
    ;

    var tree = try std.zig.Ast.parse(allocator, @as([:0]const u8, source), .zig);
    defer tree.deinit(allocator);

    const result = try generateModule("module_b", &tree, allocator, sibling_modules);
    defer if (result) |r| allocator.free(r);

    const orh = result orelse {
        return error.NoOutput;
    };

    // Both functions should be present with qualified type names
    try std.testing.expect(std.mem.indexOf(u8, orh, "module_a.HandleA") != null);
    try std.testing.expect(std.mem.indexOf(u8, orh, "useHandle") != null);
    try std.testing.expect(std.mem.indexOf(u8, orh, "useHandleInline") != null);
}
```

- [ ] **Step 3: Run the unit test**

Run: `zig build test 2>&1 | tail -20`
Expected: Test passes.

- [ ] **Step 4: Commit**

```bash
git add src/zig_module.zig test/fixtures/zig_cross_module/
git commit -m "test: cross-module type mapping — alias and inline @import"
```

---

### Task 8: Update tamga compiler-gaps.md

**Files:**
- Modify: `/home/yunus/Projects/orhon/tamga/docs/compiler-gaps.md`

- [ ] **Step 1: Mark GAP-001 as resolved**

In `/home/yunus/Projects/orhon/tamga/docs/compiler-gaps.md`, add `**Status:** Fixed` after the date line and add a note at the bottom:

```markdown
**Status:** Fixed in orhon_compiler (cross-module type mapping, 2026-04-11)
```

- [ ] **Step 2: Run full test suite one more time**

Run: `./testall.sh 2>&1 | tail -10`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/zig_module.zig
git commit -m "feat: cross-module type mapping for sibling Zig modules (fixes GAP-001)"
```
