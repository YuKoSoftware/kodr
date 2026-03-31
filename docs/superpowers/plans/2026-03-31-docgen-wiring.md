# Docgen Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `///` doc comments and `#description` metadata through the AST builder so `orhon gendoc` produces markdown with actual content, and add `-std` flag for stdlib docs.

**Architecture:** The lexer already strips `///` prefix from doc comment tokens. The PEG grammar already captures `doc_block` nodes. All AST declaration types already have `doc: ?[]const u8` fields. The missing piece is the builder — it skips `doc_block` captures everywhere. We add a `extractDoc` helper and a `setDoc` helper (mirroring the existing `setPub` pattern), then wire them into the four places that process declarations: `buildProgram` (top-level), `collectStructParts`, `collectEnumMembers`, and `collectBlueprintMethods`.

**Tech Stack:** Zig 0.15.2+, PEG builder (`src/peg/`), CLI (`src/cli.zig`), commands (`src/commands.zig`)

---

### Task 1: Add `extractDoc` and `setDoc` helpers to builder.zig

**Files:**
- Modify: `src/peg/builder.zig:389-414` (after `hasPubBefore`, before `setPub` or after it)

- [ ] **Step 1: Add `extractDoc` function**

This function takes a `BuildContext` and a `doc_block` capture node, reads all `doc_comment` tokens in its range, and joins their text with newlines. The lexer already strips `///` and one optional space, so the token `.text` is clean content.

Add after `setPub` (line 414) in `src/peg/builder.zig`:

```zig
/// Extract doc comment text from a doc_block capture node.
/// Joins all DOC_COMMENT token texts with newlines.
pub fn extractDoc(ctx: *BuildContext, doc_cap: *const CaptureNode) ?[]const u8 {
    var parts = std.ArrayListUnmanaged([]const u8){};
    var i = doc_cap.start_pos;
    while (i < doc_cap.end_pos and i < ctx.tokens.len) : (i += 1) {
        if (ctx.tokens[i].kind == .doc_comment) {
            parts.append(ctx.alloc(), ctx.tokens[i].text) catch return null;
        }
    }
    if (parts.items.len == 0) return null;
    return std.mem.join(ctx.alloc(), "\n", parts.items) catch null;
}

/// Set the doc field on a declaration node.
pub fn setDoc(node: *Node, doc: ?[]const u8) void {
    switch (node.*) {
        .func_decl => |*d| d.doc = doc,
        .struct_decl => |*d| d.doc = doc,
        .blueprint_decl => |*d| d.doc = doc,
        .enum_decl => |*d| d.doc = doc,
        .bitfield_decl => |*d| d.doc = doc,
        .const_decl => |*d| d.doc = doc,
        .var_decl => |*d| d.doc = doc,
        .field_decl => |*d| d.doc = doc,
        .enum_variant => |*d| d.doc = doc,
        .module_decl => |*d| d.doc = doc,
        else => {},
    }
}
```

- [ ] **Step 2: Build and verify no compilation errors**

Run: `zig build 2>&1 | head -20`
Expected: Clean build (functions are defined but not yet called)

- [ ] **Step 3: Commit**

```bash
git add src/peg/builder.zig
git commit -m "docgen: add extractDoc and setDoc helpers"
```

---

### Task 2: Wire doc_block to top-level declarations in buildProgram

**Files:**
- Modify: `src/peg/builder_decls.zig:24-66` (`buildProgram` function)

The grammar rule is `top_level <- doc_block? top_level_decl`. So `top_level` capture nodes have an optional `doc_block` child followed by declaration children. We need to extract the doc from the `doc_block` child and attach it to the built declaration node.

- [ ] **Step 1: Update the top_level handling in buildProgram**

In `buildProgram`, the `top_level` branch (lines 38-44) currently iterates children and builds any with a rule. Change it to track `doc_block` children and attach them to the next declaration:

Replace lines 38-44:
```zig
            } else if (std.mem.eql(u8, r, "top_level")) {
                // top_level is transparent — build its child
                for (child.children) |*tl_child| {
                    if (tl_child.rule) |_| {
                        try top_level_list.append(ctx.alloc(), try builder.buildNode(ctx, tl_child));
                    }
                }
```

With:
```zig
            } else if (std.mem.eql(u8, r, "top_level")) {
                // top_level <- doc_block? top_level_decl
                var pending_doc: ?[]const u8 = null;
                for (child.children) |*tl_child| {
                    if (tl_child.rule) |tl_rule| {
                        if (std.mem.eql(u8, tl_rule, "doc_block")) {
                            pending_doc = builder.extractDoc(ctx, tl_child);
                        } else {
                            const node = try builder.buildNode(ctx, tl_child);
                            if (pending_doc) |doc| {
                                builder.setDoc(node, doc);
                                pending_doc = null;
                            }
                            try top_level_list.append(ctx.alloc(), node);
                        }
                    }
                }
```

- [ ] **Step 2: Build and verify no compilation errors**

Run: `zig build 2>&1 | head -20`
Expected: Clean build

- [ ] **Step 3: Run tests**

Run: `./testall.sh 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add src/peg/builder_decls.zig
git commit -m "docgen: wire doc_block to top-level declarations"
```

---

### Task 3: Wire doc_block to struct members and enum members

**Files:**
- Modify: `src/peg/builder.zig:358-388` (`collectStructParts`)
- Modify: `src/peg/builder_decls.zig:440-454` (`collectEnumMembers`)

Both functions iterate children, skip `doc_block`, and build declarations. Change them to track the last seen `doc_block` and attach it to the next declaration.

- [ ] **Step 1: Update collectStructParts in builder.zig**

Replace the entire `collectStructParts` function (lines 358-388):

```zig
pub fn collectStructParts(ctx: *BuildContext, cap: *const CaptureNode, type_params: *std.ArrayListUnmanaged(*Node), members: *std.ArrayListUnmanaged(*Node)) anyerror!void {
    var pending_doc: ?[]const u8 = null;
    for (cap.children) |*child| {
        if (child.rule) |r| {
            if (std.mem.eql(u8, r, "doc_block")) {
                pending_doc = extractDoc(ctx, child);
            } else if (std.mem.eql(u8, r, "field_decl") or
                std.mem.eql(u8, r, "func_decl") or
                std.mem.eql(u8, r, "compt_decl") or
                std.mem.eql(u8, r, "const_decl") or
                std.mem.eql(u8, r, "var_decl") or
                std.mem.eql(u8, r, "bridge_decl") or
                std.mem.eql(u8, r, "bridge_func") or
                std.mem.eql(u8, r, "bridge_const"))
            {
                const node = try buildNode(ctx, child);
                if (hasPubBefore(ctx, cap, child.start_pos)) setPub(node, true);
                if (pending_doc) |doc| {
                    setDoc(node, doc);
                    pending_doc = null;
                }
                try members.append(ctx.alloc(), node);
            } else if (std.mem.eql(u8, r, "pub_decl")) {
                const node = try buildNode(ctx, child);
                if (pending_doc) |doc| {
                    setDoc(node, doc);
                    pending_doc = null;
                }
                try members.append(ctx.alloc(), node);
            } else if (std.mem.eql(u8, r, "generic_params") or std.mem.eql(u8, r, "param_list")) {
                try collectParamsRecursive(ctx, child, type_params);
            } else if (std.mem.eql(u8, r, "_") or std.mem.eql(u8, r, "TERM") or std.mem.eql(u8, r, "type")) {
                // skip (doc_block handled above)
            } else {
                try collectStructParts(ctx, child, type_params, members);
            }
        }
    }
}
```

- [ ] **Step 2: Update collectEnumMembers in builder_decls.zig**

Replace `collectEnumMembers` (lines 440-454):

```zig
fn collectEnumMembers(ctx: *BuildContext, cap: *const CaptureNode, members: *std.ArrayListUnmanaged(*Node)) anyerror!void {
    var pending_doc: ?[]const u8 = null;
    for (cap.children) |*child| {
        if (child.rule) |r| {
            if (std.mem.eql(u8, r, "doc_block")) {
                pending_doc = builder.extractDoc(ctx, child);
            } else if (std.mem.eql(u8, r, "enum_variant") or std.mem.eql(u8, r, "func_decl") or std.mem.eql(u8, r, "pub_decl")) {
                const node = try builder.buildNode(ctx, child);
                if (builder.hasPubBefore(ctx, cap, child.start_pos)) builder.setPub(node, true);
                if (pending_doc) |doc| {
                    builder.setDoc(node, doc);
                    pending_doc = null;
                }
                try members.append(ctx.alloc(), node);
            } else if (std.mem.eql(u8, r, "_") or std.mem.eql(u8, r, "TERM") or std.mem.eql(u8, r, "type")) {
                // skip (doc_block handled above)
            } else {
                try collectEnumMembers(ctx, child, members);
            }
        }
    }
}
```

- [ ] **Step 3: Build and run tests**

Run: `zig build 2>&1 | head -20 && ./testall.sh 2>&1 | tail -5`
Expected: Clean build, all tests pass

- [ ] **Step 4: Commit**

```bash
git add src/peg/builder.zig src/peg/builder_decls.zig
git commit -m "docgen: wire doc_block to struct and enum members"
```

---

### Task 4: Wire doc_block to blueprint methods and module_decl

**Files:**
- Modify: `src/peg/builder_decls.zig:362-374` (`collectBlueprintMethods`)
- Modify: `src/peg/builder_decls.zig:68-74` (`buildModuleDecl`)

- [ ] **Step 1: Update collectBlueprintMethods**

Replace the function (lines 362-374):

```zig
fn collectBlueprintMethods(ctx: *BuildContext, cap: *const CaptureNode, methods: *std.ArrayListUnmanaged(*Node)) anyerror!void {
    var pending_doc: ?[]const u8 = null;
    for (cap.children) |*child| {
        if (child.rule) |r| {
            if (std.mem.eql(u8, r, "doc_block")) {
                pending_doc = builder.extractDoc(ctx, child);
            } else if (std.mem.eql(u8, r, "blueprint_method")) {
                const node = try buildBlueprintMethod(ctx, child);
                if (pending_doc) |doc| {
                    builder.setDoc(node, doc);
                    pending_doc = null;
                }
                try methods.append(ctx.alloc(), node);
            } else if (std.mem.eql(u8, r, "_") or std.mem.eql(u8, r, "TERM")) {
                // skip (doc_block handled above)
            } else {
                try collectBlueprintMethods(ctx, child, methods);
            }
        }
    }
}
```

- [ ] **Step 2: Update buildModuleDecl to extract doc_block**

Replace `buildModuleDecl` (lines 68-74):

```zig
pub fn buildModuleDecl(ctx: *BuildContext, cap: *const CaptureNode) !*Node {
    // module_decl <- doc_block? 'module' IDENTIFIER NL
    const name_pos = builder.findTokenInRange(ctx, cap.start_pos + 1, cap.end_pos, .identifier) orelse
        return error.NoModuleName;
    const doc = if (cap.findChild("doc_block")) |db| builder.extractDoc(ctx, db) else null;
    return ctx.newNode(.{ .module_decl = .{ .name = builder.tokenText(ctx, name_pos), .doc = doc } });
}
```

- [ ] **Step 3: Build and run tests**

Run: `zig build 2>&1 | head -20 && ./testall.sh 2>&1 | tail -5`
Expected: Clean build, all tests pass

- [ ] **Step 4: Commit**

```bash
git add src/peg/builder_decls.zig
git commit -m "docgen: wire doc_block to blueprints and module_decl"
```

---

### Task 5: Wire #description metadata to module_decl.doc

**Files:**
- Modify: `src/peg/builder_decls.zig:24-66` (`buildProgram`)

`#description = "text"` is parsed as a metadata node with `field = "description"` and `value = string_literal`. In `buildProgram`, after building all nodes, scan metadata for `#description` and set it on the module node. `#description` takes precedence over `///` on the module declaration.

- [ ] **Step 1: Add #description extraction in buildProgram**

In `buildProgram`, after building the module node and before the return statement (before line 60), add:

```zig
    // Wire #description metadata to module_decl.doc (takes precedence over /// on module)
    for (metadata_list.items) |meta| {
        if (meta.* == .metadata) {
            if (std.mem.eql(u8, meta.metadata.field, "description")) {
                if (meta.metadata.value.* == .string_literal) {
                    const raw = meta.metadata.value.string_literal;
                    // Strip surrounding quotes
                    const text = if (raw.len >= 2 and raw[0] == '"') raw[1 .. raw.len - 1] else raw;
                    builder.setDoc(mod, text);
                }
                break;
            }
        }
    }
```

- [ ] **Step 2: Build and run tests**

Run: `zig build 2>&1 | head -20 && ./testall.sh 2>&1 | tail -5`
Expected: Clean build, all tests pass

- [ ] **Step 3: Commit**

```bash
git add src/peg/builder_decls.zig
git commit -m "docgen: wire #description metadata to module_decl.doc"
```

---

### Task 6: Fix output path and add -std flag

**Files:**
- Modify: `src/cli.zig:68-83` (CliArgs struct) and `src/cli.zig:157-184` (flag parsing)
- Modify: `src/commands.zig:145-198` (`runGendoc`)

- [ ] **Step 1: Add gen_std field to CliArgs**

In `src/cli.zig`, add `gen_std` field to the `CliArgs` struct after `init_in_place`:

```zig
    init_in_place: bool, // orhon init (no name) — init in current dir
    gen_std: bool,       // orhon gendoc -std — generate stdlib docs
```

- [ ] **Step 2: Initialize gen_std in the parse function**

Find where `CliArgs` is initialized (the `return .{` block) and add `gen_std = false`. Search for the initialization.

- [ ] **Step 3: Add -std flag parsing**

In the flag parsing loop (around line 180), add before the final `else`:

```zig
    } else if (std.mem.eql(u8, arg, "-std")) {
        cli.gen_std = true;
```

- [ ] **Step 4: Update help text**

In the help text (around line 209), update the gendoc line:

```zig
    \\  gendoc              Generate Markdown docs from /// comments (pub items)
    \\                        -std  Generate stdlib reference docs
```

- [ ] **Step 5: Fix output path and add -std mode in runGendoc**

Replace the output path section at the end of `runGendoc` (lines 193-197). The full updated `runGendoc`:

```zig
pub fn runGendoc(allocator: std.mem.Allocator, cli: *const _cli.CliArgs) !void {
    const docgen = @import("docgen.zig");

    // Ensure std files are available (parsing may discover std imports)
    try _std_bundle.ensureStdFiles(allocator);

    if (cli.gen_std) {
        // Generate stdlib docs from embedded .orh-cache/std/
        var reporter = errors.Reporter.init(allocator, .debug);
        defer reporter.deinit();

        var mod_resolver = module.Resolver.init(allocator, &reporter);
        defer mod_resolver.deinit();

        try mod_resolver.scanDirectory(cache.CACHE_DIR ++ "/std");

        if (reporter.hasErrors()) {
            try reporter.flush();
            return;
        }

        try mod_resolver.parseModules(allocator);
        if (reporter.hasErrors()) {
            try reporter.flush();
            return;
        }

        try docgen.generateDocs(allocator, &mod_resolver, "docs/std");
        return;
    }

    // Check source dir exists
    std.fs.cwd().access(cli.source_dir, .{}) catch {
        std.debug.print("error: source directory '{s}' not found\n", .{cli.source_dir});
        return;
    };

    var reporter = errors.Reporter.init(allocator, .debug);
    defer reporter.deinit();

    var mod_resolver = module.Resolver.init(allocator, &reporter);
    defer mod_resolver.deinit();

    try mod_resolver.scanDirectory(cli.source_dir);

    if (reporter.hasErrors()) {
        try reporter.flush();
        return;
    }

    // Parse all modules (two passes for std imports)
    try mod_resolver.parseModules(allocator);
    if (reporter.hasErrors()) {
        try reporter.flush();
        return;
    }
    // Second pass: parse any newly discovered std modules
    {
        var has_unparsed = false;
        var check_it = mod_resolver.modules.iterator();
        while (check_it.next()) |entry| {
            if (entry.value_ptr.ast == null) { has_unparsed = true; break; }
        }
        if (has_unparsed) {
            try mod_resolver.parseModules(allocator);
        }
    }

    if (reporter.hasErrors()) {
        try reporter.flush();
        return;
    }

    try docgen.generateDocs(allocator, &mod_resolver, "docs/api");
}
```

- [ ] **Step 6: Add cache import if not already present**

Check if `commands.zig` already imports `cache.zig`. If not, add:

```zig
const cache = @import("cache.zig");
```

- [ ] **Step 7: Build and run tests**

Run: `zig build 2>&1 | head -20 && ./testall.sh 2>&1 | tail -5`
Expected: Clean build, all tests pass

- [ ] **Step 8: Commit**

```bash
git add src/cli.zig src/commands.zig
git commit -m "docgen: fix output path, add -std flag for stdlib docs"
```

---

### Task 7: Add doc comments to example module and test

**Files:**
- Modify: `src/templates/example/example.orh` (add `///` doc comments to some pub items)

This validates the full pipeline: `///` → lexer → PEG → builder → docgen → markdown.

- [ ] **Step 1: Add doc comments to the example module**

Add `///` comments to a few pub declarations in the example module. Pick 2-3 existing pub functions and add doc comments above them. Also ensure the anchor file has `#description = "Language feature examples"`.

- [ ] **Step 2: Build the compiler and run orhon gendoc**

```bash
zig build && mkdir -p /tmp/orhon-doctest && cp -r src/templates/example /tmp/orhon-doctest/src && cd /tmp/orhon-doctest && orhon init . && orhon gendoc
```

Verify `docs/api/example.md` contains the doc comment text.

- [ ] **Step 3: Run the full test suite**

Run: `./testall.sh 2>&1 | tail -5`
Expected: All tests pass (example module must still compile)

- [ ] **Step 4: Commit**

```bash
git add src/templates/example/example.orh
git commit -m "docgen: add doc comments to example module"
```
