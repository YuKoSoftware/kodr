// str.zig — extern sidecar for std::str module

const std = @import("std");

pub fn join(alloc: std.mem.Allocator, parts: anytype, sep: []const u8) []const u8 {
    if (parts.len == 0) return "";

    // Calculate total length
    var total: usize = 0;
    for (parts, 0..) |part, i| {
        total += part.len;
        if (i < parts.len - 1) total += sep.len;
    }

    const buf = alloc.alloc(u8, total) catch return "";
    var pos: usize = 0;
    for (parts, 0..) |part, i| {
        @memcpy(buf[pos..][0..part.len], part);
        pos += part.len;
        if (i < parts.len - 1) {
            @memcpy(buf[pos..][0..sep.len], sep);
            pos += sep.len;
        }
    }
    return buf;
}

pub fn fromBytes(bytes: []u8) []const u8 {
    return bytes;
}

pub fn toBytes(alloc: std.mem.Allocator, s: []const u8) []u8 {
    const buf = alloc.alloc(u8, s.len) catch return &.{};
    @memcpy(buf, s);
    return buf;
}

pub fn from(alloc: std.mem.Allocator, value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8) return value;
    if (T == bool) return if (value) "true" else "false";
    return std.fmt.allocPrint(alloc, "{d}", .{value}) catch "";
}
