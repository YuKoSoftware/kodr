// kodr_fs.zig — File and Dir runtime types for Kodr
// Copied to .kodr-cache/generated/ when File or Dir types are used.
// Stateless handle pattern: each operation opens/closes the OS file handle.

const std = @import("std");

const FsError = struct { message: []const u8 };
fn FsResult(comptime T: type) type {
    return union(enum) { ok: T, err: FsError };
}

pub const File = struct {
    path: []const u8,
    alloc: std.mem.Allocator,

    /// Read entire file contents. Caller owns returned slice.
    pub fn read(self: *const File) FsResult([]const u8) {
        const file = std.fs.cwd().openFile(self.path, .{}) catch
            return .{ .err = .{ .message = "cannot open file" } };
        defer file.close();
        const content = file.readToEndAlloc(self.alloc, 10 * 1024 * 1024) catch
            return .{ .err = .{ .message = "read failed" } };
        return .{ .ok = content };
    }

    /// Write data to file (creates or overwrites).
    pub fn write(self: *const File, data: []const u8) FsResult(void) {
        const file = std.fs.cwd().createFile(self.path, .{}) catch
            return .{ .err = .{ .message = "cannot create file" } };
        defer file.close();
        file.writeAll(data) catch
            return .{ .err = .{ .message = "write failed" } };
        return .{ .ok = {} };
    }

    /// Append data to existing file.
    pub fn append(self: *const File, data: []const u8) FsResult(void) {
        const file = std.fs.cwd().openFile(self.path, .{ .mode = .write_only }) catch
            return .{ .err = .{ .message = "cannot open file for append" } };
        defer file.close();
        const end = file.getEndPos() catch 0;
        file.seekTo(end) catch
            return .{ .err = .{ .message = "seek failed" } };
        file.writeAll(data) catch
            return .{ .err = .{ .message = "append failed" } };
        return .{ .ok = {} };
    }

    /// Close the file handle (frees internal resources).
    pub fn close(self: *const File) void {
        _ = self;
    }

    /// Get file size in bytes.
    pub fn size(self: *const File) FsResult(usize) {
        const file = std.fs.cwd().openFile(self.path, .{}) catch
            return .{ .err = .{ .message = "cannot open file" } };
        defer file.close();
        const stat = file.stat() catch
            return .{ .err = .{ .message = "cannot stat file" } };
        return .{ .ok = stat.size };
    }

    /// Check if the file exists.
    pub fn exists(self: *const File) bool {
        std.fs.cwd().access(self.path, .{}) catch return false;
        return true;
    }
};

pub const Dir = struct {
    path: []const u8,
    alloc: std.mem.Allocator,

    /// List all entries in the directory. Caller owns returned slice.
    pub fn list(self: *const Dir) FsResult([][]const u8) {
        var dir = std.fs.cwd().openDir(self.path, .{ .iterate = true }) catch
            return .{ .err = .{ .message = "cannot open directory" } };
        defer dir.close();
        var names = std.ArrayListUnmanaged([]const u8){};
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            const name = self.alloc.dupe(u8, entry.name) catch continue;
            names.append(self.alloc, name) catch {
                self.alloc.free(name);
                continue;
            };
        }
        return .{ .ok = names.toOwnedSlice(self.alloc) catch return .{ .err = .{ .message = "out of memory" } } };
    }

    /// Close the directory handle (frees internal resources).
    pub fn close(self: *const Dir) void {
        _ = self;
    }

    /// Check if the directory exists.
    pub fn exists(self: *const Dir) bool {
        std.fs.cwd().access(self.path, .{}) catch return false;
        return true;
    }
};

/// Module-level: check if a path exists (file or directory)
pub fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Module-level: delete a file
pub fn deletePath(path: []const u8) FsResult(void) {
    std.fs.cwd().deleteFile(path) catch
        return .{ .err = .{ .message = "cannot delete file" } };
    return .{ .ok = {} };
}

/// Module-level: rename a file or directory
pub fn renamePath(old: []const u8, new: []const u8) FsResult(void) {
    std.fs.cwd().rename(old, new) catch
        return .{ .err = .{ .message = "cannot rename" } };
    return .{ .ok = {} };
}

/// Module-level: create a directory
pub fn makePath(path: []const u8) FsResult(void) {
    std.fs.cwd().makePath(path) catch
        return .{ .err = .{ .message = "cannot create directory" } };
    return .{ .ok = {} };
}

/// Module-level: delete a directory
pub fn removePath(path: []const u8) FsResult(void) {
    std.fs.cwd().deleteDir(path) catch
        return .{ .err = .{ .message = "cannot delete directory" } };
    return .{ .ok = {} };
}
