// fs.zig — sidecar for std::fs module
// Contains File/Dir types and module-level filesystem functions.

const std = @import("std");

const FsError = struct { message: []const u8 };
fn FsResult(comptime T: type) type {
    return union(enum) { ok: T, err: FsError };
}

// ── File type ───────────────────────────────────────────────

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

// ── Dir type ────────────────────────────────────────────────

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

// ── Module-level functions ──────────────────────────────────

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

// ── Path manipulation ───────────────────────────────────────

pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

pub fn dirname(path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse "";
}

pub fn extension(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

pub fn stem(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    const ext = std.fs.path.extension(base);
    if (ext.len > 0) return base[0 .. base.len - ext.len];
    return base;
}

pub fn isAbsolute(path: []const u8) bool {
    return std.fs.path.isAbsolute(path);
}

pub fn joinPath(parts: anytype) []const u8 {
    const alloc = std.heap.smp_allocator;
    return std.fs.path.join(alloc, &parts) catch @panic("fs.joinPath: out of memory");
}

pub fn normalize(path: []const u8) []const u8 {
    // Zig doesn't have a direct normalize — use resolve with cwd context
    // For a simple normalize, we strip redundant separators and resolve . and ..
    const alloc = std.heap.smp_allocator;
    // resolve() normalizes relative to CWD; for pure normalization we
    // resolve against "." and strip the CWD prefix if the input was relative
    if (std.fs.path.isAbsolute(path)) {
        const parts: []const []const u8 = &.{path};
        return std.fs.path.resolve(alloc, parts) catch return path;
    }
    // Relative path: resolve against "." then make relative again
    const parts: []const []const u8 = &.{path};
    const resolved = std.fs.path.resolve(alloc, parts) catch return path;
    const cwd = std.fs.cwd().realpathAlloc(alloc, ".") catch return path;
    defer alloc.free(cwd);
    if (std.mem.startsWith(u8, resolved, cwd)) {
        const rel = resolved[cwd.len..];
        if (rel.len > 0 and rel[0] == '/') return rel[1..];
        if (rel.len == 0) return ".";
        return rel;
    }
    return resolved;
}

pub fn separator() []const u8 {
    return std.fs.path.sep_str;
}
