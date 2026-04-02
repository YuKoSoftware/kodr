// console.zig — terminal I/O implementation for Orhon's std::console
// Hand-written implementation. .orh declarations auto-generated from this file.
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

pub fn printColored(color: []const u8, msg: []const u8) void {
    print(color);
    print(msg);
    print(RESET);
}

pub fn printColoredLn(color: []const u8, msg: []const u8) void {
    print(color);
    print(msg);
    println(RESET);
}

pub fn get() anyerror![]const u8 {
    const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    const line = try stdin.reader().readUntilDelimiterOrEof(&get_buf, '\n');
    return line orelse error.EndOfInput;
}
