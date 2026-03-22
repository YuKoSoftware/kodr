// system.zig — OS/system operations implementation for Orhon's std::system
// Hand-written implementation. Paired with system.orh.
// Do not edit the generated system.zig in .orh-cache/generated/ —
// edit this source file — embedded into the compiler at build time.

const std = @import("std");

fn OrhonNullable(comptime T: type) type {
    return union(enum) { some: T, none: void };
}

pub fn getEnv(key: []const u8) OrhonNullable([]const u8) {
    const val = std.process.getEnvVarOwned(std.heap.smp_allocator, key) catch {
        return .{ .none = {} };
    };
    return .{ .some = val };
}

pub fn setEnv(key: []const u8, value: []const u8) void {
    std.posix.setenv(key, value) catch {};
}

pub fn args() []const []const u8 {
    const argv = std.process.argsAlloc(std.heap.smp_allocator) catch return &.{};
    return argv;
}

pub fn cwd() []const u8 {
    const dir = std.process.getCwdAlloc(std.heap.smp_allocator) catch return "";
    return dir;
}

pub fn exit(code: i32) void {
    std.process.exit(@intCast(code));
}

pub fn pid() i32 {
    return @intCast(std.os.linux.getpid());
}

pub fn run(command: []const u8, arguments: []const []const u8) struct { code: i32, stdout: []const u8, stderr: []const u8 } {
    const alloc = std.heap.smp_allocator;

    // Build argv: command + arguments
    var argv = std.ArrayListUnmanaged([]const u8){};
    defer argv.deinit(alloc);
    argv.append(alloc, command) catch return .{ .code = -1, .stdout = "", .stderr = "failed to build argv" };
    for (arguments) |arg| {
        argv.append(alloc, arg) catch return .{ .code = -1, .stdout = "", .stderr = "failed to build argv" };
    }

    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = argv.items,
    }) catch return .{ .code = -1, .stdout = "", .stderr = "failed to run process" };

    const code: i32 = switch (result.term) {
        .Exited => |c| @intCast(c),
        else => -1,
    };

    return .{ .code = code, .stdout = result.stdout, .stderr = result.stderr };
}
