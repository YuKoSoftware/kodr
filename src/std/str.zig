// str.zig — string utilities sidecar for std::str
// Operates on []const u8 (Orhon String). All functions are pure — no side effects.

const std = @import("std");

const alloc = std.heap.page_allocator;

// ── Search ──

pub fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

pub fn endsWith(s: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, s, suffix);
}

const NullableI32 = union(enum) { some: i32, none: void };

pub fn indexOf(haystack: []const u8, needle: []const u8) NullableI32 {
    if (std.mem.indexOf(u8, haystack, needle)) |pos| {
        return .{ .some = @intCast(pos) };
    }
    return .{ .none = {} };
}

pub fn lastIndexOf(haystack: []const u8, needle: []const u8) NullableI32 {
    if (std.mem.lastIndexOf(u8, haystack, needle)) |pos| {
        return .{ .some = @intCast(pos) };
    }
    return .{ .none = {} };
}

// ── Case ──

pub fn toUpper(s: []const u8) []const u8 {
    const buf = alloc.alloc(u8, s.len) catch return s;
    for (s, 0..) |c, i| {
        buf[i] = std.ascii.toUpper(c);
    }
    return buf;
}

pub fn toLower(s: []const u8) []const u8 {
    const buf = alloc.alloc(u8, s.len) catch return s;
    for (s, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf;
}

// ── Transform ──

pub fn replace(s: []const u8, old: []const u8, new: []const u8) []const u8 {
    const result = std.mem.replaceOwned(u8, alloc, s, old, new) catch return s;
    return result;
}

pub fn repeat(s: []const u8, count: i32) []const u8 {
    if (count <= 0) return "";
    const n: usize = @intCast(count);
    const buf = alloc.alloc(u8, s.len * n) catch return s;
    for (0..n) |i| {
        @memcpy(buf[i * s.len .. (i + 1) * s.len], s);
    }
    return buf;
}

pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\n\r");
}

pub fn trimLeft(s: []const u8) []const u8 {
    return std.mem.trimLeft(u8, s, " \t\n\r");
}

pub fn trimRight(s: []const u8) []const u8 {
    return std.mem.trimRight(u8, s, " \t\n\r");
}

// ── Join ──

pub fn join(parts: anytype, separator: []const u8) []const u8 {
    return std.mem.join(alloc, separator, parts) catch return "";
}

// ── Parse ──

pub fn parseInt(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch 0;
}

pub fn parseFloat(s: []const u8) f64 {
    return std.fmt.parseFloat(f64, s) catch 0.0;
}

// ── Convert ──

pub fn toString(value: anytype) []const u8 {
    return std.fmt.allocPrint(alloc, "{any}", .{value}) catch return "";
}

// ── Length ──

pub fn len(s: []const u8) i32 {
    return @intCast(s.len);
}

pub fn charAt(s: []const u8, index: i32) []const u8 {
    const i: usize = @intCast(index);
    if (i >= s.len) return "";
    return s[i .. i + 1];
}

// ── Tests ──

test "contains" {
    try std.testing.expect(contains("hello world", "world"));
    try std.testing.expect(!contains("hello world", "xyz"));
}

test "startsWith and endsWith" {
    try std.testing.expect(startsWith("hello", "hel"));
    try std.testing.expect(endsWith("hello", "llo"));
}

test "indexOf" {
    const result = indexOf("hello", "ll");
    try std.testing.expectEqual(@as(i32, 2), result.some);
    const none = indexOf("hello", "xyz");
    try std.testing.expect(none == .none);
}

test "toUpper and toLower" {
    const upper = toUpper("hello");
    try std.testing.expect(std.mem.eql(u8, upper, "HELLO"));
    const lower = toLower("HELLO");
    try std.testing.expect(std.mem.eql(u8, lower, "hello"));
}

test "replace" {
    const result = replace("hello world", "world", "orhon");
    try std.testing.expect(std.mem.eql(u8, result, "hello orhon"));
}

test "repeat" {
    const result = repeat("ha", 3);
    try std.testing.expect(std.mem.eql(u8, result, "hahaha"));
}

test "trim" {
    const result = trim("  hello  ");
    try std.testing.expect(std.mem.eql(u8, result, "hello"));
}

test "parseInt and parseFloat" {
    try std.testing.expectEqual(@as(i32, 42), parseInt("42"));
    try std.testing.expectEqual(@as(f64, 3.14), parseFloat("3.14"));
}

test "len and charAt" {
    try std.testing.expectEqual(@as(i32, 5), len("hello"));
    try std.testing.expect(std.mem.eql(u8, charAt("hello", 1), "e"));
}
