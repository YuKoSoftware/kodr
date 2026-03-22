# Zig Bridge — `extern` Declarations and Paired `.zig` Files

Orhon handles all external interop through Zig. Orhon never talks to C, system APIs,
or external libraries directly — that complexity always lives in a paired `.zig` file.
Zig already has first-class C interop, handles ABI, calling conventions, and struct
layouts. No need to duplicate that work in Orhon.

The bridge is universal — the standard library uses the same mechanism as user code.
Reading the stdlib source is the best way to learn the bridge pattern.

---

## How It Works

A module can be paired with a hand-written `.zig` sidecar. The `.orh` file declares
the interface using `extern`. The `.zig` file provides the implementation in plain Zig.
The codegen re-exports from the sidecar — pure 1:1 translation, no special cases.

```
// console.orh — Orhon interface
module console

extern func print(msg: String) void
extern func println(msg: String) void
```

```zig
// console.zig — plain Zig implementation
const std = @import("std");

pub fn print(msg: []const u8) void {
    std.io.getStdOut().writer().writeAll(msg) catch {};
}

pub fn println(msg: []const u8) void {
    const w = std.io.getStdOut().writer();
    w.writeAll(msg) catch {};
    w.writeAll("\n") catch {};
}
```

---

## Bridge Safety Rules

Mutable references cannot cross the bridge in either direction. This ensures Orhon's
safety guarantees are maintained at the boundary.

| Direction | `T` (value) | `const &T` | `&T` (mutable) |
|-----------|------------|------------|-----------------|
| Orhon → Zig | Move | Borrow (read) | **Not allowed** |
| Zig → Orhon | Owned | Borrow (read) | **Not allowed** |

**Exception:** `self: &ExternStruct` on extern struct methods is allowed — Zig
mutates its own data, not Orhon-owned data.

Violating this rule produces a compile error:
```
mutable reference '&data' not allowed across bridge — use 'const &data' or pass by value
```

---

## `extern` Declaration Types

All `extern` declarations are implicitly public. `pub extern` is a compiler error (redundant).
A paired `.zig` sidecar file must exist alongside the `.orh` file — hard error if missing.

### `extern func` — bridge a function
```
extern func print(msg: String) void
extern func sqrt(x: any) any
```
No body. The Zig sidecar must have a matching `pub fn`.

### `extern func` with default arguments
Default arguments provide ergonomics — users can omit parameters with sensible defaults.
The compiler fills defaults at the call site.
```
extern func greet(name: String, prefix: String = "Hello") String
```
Calling `greet("world")` generates `greet("world", "Hello")` in Zig.

### `extern const` — expose a Zig constant
```
extern const PI: f64
```
The Zig sidecar must have a matching `pub const`.

### `extern struct` — bridge a Zig type with methods
```
extern struct Counter {
    extern func create(start: i32) Counter
    extern func get(self: const &Counter) i32
    extern func increment(self: &Counter) void
}
```
The sidecar must have a matching struct with `pub fn` methods.

### `extern struct` with type parameters — generic bridge types
```
extern struct Box(T: type) {
    extern func create(val: T) Box
    extern func get(self: const &Box) T
    extern func set(self: &Box, val: T) void
}
```
The sidecar implements this as a comptime function returning a type:
```zig
pub fn Box(comptime T: type) type {
    return struct {
        value: T,
        const Self = @This();
        pub fn create(val: T) Self { return .{ .value = val }; }
        pub fn get(self: *const Self) T { return self.value; }
        pub fn set(self: *Self, val: T) void { self.value = val; }
    };
}
```

---

## Orhon Wrappers Over Extern Types

The bridge `.orh` file can contain both extern declarations and regular Orhon code.
This enables ergonomic wrappers — the extern provides the raw Zig interface, and
Orhon code wraps it with defaults, validation, or convenience methods.

```
module mylib

// Raw bridge — thin extern declarations
extern struct RawList(T: type) {
    extern func init(alloc: any) RawList
    extern func append(self: &RawList, item: T) void
    extern func deinit(self: &RawList) void
}

// Orhon API — ergonomic wrapper
pub struct List(T: type) {
    raw: RawList(T)

    pub func create() List {
        return List(raw: RawList(T).init(defaultAlloc()))
    }

    pub func add(self: &List, item: T) void {
        self.raw.append(item)
    }

    pub func free(self: &List) void {
        self.raw.deinit()
    }
}
```

---

## Error Union Return Types

When an `extern func` returns `(Error | T)`, the Zig sidecar must return a union with
`.ok: T` and `.err: struct { message: []const u8 }` tags.

```zig
const GetError = struct { message: []const u8 };
const GetResult = union(enum) { ok: []const u8, err: GetError };

pub fn get() GetResult {
    return .{ .ok = line };
    // or
    return .{ .err = .{ .message = "end of input" } };
}
```

---

## Calling C Through Zig

C interop goes through `.zig` bridge files. The `.orh` file exposes a clean Orhon API,
the `.zig` file handles all C details internally:

```zig
// gtk.zig — Zig handles all C interop
const c = @cImport(@cInclude("gtk4.h"));

pub fn windowNew() *c.GtkWidget {
    return c.gtk_window_new();
}
```

```
// gtk.orh — clean Orhon interface, no C visible
module gtk

extern func windowNew() Ptr(u8)
```

---

## Module Pairing

One `.zig` sidecar per module. A module can span multiple `.orh` files (all declaring
the same module name). The sidecar file name matches the module name.

```
src/
  math.orh          // module math — extern declarations
  math_utils.orh    // module math — more Orhon code, same module
  math.zig          // sidecar — all Zig implementations for module math
```
