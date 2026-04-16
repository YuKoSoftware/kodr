// string_pool.zig — interning pool for strings, used by AstStore

const std = @import("std");

pub const StringIndex = enum(u32) {
    none = 0,
    _,
};

const Span = struct { start: u32, len: u32 };

pub const StringPool = struct {
    bytes: std.ArrayListUnmanaged(u8),
    spans: std.ArrayListUnmanaged(Span),
    map: std.StringHashMapUnmanaged(StringIndex),

    pub fn init() StringPool {
        return .{
            .bytes = .{},
            .spans = .{},
            .map = .{},
        };
    }

    pub fn deinit(pool: *StringPool, allocator: std.mem.Allocator) void {
        pool.bytes.deinit(allocator);
        pool.spans.deinit(allocator);
        pool.map.deinit(allocator);
    }

    pub fn intern(pool: *StringPool, allocator: std.mem.Allocator, str: []const u8) !StringIndex {
        if (pool.map.get(str)) |idx| return idx;

        const start: u32 = @intCast(pool.bytes.items.len);
        try pool.bytes.appendSlice(allocator, str);
        const key = pool.bytes.items[start..];

        // index 0 is .none, real entries start at 1
        const raw: u32 = @intCast(pool.spans.items.len + 1);
        const idx: StringIndex = @enumFromInt(raw);

        try pool.spans.append(allocator, .{ .start = start, .len = @intCast(str.len) });
        try pool.map.put(allocator, key, idx);
        return idx;
    }

    pub fn get(pool: *const StringPool, idx: StringIndex) []const u8 {
        const raw = @intFromEnum(idx);
        const span = pool.spans.items[raw - 1];
        return pool.bytes.items[span.start..][0..span.len];
    }
};

test "intern same string twice returns same index" {
    var pool = StringPool.init();
    defer pool.deinit(std.testing.allocator);

    const a = try pool.intern(std.testing.allocator, "hello");
    const b = try pool.intern(std.testing.allocator, "hello");
    try std.testing.expectEqual(a, b);
}

test "intern different strings returns different indices" {
    var pool = StringPool.init();
    defer pool.deinit(std.testing.allocator);

    const a = try pool.intern(std.testing.allocator, "foo");
    const b = try pool.intern(std.testing.allocator, "bar");
    try std.testing.expect(a != b);
}

test "get round-trip" {
    var pool = StringPool.init();
    defer pool.deinit(std.testing.allocator);

    const idx = try pool.intern(std.testing.allocator, "round-trip");
    try std.testing.expectEqualStrings("round-trip", pool.get(idx));
}

test "none index is never returned by intern" {
    var pool = StringPool.init();
    defer pool.deinit(std.testing.allocator);

    const idx = try pool.intern(std.testing.allocator, "something");
    try std.testing.expect(idx != .none);
}
