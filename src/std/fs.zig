// fs.zig — extern func sidecar for std::fs module
// Module-level filesystem utility functions.

const std = @import("std");

const FsError = struct { message: []const u8 };
fn FsResult(comptime T: type) type {
    return union(enum) { ok: T, err: FsError };
}

pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn delete(path: []const u8) FsResult(void) {
    std.fs.cwd().deleteFile(path) catch
        return .{ .err = .{ .message = "cannot delete file" } };
    return .{ .ok = {} };
}

pub fn rename(old: []const u8, new: []const u8) FsResult(void) {
    std.fs.cwd().rename(old, new) catch
        return .{ .err = .{ .message = "cannot rename" } };
    return .{ .ok = {} };
}

pub fn createDir(path: []const u8) FsResult(void) {
    std.fs.cwd().makePath(path) catch
        return .{ .err = .{ .message = "cannot create directory" } };
    return .{ .ok = {} };
}

pub fn deleteDir(path: []const u8) FsResult(void) {
    std.fs.cwd().deleteDir(path) catch
        return .{ .err = .{ .message = "cannot delete directory" } };
    return .{ .ok = {} };
}
