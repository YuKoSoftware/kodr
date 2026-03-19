# Zig 0.15 Reference Guide

Internal reference for correct Zig 0.15.x patterns — used in both compiler source (`src/`) and generated Zig output (`codegen.zig`). Check this before writing or generating any Zig code.

---

## Allocators

### Default allocator — `std.heap.smp_allocator`

The SMP allocator is the new standard default in Zig 0.15. It uses per-thread freelists, is safe to use from multiple threads, and requires no init or deinit.

```zig
const allocator = std.heap.smp_allocator;
```

It is a singleton — use it directly. No struct, no `.allocator()` call.

### Debug allocator — `std.heap.DebugAllocator`

Replaces `GeneralPurposeAllocator` as the recommended allocator for development. Catches double-free, use-after-free, and leaks.

```zig
var debug_alloc = std.heap.DebugAllocator(.{}){};
defer _ = debug_alloc.deinit();
const allocator = debug_alloc.allocator();
```

### GPA — still exists, no longer the go-to

`std.heap.GeneralPurposeAllocator` still compiles but is no longer the recommended choice. Do not reach for it by default.

### Arena allocator — unchanged

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();
```

### Recommended build-mode pattern (compiler source `main.zig`)

```zig
pub fn main() !void {
    const allocator = if (builtin.mode == .Debug)
        blk: {
            var da = std.heap.DebugAllocator(.{}){};
            break :blk da.allocator(); // ← won't work as-is, see note
        }
    else
        std.heap.smp_allocator;
    ...
}
```

Practical approach — use a top-level variable or a dedicated init function to manage the `DebugAllocator` lifetime. The cleanest pattern:

```zig
var debug_alloc: std.heap.DebugAllocator(.{}) = .{};

pub fn main() !void {
    const allocator = if (builtin.mode == .Debug) blk: {
        defer _ = debug_alloc.deinit();  // runs at scope exit
        break :blk debug_alloc.allocator();
    } else std.heap.smp_allocator;
    ...
}
```

Or simply switch on the constant at the top:

```zig
pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    const allocator = if (builtin.mode == .Debug) da.allocator() else std.heap.smp_allocator;
    defer if (builtin.mode == .Debug) _ = da.deinit();
    ...
}
```

---

## Collections

### `ArrayList` — unmanaged by default

In Zig 0.15 `std.ArrayList` is unmanaged: the allocator is **not** stored in the struct. Pass it to every mutating call.

```zig
// 0.15 — unmanaged
var list = std.ArrayList(i32){};
defer list.deinit(allocator);
try list.append(allocator, 42);
const v = list.items[0];
```

The old managed API is still available at `std.array_list.Managed` if needed:

```zig
var list = std.array_list.Managed(i32).init(allocator);
defer list.deinit();
try list.append(42);
```

**Impact on codegen:** `List(T)` in Kodr generates `std.ArrayList(T)`. Generated code must use the unmanaged API.

### `HashMap` — check for unmanaged changes too

`std.StringHashMap` and `std.AutoHashMap` follow the same unmanaged trend. Prefer `std.StringHashMapUnmanaged` / `std.AutoHashMapUnmanaged` and pass the allocator explicitly.

```zig
var map = std.StringHashMapUnmanaged(i32){};
defer map.deinit(allocator);
try map.put(allocator, "key", 42);
```

---

## I/O — "Writergate"

Generic `std.io` readers and writers are deprecated. Use the concrete types instead.

- **Writer:** `std.Io.Writer` — buffers are in the interface, not the implementation. **Must call `flush()` before exit.**
- **Reader:** `std.Io.Reader`

```zig
// old (deprecated)
const stdout = std.io.getStdOut().writer();
try stdout.print("hello\n", .{});

// new
var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
const stdout = bw.writer();
try stdout.print("hello\n", .{});
try bw.flush();
```

---

## Type Reflection — lowercase discriminators

All `std.builtin.Type` tags are now lowercase. Use the `@""` escape syntax.

```zig
// 0.15
switch (@typeInfo(T)) {
    .@"struct" => ...,
    .@"enum"   => ...,
    .int       => ...,
    .pointer   => ...,
}
```

---

## Build System (`build.zig`)

Key changes from earlier versions:

```zig
// Modules — use createModule + root_module
const mod = b.createModule(.{ .root_source_file = b.path("src/main.zig") });
const exe = b.addExecutable(.{
    .name = "app",
    .root_module = mod,
});

// Static library — addLibrary replaces addStaticLibrary
const lib = b.addLibrary(.{
    .name = "mylib",
    .root_module = mod,
    .linkage = .static,
});
```

---

## Other notable changes

| Old | New |
|-----|-----|
| `std.rand` | `std.Random` |
| `std.TailQueue` | `std.DoublyLinkedList` |
| `std.mem.page_size` | runtime value (function call) |
| `usingnamespace` | removed |
| `async` / `await` | removed (moved to stdlib) |
| `std.BoundedArray` | removed |

---

## Kodr codegen — what to emit

| Kodr | Generated Zig (0.15) |
|------|----------------------|
| `mem.DebugAllocator()` | `std.heap.DebugAllocator(.{}){}` + `.allocator()` |
| `mem.SMP()` | `std.heap.smp_allocator` (singleton, no init) |
| `List(T)` default owned | `std.ArrayList(T){}` + unmanaged API |
| `List(T).add(v)` | `list.append(allocator, v)` |
| `List(T).free()` | `list.deinit(allocator)` |
| `Map(K,V)` | `std.StringHashMapUnmanaged(V){}` or `std.AutoHashMapUnmanaged(K,V){}` |
| `Set(T)` | `std.AutoHashMapUnmanaged(T, void){}` |

**Default owned collection (no alloc arg):** Use `std.heap.smp_allocator` — it is a singleton, safe to reference by name. The "owned allocator" boilerplate is only needed for `DebugAllocator` / `ArenaAllocator` since those have state. SMP does not.

---

## What to update in the compiler

- [x] `src/main.zig` — switch `GeneralPurposeAllocator` to `DebugAllocator` (debug) / `smp_allocator` (release)
- [x] `src/codegen.zig` `generateAllocatorInit` — emit `DebugAllocator` for `.gpa`, add `.smp` kind emitting `smp_allocator`
- [x] `src/codegen.zig` collections — switch to unmanaged ArrayList/HashMap API
- [x] `src/codegen.zig` default owned collection — use `smp_allocator` as backing instead of GPA boilerplate
