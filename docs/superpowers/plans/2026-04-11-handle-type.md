# Handle Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `handle` keyword to Orhon that declares nominally-typed opaque pointer types — safe, zero-cost, non-dereferenceable values.

**Architecture:** `handle Name` is a top-level type declaration (like `struct`, `enum`). It flows through PEG → AST → declarations → MIR → codegen, emitting `const Name = *anyopaque;` in Zig. The type system treats each handle as a distinct nominal type.

**Tech Stack:** Zig 0.15, PEG parser, existing compiler pipeline

---

## File Structure

| File | Role |
|------|------|
| `src/peg/orhon.peg` | Grammar rule for `handle_decl` |
| `src/lexer.zig` | `kw_handle` token kind + keyword map entry |
| `src/parser.zig` | `handle_decl` node kind + `HandleDecl` struct |
| `src/peg/builder_decls.zig` | `buildHandleDecl` builder function |
| `src/peg/builder.zig` | Dispatch table entry + `setPub`/`setDoc` support |
| `src/declarations.zig` | `HandleSig` + `handles` map in `DeclTable` + `collectHandle` |
| `src/mir/mir_node.zig` | `handle_def` MIR kind |
| `src/mir/mir_lowerer.zig` | Handle cases in lowering, population, kind mapping |
| `src/codegen/codegen.zig` | Dispatch `handle_def` to codegen |
| `src/codegen/codegen_decls.zig` | `generateHandleMir` — emits `const Name = *anyopaque;` |
| `src/resolver.zig` | Register handle as named type in scope |
| `src/templates/example/handles.orh` | Example module file |
| `src/init.zig` | Embed and write the example file |
| `test/fixtures/fail_handle.orh` | Negative test fixture |

---

### Task 1: Lexer — add `kw_handle` keyword

**Files:**
- Modify: `src/lexer.zig:33` (TokenKind enum)
- Modify: `src/lexer.zig:130` (KEYWORDS map)

- [ ] **Step 1: Add `kw_handle` to `TokenKind` enum**

In `src/lexer.zig`, add `kw_handle` after `kw_enum` (line 33):

```zig
    kw_enum,
    kw_handle,
    kw_defer,
```

- [ ] **Step 2: Add `"handle"` to `KEYWORDS` map**

In `src/lexer.zig`, add after the `"enum"` entry (line 130):

```zig
    .{ "enum",      .kw_enum },
    .{ "handle",    .kw_handle },
    .{ "defer",    .kw_defer },
```

- [ ] **Step 3: Verify it compiles**

Run: `zig build 2>&1 | head -20`
Expected: Build succeeds (no code references `kw_handle` yet, so no errors)

- [ ] **Step 4: Commit**

```bash
git add src/lexer.zig
git commit -m "feat: add kw_handle keyword token"
```

---

### Task 2: PEG Grammar — add `handle_decl` rule

**Files:**
- Modify: `src/peg/orhon.peg:41` (top_level_start)
- Modify: `src/peg/orhon.peg:70-79` (top_level_decl)
- Modify: `src/peg/orhon.peg:81-87` (pub_decl)
- Modify: `src/peg/orhon.peg:154` (add handle_decl rule after enum section)
- Modify: `src/peg/orhon.peg:574` (keywords comment)

- [ ] **Step 1: Add `'handle'` to `top_level_start` lookahead**

In `src/peg/orhon.peg` line 41, add `'handle'` to the list:

```
top_level_start
    <- 'func' / 'pub' / 'struct' / 'blueprint' / 'enum' / 'handle' / 'const' / 'var'
     / 'compt' / 'test' / 'import' / '#'
```

- [ ] **Step 2: Add `handle_decl` to `top_level_decl`**

In `src/peg/orhon.peg` lines 70-79, add `handle_decl` after `enum_decl`:

```
top_level_decl
    <- pub_decl
     / func_decl
     / compt_decl
     / struct_decl
     / blueprint_decl
     / enum_decl
     / handle_decl
     / const_decl
     / var_decl
     / test_decl
```

- [ ] **Step 3: Add `handle_decl` to `pub_decl`**

In `src/peg/orhon.peg` lines 81-87, add `handle_decl`:

```
pub_decl
    <- 'pub' (func_decl
            / struct_decl
            / blueprint_decl
            / enum_decl
            / handle_decl
            / const_decl
            / compt_decl)
```

- [ ] **Step 4: Add the `handle_decl` grammar rule**

After the enum section (after line 164), add:

```
# ============================================================
# HANDLE DECLARATIONS
# ============================================================

handle_decl
    <- 'handle' IDENTIFIER TERM  {label: "handle declaration"}
```

Note: `TERM` is the statement terminator (newline). This ensures `handle Foo` must be on its own line.

- [ ] **Step 5: Update keywords comment**

In `src/peg/orhon.peg` line 574, add `handle` to the keyword list:

```
# pub match struct enum handle defer null void compt
```

- [ ] **Step 6: Commit**

```bash
git add src/peg/orhon.peg
git commit -m "feat: add handle_decl grammar rule"
```

---

### Task 3: AST — add `HandleDecl` node

**Files:**
- Modify: `src/parser.zig:15-72` (NodeKind enum)
- Modify: `src/parser.zig:76-131` (Node union)
- Modify: `src/parser.zig:204-210` (add HandleDecl struct)

- [ ] **Step 1: Add `handle_decl` to `NodeKind` enum**

In `src/parser.zig`, add after `enum_decl` (line 23):

```zig
    enum_decl,
    handle_decl,
    var_decl,
```

- [ ] **Step 2: Add `handle_decl` to `Node` union**

In `src/parser.zig`, add after `enum_decl: EnumDecl` (line 84):

```zig
    enum_decl: EnumDecl,
    handle_decl: HandleDecl,
    var_decl: VarDecl,
```

- [ ] **Step 3: Add `HandleDecl` struct**

In `src/parser.zig`, add after `EnumDecl` (after line 210):

```zig
pub const HandleDecl = struct {
    name: []const u8,
    is_pub: bool,
    doc: ?[]const u8 = null,
};
```

- [ ] **Step 4: Verify it compiles**

Run: `zig build 2>&1 | head -20`
Expected: May get "unhandled switch" errors in files that switch on `NodeKind` — that's expected and will be fixed in subsequent tasks.

- [ ] **Step 5: Commit**

```bash
git add src/parser.zig
git commit -m "feat: add HandleDecl AST node"
```

---

### Task 4: PEG Builder — wire up `buildHandleDecl`

**Files:**
- Modify: `src/peg/builder_decls.zig:1-6` (header comment)
- Modify: `src/peg/builder_decls.zig:379` (add buildHandleDecl function)
- Modify: `src/peg/builder.zig:145` (dispatch table)
- Modify: `src/peg/builder.zig:430-439` (setPub)
- Modify: `src/peg/builder.zig:457-467` (setDoc)

- [ ] **Step 1: Add `buildHandleDecl` function**

In `src/peg/builder_decls.zig`, add after `buildEnumDecl` (after line 379):

```zig
pub fn buildHandleDecl(ctx: *BuildContext, cap: *const CaptureNode) !*Node {
    // handle_decl <- 'handle' IDENTIFIER TERM
    // The identifier is the token right after 'handle'
    var name: []const u8 = "";
    for (cap.start_pos..cap.end_pos) |i| {
        if (i < ctx.tokens.len and ctx.tokens[i].kind == .identifier) {
            name = ctx.tokens[i].text;
            break;
        }
    }
    return ctx.newNode(.{ .handle_decl = .{
        .name = name,
        .is_pub = false,
    } });
}
```

- [ ] **Step 2: Add dispatch table entry**

In `src/peg/builder.zig`, add after the `enum_decl` entry (line 145):

```zig
    .{ "enum_decl", decls_impl.buildEnumDecl },
    .{ "handle_decl", decls_impl.buildHandleDecl },
    .{ "field_decl", decls_impl.buildFieldDecl },
```

- [ ] **Step 3: Add `handle_decl` to `setPub`**

In `src/peg/builder.zig`, add to the `setPub` function switch (after line 435):

```zig
        .func_decl => |*d| d.is_pub = value,
        .struct_decl => |*d| d.is_pub = value,
        .blueprint_decl => |*d| d.is_pub = value,
        .enum_decl => |*d| d.is_pub = value,
        .handle_decl => |*d| d.is_pub = value,
        .var_decl => |*d| d.is_pub = value,
```

- [ ] **Step 4: Add `handle_decl` to `setDoc`**

In `src/peg/builder.zig`, add to the `setDoc` function switch (after line 462):

```zig
        .enum_decl => |*d| d.doc = doc,
        .handle_decl => |*d| d.doc = doc,
        .var_decl => |*d| d.doc = doc,
```

- [ ] **Step 5: Update header comment**

In `src/peg/builder_decls.zig` line 1-5, add `buildHandleDecl` to the comment:

```zig
// builder_decls.zig — Declaration builders for the PEG AST builder
// Contains: buildProgram, buildModuleDecl, buildImport, buildMetadata,
//           buildFuncDecl, buildParam, buildConstDecl, buildVarDecl,
//           buildStructDecl, buildBlueprintDecl, buildEnumDecl, buildHandleDecl,
//           buildFieldDecl, buildEnumVariant, buildDestructDecl, buildTestDecl,
//           buildPubDecl, buildComptDecl
```

- [ ] **Step 6: Verify it compiles**

Run: `zig build 2>&1 | head -20`
Expected: May still have unhandled switch errors in declarations/MIR/codegen/resolver — those are next.

- [ ] **Step 7: Commit**

```bash
git add src/peg/builder_decls.zig src/peg/builder.zig
git commit -m "feat: add buildHandleDecl builder and wire dispatch"
```

---

### Task 5: Declarations — register handle types

**Files:**
- Modify: `src/declarations.zig:46-51` (add HandleSig struct)
- Modify: `src/declarations.zig:74-84` (add handles field to DeclTable)
- Modify: `src/declarations.zig:92-103` (init)
- Modify: `src/declarations.zig:106-147` (deinit)
- Modify: `src/declarations.zig:149-155` (hasDecl)
- Modify: `src/declarations.zig:199-214` (collectTopLevel)
- Modify: `src/declarations.zig:427` (add collectHandle function)

- [ ] **Step 1: Add `HandleSig` struct**

In `src/declarations.zig`, add after `EnumSig` (after line 51):

```zig
/// A handle declaration summary
pub const HandleSig = struct {
    name: []const u8,
    is_pub: bool,
};
```

- [ ] **Step 2: Add `handles` field to `DeclTable`**

In `src/declarations.zig`, add after `enums` field (line 77):

```zig
    enums: std.StringHashMap(EnumSig),
    handles: std.StringHashMap(HandleSig),
    vars: std.StringHashMap(VarSig),
```

- [ ] **Step 3: Initialize `handles` in `init`**

In `src/declarations.zig`, add in the `init` function (after line 96):

```zig
            .enums = std.StringHashMap(EnumSig).init(allocator),
            .handles = std.StringHashMap(HandleSig).init(allocator),
            .vars = std.StringHashMap(VarSig).init(allocator),
```

- [ ] **Step 4: Deinit `handles` in `deinit`**

In `src/declarations.zig`, add after enum deinit (after line 126):

```zig
        self.enums.deinit();
        self.handles.deinit();
        self.vars.deinit();
```

Note: `HandleSig` has no owned slices, so no iteration/free needed — just `deinit()`.

- [ ] **Step 5: Add handles to `hasDecl`**

In `src/declarations.zig`, update `hasDecl` (lines 149-155):

```zig
    pub fn hasDecl(self: *const DeclTable, name: []const u8) bool {
        return self.funcs.contains(name) or
               self.structs.contains(name) or
               self.enums.contains(name) or
               self.handles.contains(name) or
               self.vars.contains(name) or
               self.types.contains(name);
    }
```

- [ ] **Step 6: Add `handle_decl` case to `collectTopLevel`**

In `src/declarations.zig`, add after `enum_decl` case (line 205):

```zig
            .enum_decl => |e| try self.collectEnum(e, loc),
            .handle_decl => |h| try self.collectHandle(h, loc),
            .var_decl => |v| {
```

- [ ] **Step 7: Add `collectHandle` function**

In `src/declarations.zig`, add after `collectEnum` (after line 427):

```zig
    fn collectHandle(self: *DeclCollector, h: parser.HandleDecl, loc: ?errors.SourceLoc) anyerror!void {
        if (self.table.handles.contains(h.name)) {
            try self.reporter.reportFmt(loc, "duplicate handle declaration: '{s}'", .{h.name});
            return;
        }
        try self.table.handles.put(h.name, .{
            .name = h.name,
            .is_pub = h.is_pub,
        });
    }
```

- [ ] **Step 8: Verify it compiles**

Run: `zig build 2>&1 | head -20`

- [ ] **Step 9: Commit**

```bash
git add src/declarations.zig
git commit -m "feat: register handle types in declaration pass"
```

---

### Task 6: MIR — add `handle_def` kind and lowering

**Files:**
- Modify: `src/mir/mir_node.zig:188` (MirKind enum)
- Modify: `src/mir/mir_lowerer.zig:106-108` (lowerNode children)
- Modify: `src/mir/mir_lowerer.zig:554-558` (populateData)
- Modify: `src/mir/mir_lowerer.zig:658` (astToMirKind)

- [ ] **Step 1: Add `handle_def` to `MirKind` enum**

In `src/mir/mir_node.zig`, add after `enum_def` (line 188):

```zig
    enum_def,
    handle_def,
    var_decl,
```

- [ ] **Step 2: Add handle case in lowerNode children**

In `src/mir/mir_lowerer.zig`, add after the `enum_decl` case (after line 108):

```zig
            .enum_decl => |e| {
                mir_node_ptr.children = try self.lowerSlice(e.members);
            },
            .handle_decl => {
                // No body to lower — handle has no members
                mir_node_ptr.children = &.{};
            },
            .field_decl => |f| {
```

- [ ] **Step 3: Add handle case in populateData**

In `src/mir/mir_lowerer.zig`, add after the `enum_decl` case (after line 558):

```zig
        .enum_decl => |e| {
            m.name = e.name;
            m.is_pub = e.is_pub;
            m.backing_type = e.backing_type;
        },
        .handle_decl => |h| {
            m.name = h.name;
            m.is_pub = h.is_pub;
        },
        .var_decl => |v| {
```

- [ ] **Step 4: Add handle case in astToMirKind**

In `src/mir/mir_lowerer.zig`, add after the `enum_decl` mapping (line 658):

```zig
        .enum_decl => .enum_def,
        .handle_decl => .handle_def,
        .field_decl => .field_def,
```

- [ ] **Step 5: Verify it compiles**

Run: `zig build 2>&1 | head -20`

- [ ] **Step 6: Commit**

```bash
git add src/mir/mir_node.zig src/mir/mir_lowerer.zig
git commit -m "feat: add handle_def MIR kind and lowering"
```

---

### Task 7: Codegen — emit `const Name = *anyopaque;`

**Files:**
- Modify: `src/codegen/codegen_decls.zig:305` (add generateHandleMir)
- Modify: `src/codegen/codegen.zig:392` (dispatch in generateTopLevelMir)
- Modify: `src/codegen/codegen.zig:429` (add forwarding stub)

- [ ] **Step 1: Add `generateHandleMir` in codegen_decls.zig**

In `src/codegen/codegen_decls.zig`, add after `generateEnumMir` (after line 305):

```zig
// ============================================================
// HANDLES
// ============================================================

/// MIR-path handle codegen — emits `const Name = *anyopaque;`
pub fn generateHandleMir(cg: *CodeGen, m: *mir.MirNode) anyerror!void {
    const handle_name = m.name orelse return;
    if (cg.is_zig_module) return cg.generateZigReExport(handle_name, m.is_pub);

    if (m.is_pub) try cg.emit("pub ");
    try cg.emitFmt("const {s} = *anyopaque;\n", .{handle_name});
}
```

- [ ] **Step 2: Add dispatch in `generateTopLevelMir`**

In `src/codegen/codegen.zig`, add after the `enum_def` case (line 392):

```zig
            .enum_def => try self.generateEnumMir(m),
            .handle_def => try self.generateHandleMir(m),
            .var_decl => try self.generateTopLevelDeclMir(m),
```

- [ ] **Step 3: Add forwarding stub in codegen.zig**

In `src/codegen/codegen.zig`, add after `generateEnumMir` stub (after line 429):

```zig
    // ============================================================
    // HANDLES
    // ============================================================

    /// MIR-path handle codegen — emits const Name = *anyopaque;
    pub fn generateHandleMir(self: *CodeGen, m: *mir.MirNode) anyerror!void { return decls_impl.generateHandleMir(self, m); }
```

- [ ] **Step 4: Verify it compiles**

Run: `zig build 2>&1 | head -20`

- [ ] **Step 5: Commit**

```bash
git add src/codegen/codegen_decls.zig src/codegen/codegen.zig
git commit -m "feat: handle codegen — emit const Name = *anyopaque"
```

---

### Task 8: Resolver — register handle as named type

**Files:**
- Modify: `src/resolver.zig:138-160` (registerDecl)
- Modify: `src/resolver.zig:163-262` (resolveNode)

- [ ] **Step 1: Add handle to `registerDecl`**

In `src/resolver.zig`, add after the `enum_decl` case (after line 148):

```zig
            .enum_decl => |e| {
                try scope.define(e.name, RT{ .named = e.name });
                for (e.members) |member| {
                    if (member.* == .enum_variant) {
                        try scope.define(member.enum_variant.name, RT{ .named = e.name });
                    }
                }
            },
            .handle_decl => |h| {
                try scope.define(h.name, RT{ .named = h.name });
            },
            .blueprint_decl => |b| {
```

- [ ] **Step 2: Add handle to `resolveNode`**

In `src/resolver.zig`, find where `enum_decl` and `blueprint_decl` are handled in `resolveNode`. Add a no-op case for `handle_decl` (handle has no body to resolve):

```zig
            .enum_decl => {},
            .handle_decl => {},
            .blueprint_decl => |b| {
```

Note: Search the `resolveNode` switch for where `.enum_decl => {}` appears (it's a passthrough since enum members are already collected). Handle gets the same treatment.

- [ ] **Step 3: Verify it compiles**

Run: `zig build 2>&1 | head -30`
Expected: Might still have unhandled switch warnings elsewhere. Check and fix any remaining switches that need a `handle_decl` or `handle_def` case.

- [ ] **Step 4: Fix any remaining unhandled switches**

Search for compile errors mentioning `handle_decl` or `handle_def`. Common places:
- Any other file that switches on `NodeKind` or `MirKind`
- LSP analysis, formatter, or other passes

For each, add the appropriate case — typically `.handle_decl => {}` or `.handle_def => {}` for passes that don't need to do anything with handles.

- [ ] **Step 5: Run full build**

Run: `zig build 2>&1 | head -30`
Expected: Clean build with no errors.

- [ ] **Step 6: Commit**

```bash
git add src/resolver.zig
git commit -m "feat: register handle types in resolver scope"
```

If other files needed fixes in step 4:

```bash
git add -u
git commit -m "fix: add handle_decl/handle_def cases to remaining switches"
```

---

### Task 9: Test — basic handle parsing and codegen

**Files:**
- Create: `test/fixtures/handle_basic.orh`

- [ ] **Step 1: Create test fixture**

Create `test/fixtures/handle_basic.orh`:

```
module handle_basic

handle WindowHandle
pub handle DeviceHandle

func get_handle() WindowHandle {
    return @cast(0)
}

func use_handle(h: WindowHandle) i32 {
    return 42
}

test "handle pass through" {
    const h = get_handle()
    const result = use_handle(h)
    @assert(result == 42)
}
```

Note: `@cast(0)` is used to create a handle value in tests — in real code, handles come from Zig FFI. This is the simplest way to test the pipeline end-to-end.

- [ ] **Step 2: Run the fixture through the compiler**

```bash
cd /tmp && rm -rf handle_test && mkdir -p handle_test/src
cp test/fixtures/handle_basic.orh handle_test/src/handle_basic.orh
cd handle_test
orhon build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Verify generated Zig**

```bash
cat handle_test/zig-out/generated/handle_basic.zig
```

Expected output should contain:
- `const WindowHandle = *anyopaque;`
- `pub const DeviceHandle = *anyopaque;`

- [ ] **Step 4: Run the tests**

```bash
orhon test 2>&1
```

Expected: Test passes.

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/handle_basic.orh
git commit -m "test: basic handle parsing and codegen fixture"
```

---

### Task 10: Test — negative cases (duplicate handle, type mismatch)

**Files:**
- Create: `test/fixtures/fail_handle.orh`
- Modify: `test/11_errors.sh` (add run_fixture call)

- [ ] **Step 1: Create negative test fixture**

Create `test/fixtures/fail_handle.orh`:

```
module fail_handle

handle Foo
handle Foo
```

- [ ] **Step 2: Add to error test suite**

In `test/11_errors.sh`, add after the enum errors section (after line 376):

```bash
# handle errors
run_fixture neg_handle_dup fail_handle.orh "duplicate handle" "fixture: catches duplicate handle declaration"
```

- [ ] **Step 3: Run the error tests**

Run: `bash test/11_errors.sh 2>&1 | tail -20`
Expected: `PASS fixture: catches duplicate handle declaration`

- [ ] **Step 4: Commit**

```bash
git add test/fixtures/fail_handle.orh test/11_errors.sh
git commit -m "test: negative test for duplicate handle declaration"
```

---

### Task 11: Example module — add `handles.orh`

**Files:**
- Create: `src/templates/example/handles.orh`
- Modify: `src/init.zig:19` (add embed constant)
- Modify: `src/init.zig:73-81` (add to example_files tuple)
- Modify: `src/init.zig:99` (update file count in message)

- [ ] **Step 1: Create the example file**

Create `src/templates/example/handles.orh`:

```
module example

// ─── Handle Types ──────────────────────────────────────────────────────────────

// handles are opaque pointer types — safe, nominally typed, zero cost
// you can store them, pass them, return them, but never dereference or cast them
// each handle is its own type: ResourceHandle ≠ ConnectionHandle

handle ResourceHandle
handle ConnectionHandle

// handles work as function parameters and return types

func create_resource() ResourceHandle {
    return @cast(0)
}

func use_resource(r: ResourceHandle) i32 {
    return 1
}

func release_resource(r: ResourceHandle) () {
    _ = r
}

// handles compose with optionals

func try_connect() (null | ConnectionHandle) {
    return null
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "handle round trip" {
    const r = create_resource()
    @assert(use_resource(r) == 1)
}

test "optional handle" {
    const conn = try_connect()
    @assert(conn == null)
}
```

- [ ] **Step 2: Add embed constant in init.zig**

In `src/init.zig`, add after `BLUEPRINTS_TEMPLATE` (line 19):

```zig
const BLUEPRINTS_TEMPLATE       = @embedFile("templates/example/blueprints.orh");
const HANDLES_TEMPLATE          = @embedFile("templates/example/handles.orh");
```

- [ ] **Step 3: Add to example_files tuple**

In `src/init.zig`, add to the `example_files` tuple (after line 80):

```zig
        .{ "blueprints.orh",    BLUEPRINTS_TEMPLATE },
        .{ "handles.orh",       HANDLES_TEMPLATE },
    };
```

- [ ] **Step 4: Update file count in output message**

In `src/init.zig`, update line 99:

```zig
    std.debug.print("  {s}/src/example/  (8 files — language manual)\n", .{base});
```

- [ ] **Step 5: Verify build**

Run: `zig build 2>&1 | head -20`
Expected: Clean build.

- [ ] **Step 6: Test that `orhon init` includes the new file**

```bash
cd /tmp && rm -rf handle_init_test
orhon init handle_init_test 2>&1
ls handle_init_test/src/example/handles.orh
```

Expected: File exists.

- [ ] **Step 7: Test that the example project builds**

```bash
cd /tmp/handle_init_test && orhon build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 8: Commit**

```bash
git add src/templates/example/handles.orh src/init.zig
git commit -m "feat: add handles.orh example module"
```

---

### Task 12: Full test suite

- [ ] **Step 1: Run the full test suite**

Run: `./testall.sh 2>&1 | tail -40`
Expected: All stages pass.

- [ ] **Step 2: If any failures, fix them**

Read `test_log.txt` for details on failures. Common issues:
- Missing `handle_decl` or `handle_def` case in a switch somewhere
- PEG grammar rule not matching (check TERM placement)
- Test fixture issues

- [ ] **Step 3: Commit any fixes**

```bash
git add -u
git commit -m "fix: resolve test suite failures for handle type"
```
