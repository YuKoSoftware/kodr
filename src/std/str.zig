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

pub fn repeat(s: []const u8, times: i32) []const u8 {
    if (times <= 0) return "";
    const n: usize = @intCast(times);
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

// ── Formatting ──

pub fn padLeft(s: []const u8, width: i32, fill: []const u8) []const u8 {
    const w: usize = @intCast(@max(0, width));
    if (s.len >= w) return s;
    const pad_len = w - s.len;
    const fill_char = if (fill.len > 0) fill[0] else @as(u8, ' ');
    const buf = alloc.alloc(u8, w) catch return s;
    @memset(buf[0..pad_len], fill_char);
    @memcpy(buf[pad_len..], s);
    return buf;
}

pub fn padRight(s: []const u8, width: i32, fill: []const u8) []const u8 {
    const w: usize = @intCast(@max(0, width));
    if (s.len >= w) return s;
    const fill_char = if (fill.len > 0) fill[0] else @as(u8, ' ');
    const buf = alloc.alloc(u8, w) catch return s;
    @memcpy(buf[0..s.len], s);
    @memset(buf[s.len..], fill_char);
    return buf;
}

pub fn truncate(s: []const u8, max_len: i32) []const u8 {
    const m: usize = @intCast(@max(0, max_len));
    if (s.len <= m) return s;
    if (m <= 3) return s[0..m];
    const buf = alloc.alloc(u8, m) catch return s;
    @memcpy(buf[0 .. m - 3], s[0 .. m - 3]);
    @memcpy(buf[m - 3 ..], "...");
    return buf;
}

pub fn reverse(s: []const u8) []const u8 {
    if (s.len == 0) return "";
    const buf = alloc.alloc(u8, s.len) catch return s;
    for (s, 0..) |c, i| {
        buf[s.len - 1 - i] = c;
    }
    return buf;
}

pub fn splitBy(s: []const u8, sep: []const u8) []const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    var first = true;
    var iter = std.mem.splitSequence(u8, s, sep);
    while (iter.next()) |part| {
        if (!first) buf.append(alloc, '\n') catch {};
        first = false;
        buf.appendSlice(alloc, part) catch {};
    }
    return if (buf.items.len > 0) buf.items else "";
}

pub fn countOccurrences(s: []const u8, sub: []const u8) i32 {
    if (sub.len == 0) return 0;
    var n: i32 = 0;
    var i: usize = 0;
    while (i + sub.len <= s.len) {
        if (std.mem.eql(u8, s[i .. i + sub.len], sub)) {
            n += 1;
            i += sub.len;
        } else {
            i += 1;
        }
    }
    return n;
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

test "padLeft" {
    try std.testing.expect(std.mem.eql(u8, padLeft("42", 5, "0"), "00042"));
    try std.testing.expect(std.mem.eql(u8, padLeft("hello", 3, " "), "hello"));
}

test "padRight" {
    try std.testing.expect(std.mem.eql(u8, padRight("hi", 5, "."), "hi..."));
}

test "truncate" {
    try std.testing.expect(std.mem.eql(u8, truncate("hello world", 8), "hello..."));
    try std.testing.expect(std.mem.eql(u8, truncate("hi", 10), "hi"));
}

test "reverse" {
    try std.testing.expect(std.mem.eql(u8, reverse("hello"), "olleh"));
    try std.testing.expect(std.mem.eql(u8, reverse(""), ""));
}

test "splitBy" {
    try std.testing.expect(std.mem.eql(u8, splitBy("a,b,c", ","), "a\nb\nc"));
    try std.testing.expect(std.mem.eql(u8, splitBy("hello", ","), "hello"));
}

test "countOccurrences" {
    try std.testing.expectEqual(@as(i32, 3), countOccurrences("abababab", "ab"));
    try std.testing.expectEqual(@as(i32, 0), countOccurrences("hello", "xyz"));
}
