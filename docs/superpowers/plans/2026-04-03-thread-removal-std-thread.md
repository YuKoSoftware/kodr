# Thread Removal + std::thread Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `thread` keyword, Handle(T) CoreType, thread_safety.zig pass, and all thread codegen from the compiler. Replace `src/std/async.zig` with `src/std/thread.zig` providing Thread(T), Atomic(T), Mutex, and a convenience spawn() function.

**Architecture:** Pure removal from compiler (grammar, parser, builder, codegen, types, MIR, resolver, LSP, cache, pipeline, thread_safety pass) + replacement of async.zig with thread.zig in std. CoreType struct is fully eliminated. Existing ownership + borrow checkers cover thread safety.

**Tech Stack:** Zig 0.15.2+, Orhon compiler pipeline, shell test scripts.

---

### Task 1: Remove thread keyword from grammar and parser

**Files:**
- Modify: `src/peg/orhon.peg:40-101`
- Modify: `src/parser.zig:186-190`
- Modify: `src/peg/builder_decls.zig:519-538`
- Modify: `src/peg/builder.zig:152,338,346`

- [ ] **Step 1: Remove thread from PEG grammar**

In `src/peg/orhon.peg`:

Remove `/ 'thread'` from the `top_level_start` rule (line 42). Change:

```
top_level_start
    <- 'func' / 'pub' / 'struct' / 'blueprint' / 'enum' / 'const' / 'var'
     / 'thread' / 'compt' / 'test' / 'import' / '#'
```

to:

```
top_level_start
    <- 'func' / 'pub' / 'struct' / 'blueprint' / 'enum' / 'const' / 'var'
     / 'compt' / 'test' / 'import' / '#'
```

Remove `/ thread_decl` from `top_level_decl` (line 74). Change:

```
top_level_decl
    <- pub_decl
     / func_decl
     / thread_decl
     / compt_decl
```

to:

```
top_level_decl
    <- pub_decl
     / func_decl
     / compt_decl
```

Remove `/ thread_decl` from `pub_decl` (line 85). Change:

```
pub_decl
    <- 'pub' (func_decl
            / thread_decl
            / struct_decl
```

to:

```
pub_decl
    <- 'pub' (func_decl
            / struct_decl
```

Delete the `thread_decl` rule entirely (lines 100-101):

```
thread_decl
    <- 'thread' func_name '(' _ param_list _ ')' type block  {label: "thread declaration"}
```

- [ ] **Step 2: Remove FuncContext.thread from parser**

In `src/parser.zig`, change the FuncContext enum (lines 186-190) from:

```zig
pub const FuncContext = enum {
    normal,
    compt,
    thread, // thread declaration — generates spawn wrapper + body
};
```

to:

```zig
pub const FuncContext = enum {
    normal,
    compt,
};
```

- [ ] **Step 3: Remove buildThreadDecl from builder**

In `src/peg/builder_decls.zig`, delete the entire `buildThreadDecl` function (lines 519-538).

In `src/peg/builder.zig`, remove the thread_decl dispatch entry (line 152):

```zig
    .{ "thread_decl", decls_impl.buildThreadDecl },
```

Also in builder.zig, remove `"thread_decl"` from the boundary check around lines 338-346. Find the line:

```zig
                std.mem.eql(u8, r, "thread_decl") or
```

and remove it.

- [ ] **Step 4: Commit**

```bash
git add src/peg/orhon.peg src/parser.zig src/peg/builder_decls.zig src/peg/builder.zig
git commit -m "refactor: remove thread keyword from grammar and parser

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Remove Handle and CoreType from compiler

**Files:**
- Modify: `src/builtins.zig:9,16`
- Modify: `src/types.zig:165-370,488-499`
- Modify: `src/mir/mir_types.zig:20,34-39`
- Modify: `src/mir/mir_annotator.zig:194`
- Modify: `src/resolver.zig:475-548,573-576`
- Modify: `src/lsp/lsp_analysis.zig:56-60`
- Modify: `src/cache.zig:571-575`

- [ ] **Step 1: Remove Handle from builtins**

In `src/builtins.zig`, remove `"Handle"` from the BUILTIN_TYPES array:

```zig
pub const BUILTIN_TYPES = [_][]const u8{
    "Error",
    "Vector",
};
```

Remove `BT.HANDLE` constant:

```zig
pub const BT = struct {
    pub const ERROR = "Error";
    pub const VECTOR = "Vector";
};
```

- [ ] **Step 2: Remove CoreType entirely from types.zig**

In `src/types.zig`:

Delete the `CoreType` struct (lines 199-209) entirely.

Remove `.core_type: CoreType` from the `ResolvedType` union (line 168). The line `core_type: CoreType,` is deleted.

Delete the `isCoreType()` method (lines 257-263):
```zig
    pub fn isCoreType(self: ResolvedType, kind: CoreType.Kind) bool {
        return switch (self) {
            .core_type => |ct| ct.kind == kind,
            else => false,
        };
    }
```

Delete the `coreInner()` method (lines 265-271):
```zig
    pub fn coreInner(self: ResolvedType) ?*const ResolvedType {
        return switch (self) {
            .core_type => |ct| ct.inner,
            else => null,
        };
    }
```

Remove the `.core_type` branch from the `name()` method (around line 284-286):
```zig
            .core_type => |ct| switch (ct.kind) {
                .handle => "Handle(T)",
            },
```

In `resolveTypeNode()`, remove the Handle detection. The current code (around lines 350-367) checks for BT.HANDLE and creates a core_type. Remove the entire `core_kind` logic:

```zig
    const core_kind: ?ResolvedType.CoreType.Kind = if (std.mem.eql(u8, g.name, builtins.BT.HANDLE))
        .handle
    else
        null;

    if (core_kind) |kind| {
        if (g.args.len > 0) {
            const inner = try alloc.create(ResolvedType);
            inner.* = try resolveTypeNode(alloc, g.args[0]);
            return .{ .core_type = .{ .kind = kind, .inner = inner } };
        }
        return .unknown;
    }
```

This block is removed entirely. The generic type will fall through to the normal `.generic` handling below it.

Delete the CoreType test block (around lines 488-499).

- [ ] **Step 3: Remove thread_handle from MIR**

In `src/mir/mir_types.zig`, remove `thread_handle` from TypeClass:

```zig
pub const TypeClass = enum {
    plain,
    error_union,
    null_union,
    arbitrary_union,
    string,
};
```

In `classifyType()`, the `.generic` arm no longer checks for Handle. Remove:

```zig
            if (std.mem.eql(u8, g.name, builtins.BT.HANDLE))
                return .thread_handle;
```

Remove the entire `.core_type` arm from classifyType() since CoreType no longer exists.

- [ ] **Step 4: Remove core_type from mir_annotator, resolver, LSP, cache**

In `src/mir/mir_annotator.zig`, remove the core_type comparison (line 194):
```zig
        if (a == .core_type and b == .core_type) return a.core_type.kind == b.core_type.kind;
```

In `src/resolver.zig`, delete `coreTypeName()` entirely (lines 573-576).

Remove the two core_type compatibility blocks in `typesCompatible()` (lines 537-548):
```zig
    if (a == .core_type) {
        const wrapper_name = coreTypeName(a.core_type.kind);
        ...
    }
    if (b == .core_type) {
        const wrapper_name = coreTypeName(b.core_type.kind);
        ...
    }
```

Remove the `.core_type` branch in `typesMatchWithSubstitution()` (lines 475-483).

In `src/lsp/lsp_analysis.zig`, remove the entire `.core_type` branch from `formatType()` (lines 56-66).

In `src/cache.zig`, remove the `.core_type` branch from `hashResolvedType()` (lines 571-575).

- [ ] **Step 5: Commit**

```bash
git add src/builtins.zig src/types.zig src/mir/mir_types.zig src/mir/mir_annotator.zig src/resolver.zig src/lsp/lsp_analysis.zig src/cache.zig
git commit -m "refactor: remove Handle CoreType — CoreType struct fully eliminated

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Remove thread codegen and thread safety pass

**Files:**
- Modify: `src/codegen/codegen_decls.zig:37,131-217`
- Modify: `src/codegen/codegen.zig:284-285,607-612`
- Delete: `src/thread_safety.zig`
- Modify: `src/pipeline_passes.zig:12,127-131`
- Modify: `src/pipeline.zig:36-40`
- Modify: `src/mir/mir_node.zig:60`
- Modify: `src/mir/mir_lowerer.zig:539`

- [ ] **Step 1: Remove thread codegen from codegen_decls.zig**

Remove the thread dispatch (line 37):
```zig
    // Thread function — generate body + spawn wrapper
    if (m.is_thread) return cg.generateThreadFuncMir(m);
```

Delete the entire `generateThreadFuncMir` function (lines 131-217).

- [ ] **Step 2: Remove Handle from codegen.zig**

Remove the `_orhon_async` import emission (lines 284-285):
```zig
        // Handle(T) is now in std::async — no injected helper needed
        try self.emit("const _orhon_async = @import(\"_orhon_async\");\n");
```

Remove the Handle branch from `typeToZig()` (lines 607-612):
```zig
                } else if (std.mem.eql(u8, g.name, builtins.BT.HANDLE)) {
                    // Handle(T) → _orhon_async.Handle(zigT) (from std::async)
                    if (g.args.len > 0) {
                        const inner = try self.typeToZig(g.args[0]);
                        break :blk try self.allocTypeStr("_orhon_async.Handle({s})", .{inner});
                    }
                }
```

- [ ] **Step 3: Remove is_thread from MIR**

In `src/mir/mir_node.zig`, remove the `is_thread` field (line 60):
```zig
    is_thread: bool = false,
```

In `src/mir/mir_lowerer.zig`, remove the thread context assignment (line 539):
```zig
            m.is_thread = (f.context == .thread);
```

- [ ] **Step 4: Delete thread_safety.zig**

```bash
rm src/thread_safety.zig
```

- [ ] **Step 5: Remove thread safety pass from pipeline**

In `src/pipeline_passes.zig`, remove the import (line 12):
```zig
const thread_safety = @import("thread_safety.zig");
```

Remove the pass 8 invocation (lines 127-131):
```zig
    // ── Pass 8: Thread Safety ──────────────────────────────
    var thread_checker = thread_safety.ThreadSafetyChecker.init(allocator, &sema_ctx);
    defer thread_checker.deinit();
    try thread_checker.check(ast);
    if (reporter.hasErrors()) return null;
```

- [ ] **Step 6: Remove _orhon_async generation from pipeline.zig**

In `src/pipeline.zig`, remove the async.zig copy block (lines 36-40):
```zig
    {
        const file = try std.fs.cwd().createFile(cache.GENERATED_DIR ++ "/_orhon_async.zig", .{});
        defer file.close();
        try file.writeAll(_std_bundle.ASYNC_ZIG);
    }
```

- [ ] **Step 7: Commit**

```bash
git add src/codegen/codegen_decls.zig src/codegen/codegen.zig src/mir/mir_node.zig src/mir/mir_lowerer.zig src/pipeline_passes.zig src/pipeline.zig
git rm src/thread_safety.zig
git commit -m "refactor: remove thread codegen, thread safety pass, and _orhon_async

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Create std::thread module

**Files:**
- Create: `src/std/thread.zig`
- Delete: `src/std/async.zig`
- Modify: `src/std_bundle.zig:10,60-61`

- [ ] **Step 1: Create src/std/thread.zig**

```zig
// thread.zig — Threading primitives for Orhon std::thread
//
// Thread(T) — spawn a thread, join for result
// Atomic(T) — lock-free atomic operations
// Mutex      — mutual exclusion lock
// spawn()    — convenience function, infers return type

const std = @import("std");

/// Spawn a thread running func with the given args. Returns Thread(T)
/// where T is the return type of func. Convenience shorthand for
/// Thread(T).spawn(func, args).
pub fn spawn(comptime func: anytype, args: anytype) Thread(@typeInfo(@TypeOf(func)).@"fn".return_type.?) {
    return Thread(@typeInfo(@TypeOf(func)).@"fn".return_type.?).spawn(func, args);
}

/// A thread handle that joins and returns a result of type T.
pub fn Thread(comptime T: type) type {
    return struct {
        handle: std.Thread,
        state: *SharedState,

        const SharedState = struct {
            result: T = undefined,
            completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        };

        const Self = @This();

        /// Spawn a new thread running func with args.
        pub fn spawn(comptime func: anytype, args: anytype) Self {
            const state = std.heap.page_allocator.create(SharedState) catch
                @panic("Out of memory: thread state allocation");
            state.* = .{};

            const Args = @TypeOf(args);
            const Wrapper = struct {
                fn run(s: *SharedState, a: Args) void {
                    const result = @call(.auto, func, a);
                    if (T != void) s.result = result;
                    s.completed.store(true, .release);
                }
            };

            const thread = std.Thread.spawn(.{}, Wrapper.run, .{ state, args }) catch
                |e| @panic(@errorName(e));

            return .{ .handle = thread, .state = state };
        }

        /// Block until the thread completes and return its result.
        pub fn join(self: *Self) T {
            self.handle.join();
            const result = if (T != void) self.state.result else {};
            std.heap.page_allocator.destroy(self.state);
            return result;
        }

        /// Check if the thread has completed without blocking.
        pub fn done(self: *const Self) bool {
            return self.state.completed.load(.acquire);
        }
    };
}

/// Lock-free atomic wrapper over type T using sequential consistency.
pub fn Atomic(comptime T: type) type {
    return struct {
        inner: std.atomic.Value(T),

        const Self = @This();

        /// Creates a new atomic with the given initial value.
        pub fn new(initial: T) Self {
            return .{ .inner = std.atomic.Value(T).init(initial) };
        }

        /// Atomically loads and returns the current value.
        pub fn load(self: *const Self) T {
            return self.inner.load(.seq_cst);
        }

        /// Atomically stores a new value.
        pub fn store(self: *Self, val: T) void {
            self.inner.store(val, .seq_cst);
        }

        /// Atomically swaps the value and returns the previous one.
        pub fn exchange(self: *Self, val: T) T {
            return self.inner.swap(val, .seq_cst);
        }

        /// Atomically adds val and returns the previous value.
        pub fn fetchAdd(self: *Self, val: T) T {
            return self.inner.fetchAdd(val, .seq_cst);
        }

        /// Atomically subtracts val and returns the previous value.
        pub fn fetchSub(self: *Self, val: T) T {
            return self.inner.fetchSub(val, .seq_cst);
        }
    };
}

/// Mutual exclusion lock. Wraps std.Thread.Mutex.
pub const Mutex = struct {
    inner: std.Thread.Mutex = .{},

    /// Create a new unlocked mutex.
    pub fn new() Mutex {
        return .{ .inner = .{} };
    }

    /// Acquire the lock. Blocks if already held.
    pub fn lock(self: *Mutex) void {
        self.inner.lock();
    }

    /// Release the lock.
    pub fn unlock(self: *Mutex) void {
        self.inner.unlock();
    }
};
```

- [ ] **Step 2: Delete async.zig and update std_bundle.zig**

```bash
rm src/std/async.zig
```

In `src/std_bundle.zig`, replace the ASYNC_ZIG embed (line 10):

```zig
pub const ASYNC_ZIG  = @embedFile("std/async.zig");
```

with:

```zig
const THREAD_ZIG = @embedFile("std/thread.zig");
```

Note: change `pub const` to just `const` since the pipeline no longer needs to access it externally (no more `_orhon_async` copy).

In the files array in `ensureStdFiles()`, replace the async entry (line 60-61):

```zig
        .{ .name = "async.zig",       .content = ASYNC_ZIG },
```

with:

```zig
        .{ .name = "thread.zig",      .content = THREAD_ZIG },
```

- [ ] **Step 3: Update pipeline.zig ASYNC_ZIG reference**

Check that `src/pipeline.zig` no longer references `ASYNC_ZIG` (should have been removed in Task 3 Step 6). If any references remain to `_std_bundle.ASYNC_ZIG`, remove them.

- [ ] **Step 4: Build the compiler**

Run: `zig build 2>&1 | head -20`
Expected: Clean build.

- [ ] **Step 5: Commit**

```bash
git add src/std/thread.zig src/std_bundle.zig
git rm src/std/async.zig
git commit -m "feat: add std::thread module — Thread(T), Atomic(T), Mutex, spawn()

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Update tests

**Files:**
- Modify: `test/fixtures/tester.orh:1283-1382`
- Modify: `test/fixtures/tester_main.orh:546-604`
- Delete: `test/fixtures/fail_threads.orh`
- Modify: `test/10_runtime.sh:49-50`
- Modify: `test/11_errors.sh:105-125,397-401`

- [ ] **Step 1: Rewrite thread tests in tester.orh**

In `test/fixtures/tester.orh`, replace the threading section (lines 1283-1344) with:

```orh
// ─── Threading ───────────────────────────────────────────────

import std::thread

// regular functions — any function can be spawned as a thread

func doubler(x: i32) i32 {
    return x * 2
}

func adder(a: i32, b: i32) i32 {
    return a + b
}

func noop_work() void {
}

// single thread spawn + .join()

pub func test_thread() i32 {
    var t: thread.Thread(i32) = thread.spawn(doubler, 21)
    return t.join()
}

// two concurrent threads

pub func test_thread_multi() i32 {
    var a: thread.Thread(i32) = thread.spawn(doubler, 10)
    var b: thread.Thread(i32) = thread.spawn(doubler, 15)
    const r1: i32 = a.join()
    const r2: i32 = b.join()
    return r1 + r2
}

// thread with multiple params

pub func test_thread_params() i32 {
    var t: thread.Thread(i32) = thread.spawn(adder, 17, 25)
    return t.join()
}

// void thread

pub func test_thread_void() i32 {
    var t: thread.Thread(void) = thread.spawn(noop_work)
    t.join()
    return 1
}

// .done() non-blocking check

pub func test_thread_done() i32 {
    var t: thread.Thread(i32) = thread.spawn(doubler, 5)
    const result: i32 = t.join()
    return result
}

// join discards result for non-void

pub func test_thread_join() i32 {
    var t: thread.Thread(i32) = thread.spawn(doubler, 99)
    t.join()
    return 1
}
```

Replace the atomics section (lines 1346-1382) with:

```orh
// ─── Atomics ────────────────────────────────────────────────

// Atomic(T) — lock-free shared state (from std::thread)

pub func test_atomic() i32 {
    var a: thread.Atomic(i32) = thread.Atomic(i32).new(0)
    a.store(42)
    return a.load()
}

// atomic fetch operations

pub func test_atomic_fetch() i32 {
    var a: thread.Atomic(i32) = thread.Atomic(i32).new(10)
    a.fetchAdd(5)
    a.fetchSub(3)
    return a.load()
}

// atomic swap

pub func test_atomic_swap() i32 {
    var a: thread.Atomic(i32) = thread.Atomic(i32).new(100)
    const old: i32 = a.exchange(200)
    return old
}

// atomic bool — the pattern used for thread cancellation flags

pub func test_atomic_bool() i32 {
    var flag: thread.Atomic(bool) = thread.Atomic(bool).new(false)
    flag.store(true)
    if (flag.load()) {
        return 1
    }
    return 0
}
```

- [ ] **Step 2: Update tester_main.orh**

The tester_main.orh calls thread test functions and checks return values. The function signatures and return values are the same, so no changes should be needed to the call site patterns. Verify this — if the function names or return values changed, update accordingly.

- [ ] **Step 3: Delete fail_threads.orh and remove thread error tests**

```bash
rm test/fixtures/fail_threads.orh
```

In `test/11_errors.sh`, remove the inline unjoined thread test (lines 105-125):

```bash
# unjoined thread error
cd "$TESTDIR"
mkdir -p neg_thread/src
cat > neg_thread/src/neg_thread.orh <<'ORHON'
module neg_thread
#name    = "neg_thread"
#version = (1, 0, 0)
#build   = exe

thread worker(x: i32) Handle(i32) {
    return Handle(x * 2)
}

func main() void {
    const h: Handle(i32) = worker(42)
}
ORHON
cd neg_thread
NEG_OUT=$("$ORHON" build 2>&1 || true)
if echo "$NEG_OUT" | grep -qi "must be joined"; then pass "rejects unjoined thread"
else fail "rejects unjoined thread" "$NEG_OUT"; fi
```

Remove the thread safety fixture tests (lines 397-401):

```bash
# thread safety errors
run_fixture neg_thread2 fail_threads.orh "must be joined" "fixture: catches unjoined thread"
run_fixture neg_thread_move fail_threads.orh "moved into thread" "fixture: catches use after move into thread"
run_fixture neg_thread_freeze fail_threads.orh "cannot mutate.*borrowed by thread" "fixture: catches frozen var mutation"
run_fixture neg_thread_mutborrow fail_threads.orh "cannot pass mutable borrow to thread" "fixture: catches mutable borrow to thread"
```

- [ ] **Step 4: Commit**

```bash
git add test/fixtures/tester.orh test/fixtures/tester_main.orh test/10_runtime.sh test/11_errors.sh
git rm test/fixtures/fail_threads.orh
git commit -m "test: rewrite thread tests for std::thread, remove thread safety error tests

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Update example module and docs

**Files:**
- Modify: `src/templates/example/advanced.orh:58-107,231-233`
- Modify: `docs/TODO.md`

- [ ] **Step 1: Update example module**

In `src/templates/example/advanced.orh`, replace the thread section (around lines 58-98) with:

```orh
// ─── Threading ──────────────────────────────────────────────────────────────

// Threading is provided by std::thread — not a language builtin.
// Any function can be spawned as a thread.

import std::thread

func doubler(x: i32) i32 {
    return x * 2
}

func noop_work() void {
}

// thread.spawn() starts a thread, returns Thread(T)

func thread_demo() i32 {
    var t: thread.Thread(i32) = thread.spawn(doubler, 21)
    return t.join()
}

// multiple concurrent threads

func thread_multi() i32 {
    var a: thread.Thread(i32) = thread.spawn(doubler, 10)
    var b: thread.Thread(i32) = thread.spawn(doubler, 15)
    const r1: i32 = a.join()
    const r2: i32 = b.join()
    return r1 + r2
}

// void thread

func thread_void() i32 {
    var t: thread.Thread(void) = thread.spawn(noop_work)
    t.join()
    return 1
}

func thread_join() i32 {
    var t: thread.Thread(i32) = thread.spawn(doubler, 42)
    t.join()
    return 1
}
```

Replace the atomics section (around lines 100-107) with:

```orh
// ─── Atomics ────────────────────────────────────────────────────────────────

// Atomic(T) — lock-free atomic value for thread-safe shared state (from std::thread)

func atomic_demo() i32 {
    var counter: thread.Atomic(i32) = thread.Atomic(i32).new(0)
    counter.store(42)
    return counter.load()
}
```

Keep the test blocks but update the thread test (around line 231):

```orh
test "thread" {
    @assert(thread_demo() == 42)
}
```

- [ ] **Step 2: Update docs/TODO.md**

Mark thread codegen simplification as done. Change:

```markdown
### Thread codegen simplification `medium`

- Currently the compiler generates a complex spawn wrapper in `codegen_decls.zig`
  (SharedState allocation, thread spawn, closure capture)
- Should be much simpler — a thin mapping to Zig's `std.Thread.spawn` that lives
  mostly in `std::async`, not in the codegen
- The `thread` keyword can stay as syntax, but the heavy lifting should move to a
  library function like `async.spawn()` that the codegen just calls
```

to:

```markdown
### ~~Thread codegen simplification~~ — done (v0.18.0)
`thread` keyword removed. Threading moved to `std::thread`. thread_safety.zig deleted.
```

- [ ] **Step 3: Commit**

```bash
git add src/templates/example/advanced.orh docs/TODO.md
git commit -m "docs: update thread documentation and examples for std::thread

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Clear cache and run full test suite

**Files:** None (verification only)

- [ ] **Step 1: Clear the build cache**

```bash
rm -rf .orh-cache
```

- [ ] **Step 2: Build the compiler**

```bash
zig build 2>&1 | head -20
```

Expected: Clean build, no errors.

- [ ] **Step 3: Run unit tests**

```bash
zig build test 2>&1 | head -50
```

Expected: All unit tests pass. No references to removed symbols.

- [ ] **Step 4: Run the full test suite**

```bash
./testall.sh
```

Expected: All tests pass. Thread tests should work via std::thread. Atomic tests unchanged. Thread error tests removed.

- [ ] **Step 5: Fix any failures**

Common issues:
- Stale references to `BT.HANDLE`, `CoreType`, `.core_type`, `.thread_handle`, `FuncContext.thread` — grep and fix
- `_orhon_async` still referenced somewhere — remove
- Thread test functions have wrong return values — check tester_main.orh expectations
- Grammar still references `thread_decl` somewhere — check builder dispatch tables

- [ ] **Step 6: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix: resolve remaining thread removal issues

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```
