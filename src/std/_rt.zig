// _rt.zig — Orhon compiler runtime sidecar
// Bridge implementation for the _rt module.
// Paired with _rt.orh — loaded automatically by the compiler.

const std = @import("std");

// ── Allocator ──
// Debug builds: GPA (leak detection, use-after-free checks)
// Release builds: page allocator (fast, zero overhead)

pub const alloc = if (@import("builtin").mode == .Debug)
    gpa.allocator()
else
    std.heap.page_allocator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// ── Type helpers ──

pub fn OrhonNullable(comptime T: type) type {
    return union(enum) { some: T, none: void };
}

pub fn orhonTypeId(comptime T: type) usize {
    return @intFromPtr(@typeName(T).ptr);
}

// ── Error type ──

pub const OrhonError = struct { message: []const u8 };

pub fn OrhonResult(comptime T: type) type {
    return union(enum) { ok: T, err: OrhonError };
}

// ── Thread handle ──

pub fn OrhonHandle(comptime T: type) type {
    return struct {
        thread: std.Thread,
        state: *SharedState,

        pub const SharedState = struct {
            result: T = undefined,
            completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        };

        const Self = @This();

        /// Block until thread finishes, return the result (move).
        pub fn getValue(self: *Self) T {
            self.thread.join();
            const result = self.state.result;
            alloc.destroy(self.state);
            return result;
        }

        /// Block until thread finishes, don't move the result.
        pub fn wait(self: *Self) void {
            self.thread.join();
        }

        /// Non-blocking check: is the thread done?
        pub fn done(self: *const Self) bool {
            return self.state.completed.load(.acquire);
        }

        /// Block until done, discard result, clean up.
        pub fn join(self: *Self) void {
            self.thread.join();
            alloc.destroy(self.state);
        }
    };
}

// ── Tests ──

test "alloc works" {
    const ptr = try alloc.create(i32);
    ptr.* = 42;
    try std.testing.expectEqual(42, ptr.*);
    alloc.destroy(ptr);
}

test "OrhonNullable" {
    const N = OrhonNullable(i32);
    const some: N = .{ .some = 42 };
    const none: N = .{ .none = {} };
    try std.testing.expectEqual(42, some.some);
    _ = none;
}

test "OrhonResult" {
    const R = OrhonResult(i32);
    const ok: R = .{ .ok = 42 };
    const err: R = .{ .err = .{ .message = "fail" } };
    try std.testing.expectEqual(42, ok.ok);
    try std.testing.expect(std.mem.eql(u8, err.err.message, "fail"));
}

test "orhonTypeId distinct" {
    try std.testing.expect(orhonTypeId(i32) != orhonTypeId(f64));
}
