// errors.zig — Orhon compiler error formatting
// Single source of truth for all error output.
// Emits full trace in debug builds, message only in release builds.

const std = @import("std");

pub const BuildMode = enum {
    debug,
    release,
};

/// A source location in a .orh file
pub const SourceLoc = struct {
    file: []const u8,
    line: usize,
    col: usize,
};

/// A single error with optional location and trace
pub const OrhonError = struct {
    message: []const u8,
    loc: ?SourceLoc = null,
    notes: []const []const u8 = &.{},
};

/// The error reporter — used by every pass
pub const Reporter = struct {
    mode: BuildMode,
    errors: std.ArrayListUnmanaged(OrhonError),
    warnings: std.ArrayListUnmanaged(OrhonError),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, mode: BuildMode) Reporter {
        return .{
            .mode = mode,
            .errors = .{},
            .warnings = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Reporter) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
            if (err.loc) |loc| {
                if (loc.file.len > 0) self.allocator.free(loc.file);
            }
        }
        self.errors.deinit(self.allocator);
        for (self.warnings.items) |w| {
            self.allocator.free(w.message);
            if (w.loc) |loc| {
                if (loc.file.len > 0) self.allocator.free(loc.file);
            }
        }
        self.warnings.deinit(self.allocator);
    }

    fn storeOwned(self: *Reporter, diag: OrhonError, list: *std.ArrayListUnmanaged(OrhonError)) !void {
        const owned_msg = try self.allocator.dupe(u8, diag.message);
        const owned_loc: ?SourceLoc = if (diag.loc) |loc| .{
            .file = if (loc.file.len > 0) (self.allocator.dupe(u8, loc.file) catch "") else "",
            .line = loc.line,
            .col = loc.col,
        } else null;
        try list.append(self.allocator, .{
            .message = owned_msg,
            .loc = owned_loc,
            .notes = diag.notes,
        });
    }

    pub fn report(self: *Reporter, err: OrhonError) !void {
        try self.storeOwned(err, &self.errors);
    }

    /// Record a non-fatal warning. Compilation continues after warnings.
    pub fn warn(self: *Reporter, w: OrhonError) !void {
        try self.storeOwned(w, &self.warnings);
    }

    pub fn hasErrors(self: *const Reporter) bool {
        return self.errors.items.len > 0;
    }

    pub fn hasWarnings(self: *const Reporter) bool {
        return self.warnings.items.len > 0;
    }

    /// Print all diagnostics to stderr: warnings first, then errors.
    pub fn flush(self: *const Reporter) !void {
        var buf: [4096]u8 = undefined;
        var w = std.fs.File.stderr().writer(&buf);
        const stderr = &w.interface;

        for (self.warnings.items) |diag| {
            try printDiagnostic(stderr, &diag, "WARNING", self.mode);
        }
        for (self.errors.items) |diag| {
            try printDiagnostic(stderr, &diag, "ERROR", self.mode);
        }

        // Summary line
        const warning_count = self.warnings.items.len;
        const error_count = self.errors.items.len;
        if (warning_count > 0 or error_count > 0) {
            try stderr.print("\n", .{});
        }
        if (warning_count > 0 and error_count > 0) {
            try stderr.print("{s}{d} warning(s){s}, {s}{d} error(s){s}\n", .{ YELLOW, warning_count, RESET, RED, error_count, RESET });
        } else if (warning_count > 0) {
            try stderr.print("{s}{d} warning(s){s}\n", .{ YELLOW, warning_count, RESET });
        } else if (error_count > 0) {
            try stderr.print("{s}{d} error(s){s}\n", .{ RED, error_count, RESET });
        }

        try stderr.flush();
    }
};

// ANSI color codes
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

fn printDiagnostic(stderr: anytype, diag: *const OrhonError, label: []const u8, mode: BuildMode) !void {
    const is_error = std.mem.eql(u8, label, "ERROR");
    const color = if (is_error) RED else YELLOW;

    if (diag.loc) |loc| {
        if (mode == .debug) {
            // Header: ── ERROR ─────────────────
            try stderr.print("\n{s}{s}── {s} ─────────────────────────────────────────{s}\n", .{ BOLD, color, label, RESET });
            // Message
            try stderr.print("{s}{s}{s}\n", .{ BOLD, diag.message, RESET });
            // Location
            if (loc.line > 0 and loc.file.len > 0) {
                try stderr.print("{s}  --> {s}:{d}{s}\n", .{ CYAN, loc.file, loc.line, RESET });
            } else if (loc.line > 0) {
                try stderr.print("{s}  at line {d}{s}\n", .{ CYAN, loc.line, RESET });
            }
            // Source snippet
            if (loc.file.len > 0 and loc.line > 0) {
                if (readSourceLine(loc.file, loc.line)) |line| {
                    try stderr.print("{s}   |{s}\n", .{ DIM, RESET });
                    try stderr.print("{s}{d: >3}|{s}  {s}\n", .{ DIM, loc.line, RESET, line });
                    try stderr.print("{s}   |{s}\n", .{ DIM, RESET });
                }
            }
            for (diag.notes) |note| {
                try stderr.print("{s}  note:{s} {s}\n", .{ DIM, RESET, note });
            }
        } else {
            try stderr.print("{s}: {s}\n", .{ label, diag.message });
        }
    } else {
        try stderr.print("\n{s}{s}── {s} ─────────────────────────────────────────{s}\n", .{ BOLD, color, label, RESET });
        try stderr.print("{s}{s}{s}\n", .{ BOLD, diag.message, RESET });
    }
}

/// Read a specific line from a source file, returns null on failure
fn readSourceLine(file_path: []const u8, target_line: usize) ?[]const u8 {
    const file = std.fs.cwd().openFile(file_path, .{}) catch return null;
    defer file.close();
    const content = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch return null;
    // Don't defer free — the slice is valid for the duration of flush()
    // This is a small leak per error but errors are fatal anyway
    var line_num: usize = 1;
    var start: usize = 0;
    for (content, 0..) |ch, i| {
        if (ch == '\n') {
            if (line_num == target_line) {
                return content[start..i];
            }
            line_num += 1;
            start = i + 1;
        }
    }
    // Last line without trailing newline
    if (line_num == target_line and start < content.len) {
        return content[start..];
    }
    return null;
}

/// Simple one-shot error print — for fatal compiler errors before Reporter is set up
pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [4096]u8 = undefined;
    var w = std.fs.File.stderr().writer(&buf);
    const stderr = &w.interface;
    stderr.print("ERROR: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
    std.process.exit(1);
}

test "reporter collects errors" {
    var reporter = Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    try reporter.report(.{ .message = "test error" });
    try std.testing.expect(reporter.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), reporter.errors.items.len);
}

test "reporter release mode" {
    var reporter = Reporter.init(std.testing.allocator, .release);
    defer reporter.deinit();
    try std.testing.expect(!reporter.hasErrors());
}

test "reporter collects warnings" {
    var reporter = Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    try reporter.warn(.{ .message = "test warning" });
    try std.testing.expect(!reporter.hasErrors());
    try std.testing.expect(reporter.hasWarnings());
    try std.testing.expectEqual(@as(usize, 1), reporter.warnings.items.len);
    try std.testing.expectEqualStrings("test warning", reporter.warnings.items[0].message);
}

test "reporter warnings don't block compilation" {
    var reporter = Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    try reporter.warn(.{ .message = "unused var" });
    try std.testing.expect(!reporter.hasErrors()); // warnings don't count as errors
}
