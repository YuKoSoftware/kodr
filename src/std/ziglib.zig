// ziglib.zig — bridge testbed sidecar
// Implements the extern declarations from ziglib.orh.
// Plain Zig — no Orhon awareness.

const std = @import("std");

// ── Functions ───────────────────────────────────────────────

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn greeting(name: []const u8) []const u8 {
    _ = name;
    return "hello from zig";
}

pub fn isEven(n: i32) bool {
    return @rem(n, 2) == 0;
}

pub fn distance(x: f64, y: f64) f64 {
    return @sqrt(x * x + y * y);
}

pub fn identity(val: anytype) @TypeOf(val) {
    return val;
}

// ── Counter (non-generic struct) ────────────────────────────

pub const Counter = struct {
    count: i32,

    pub fn create(start: i32) Counter {
        return .{ .count = start };
    }

    pub fn get(self: *const Counter) i32 {
        return self.count;
    }

    pub fn increment(self: *Counter) void {
        self.count += 1;
    }

    pub fn reset(self: *Counter) void {
        self.count = 0;
    }
};

// ── Box (generic struct, one type param) ────────────────────

pub fn Box(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();

        pub fn create(val: T) Self {
            return .{ .value = val };
        }

        pub fn get(self: *const Self) T {
            return self.value;
        }

        pub fn set(self: *Self, val: T) void {
            self.value = val;
        }
    };
}

// ── KV (generic struct, two type params) ─────────────────────

pub fn KV(comptime K: type, comptime V: type) type {
    return struct {
        k: K,
        v: V,

        const Self = @This();

        pub fn create(k: K, v: V) Self {
            return .{ .k = k, .v = v };
        }

        pub fn key(self: *const Self) K {
            return self.k;
        }

        pub fn val(self: *const Self) V {
            return self.v;
        }
    };
}

// ── Constants as functions ──────────────────────────────────

pub fn maxSize() i32 {
    return 1024;
}

pub fn pi() f64 {
    return std.math.pi;
}
