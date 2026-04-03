// async.zig — atomic concurrency primitives sidecar for std::async
// Provides Atomic(T) as a Zig generic type function.
// Wraps std.atomic.Value(T) for lock-free atomic operations.

const std = @import("std");

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

// ── Tests ──

test "Atomic basic" {
    var a = Atomic(i32).new(0);
    a.store(42);
    try std.testing.expectEqual(@as(i32, 42), a.load());
}

test "Atomic exchange" {
    var a = Atomic(i32).new(10);
    const old = a.exchange(20);
    try std.testing.expectEqual(@as(i32, 10), old);
    try std.testing.expectEqual(@as(i32, 20), a.load());
}

test "Atomic fetchAdd" {
    var a = Atomic(i32).new(0);
    _ = a.fetchAdd(5);
    _ = a.fetchAdd(3);
    try std.testing.expectEqual(@as(i32, 8), a.load());
}

test "Atomic fetchSub" {
    var a = Atomic(i32).new(100);
    _ = a.fetchSub(30);
    try std.testing.expectEqual(@as(i32, 70), a.load());
}
