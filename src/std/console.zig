// console.zig — terminal I/O implementation for Orhon's std::console
// Hand-written implementation. Paired with console.orh.
// Do not edit the generated console.zig in .orh-cache/generated/ —
// edit this source file — embedded into the compiler at build time.

const std = @import("std");

const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
const stderr = std.fs.File{ .handle = std.posix.STDERR_FILENO };

var buf: [4096]u8 = undefined;
var w: std.fs.File.Writer = stdout.writer(&buf);

pub fn print(msg: []const u8) void {
    w.interface.writeAll(msg) catch {}; // fire-and-forget: I/O in void fn
}

pub fn println(msg: []const u8) void {
    w.interface.writeAll(msg) catch {}; // fire-and-forget: I/O in void fn
    w.interface.writeAll("\n") catch {};
    w.interface.flush() catch {};
}

pub fn flush() void {
    w.interface.flush() catch {}; // fire-and-forget: I/O in void fn
}

pub fn debugPrint(msg: []const u8) void {
    stderr.writeAll(msg) catch {}; // fire-and-forget: I/O in void fn
}

// GetResult mirrors ErrorUnion(String) as the codegen expects: .ok and .err tags
const GetError = struct { message: []const u8 };
const GetResult = union(enum) { ok: []const u8, err: GetError };

var get_buf: [4096]u8 = undefined;

pub fn supportsColor() bool {
    return std.posix.isatty(std.posix.STDOUT_FILENO);
}

// ANSI color constants
pub const RESET = "\x1b[0m";
pub const BOLD = "\x1b[1m";
pub const DIM = "\x1b[2m";
pub const UNDERLINE = "\x1b[4m";

pub const RED = "\x1b[31m";
pub const GREEN = "\x1b[32m";
pub const YELLOW = "\x1b[33m";
pub const BLUE = "\x1b[34m";
pub const MAGENTA = "\x1b[35m";
pub const CYAN = "\x1b[36m";
pub const WHITE = "\x1b[37m";

pub fn get() GetResult {
    const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    const line = stdin.reader().readUntilDelimiterOrEof(&get_buf, '\n') catch {
        return .{ .err = .{ .message = "stdin read error" } };
    };
    if (line) |l| {
        return .{ .ok = l };
    } else {
        return .{ .err = .{ .message = "end of input" } };
    }
}
