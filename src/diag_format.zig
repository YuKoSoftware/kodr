// diag_format.zig — Diagnostic output rendering (human, JSON, short)
const std = @import("std");
const errors = @import("errors.zig");

pub const DiagFormat = enum { human, json, short };

// ── ANSI constants ────────────────────────────────────────────────────────────

const RED        = "\x1b[31m";
const YELLOW     = "\x1b[33m";
const CYAN       = "\x1b[36m";
const DIM        = "\x1b[2m";
const BOLD       = "\x1b[1m";
const RESET      = "\x1b[0m";
const WHITE      = "\x1b[97m";
const HEADER_ERR = "\x1b[41m";
const HEADER_WRN = "\x1b[43m";
const HEADER_WRN_FG = "\x1b[30m";
const HEADER_PAD = "                                                  ";

fn esc(comptime code: []const u8, use_color: bool) []const u8 {
    return if (use_color) code else "";
}

// ── Human format ──────────────────────────────────────────────────────────────

pub fn flushHuman(reporter: *errors.Reporter, mode: errors.BuildMode, writer: anytype, use_color: bool) !void {
    var err_count: usize = 0;
    var warn_count: usize = 0;

    for (reporter.diagnostics.items, 0..) |*diag, i| {
        if (diag.parent != null) continue; // notes/hints emitted via emitChildren
        switch (diag.severity) {
            .err => {
                err_count += 1;
                try printDiagnostic(reporter, writer, diag, .err, mode, use_color);
                try emitChildren(reporter, @intCast(i), writer, use_color);
            },
            .warning => {
                warn_count += 1;
                try printDiagnostic(reporter, writer, diag, .warning, mode, use_color);
                try emitChildren(reporter, @intCast(i), writer, use_color);
            },
            .note, .hint => {},
        }
    }

    if (warn_count > 0 or err_count > 0) try writer.print("\n", .{});
    if (warn_count > 0 and err_count > 0) {
        try writer.print("{s}{d} warning(s){s}, {s}{d} error(s){s}\n", .{ esc(YELLOW, use_color), warn_count, esc(RESET, use_color), esc(RED, use_color), err_count, esc(RESET, use_color) });
    } else if (warn_count > 0) {
        try writer.print("{s}{d} warning(s){s}\n", .{ esc(YELLOW, use_color), warn_count, esc(RESET, use_color) });
    } else if (err_count > 0) {
        try writer.print("{s}{d} error(s){s}\n", .{ esc(RED, use_color), err_count, esc(RESET, use_color) });
    }
}

fn emitChildren(reporter: *errors.Reporter, parent_idx: u32, writer: anytype, use_color: bool) !void {
    for (reporter.diagnostics.items) |*diag| {
        if (diag.parent != parent_idx) continue;
        try printNote(writer, diag, use_color);
    }
}

fn printNote(writer: anytype, diag: *const errors.OrhonDiag, use_color: bool) !void {
    try writer.print("\n  {s}note:{s} {s}\n", .{ esc(CYAN, use_color), esc(RESET, use_color), diag.message });
    if (diag.loc) |loc| {
        if (loc.line > 0 and loc.file.len > 0) {
            try writer.print("  {s}──▸ {s}:{d}{s}\n", .{ esc(CYAN, use_color), loc.file, loc.line, esc(RESET, use_color) });
        } else if (loc.line > 0) {
            try writer.print("  {s}at line {d}{s}\n", .{ esc(CYAN, use_color), loc.line, esc(RESET, use_color) });
        }
    }
}

fn printDiagnostic(reporter: *errors.Reporter, writer: anytype, diag: *const errors.OrhonDiag, kind: DiagKind, mode: errors.BuildMode, use_color: bool) !void {
    const is_error = kind == .err;
    const lbl = kind.label();

    var code_buf: [8]u8 = undefined;
    const code_str: []const u8 = if (diag.code) |c| c.toCode(&code_buf) else "";
    const has_code = diag.code != null;

    if (mode != .debug) {
        if (has_code) {
            try writer.print("{s} [{s}]: {s}\n", .{ lbl, code_str, diag.message });
        } else {
            try writer.print("{s}: {s}\n", .{ lbl, diag.message });
        }
        return;
    }

    const full_lbl = if (has_code)
        try std.fmt.allocPrint(std.heap.page_allocator, "{s} [{s}]", .{ lbl, code_str })
    else
        lbl;
    defer if (has_code) std.heap.page_allocator.free(full_lbl);
    const pad_len = if (HEADER_PAD.len > full_lbl.len + 2) HEADER_PAD.len - full_lbl.len - 2 else 0;

    const header_bg = if (is_error) esc(HEADER_ERR, use_color) else esc(HEADER_WRN, use_color);
    const header_fg = if (is_error) esc(WHITE, use_color) else esc(HEADER_WRN_FG, use_color);
    try writer.print("\n{s}{s}{s}  {s}{s}{s}\n", .{ header_bg, esc(BOLD, use_color), header_fg, full_lbl, HEADER_PAD[0..pad_len], esc(RESET, use_color) });
    try writer.print("\n  {s}{s}{s}\n", .{ esc(BOLD, use_color), diag.message, esc(RESET, use_color) });

    if (diag.loc) |loc| {
        if (loc.line > 0 and loc.file.len > 0) {
            try writer.print("  {s}──▸ {s}:{d}{s}\n", .{ esc(CYAN, use_color), loc.file, loc.line, esc(RESET, use_color) });
        } else if (loc.line > 0) {
            try writer.print("  {s}at line {d}{s}\n", .{ esc(CYAN, use_color), loc.line, esc(RESET, use_color) });
        }
        if (loc.file.len > 0 and loc.line > 0) {
            if (reporter.getSourceLine(loc.file, loc.line)) |line| {
                try writer.print("{s}       │{s}\n", .{ esc(DIM, use_color), esc(RESET, use_color) });
                try writer.print("{s}{d: >5}{s} {s}│{s}  {s}{s}{s}\n", .{ esc(BOLD, use_color), loc.line, esc(RESET, use_color), esc(DIM, use_color), esc(RESET, use_color), esc(BOLD, use_color), line, esc(RESET, use_color) });
                try writer.print("{s}       │{s}\n", .{ esc(DIM, use_color), esc(RESET, use_color) });
            }
        }
    }
}

const DiagKind = enum {
    err,
    warning,

    fn label(self: DiagKind) []const u8 {
        return switch (self) {
            .err     => "ERROR",
            .warning => "WARNING",
        };
    }
};

// ── JSON format ───────────────────────────────────────────────────────────────

pub fn flushJson(reporter: *const errors.Reporter, writer: anytype) !void {
    try writer.writeAll("{\"version\":1,\"diagnostics\":[");
    var first = true;
    for (reporter.diagnostics.items) |*diag| {
        if (!first) try writer.writeAll(",");
        first = false;
        try writeDiagJson(diag, writer);
    }
    try writer.writeAll("]}\n");
}

fn writeDiagJson(diag: *const errors.OrhonDiag, writer: anytype) !void {
    const severity_str: []const u8 = switch (diag.severity) {
        .err     => "error",
        .warning => "warning",
        .note    => "note",
        .hint    => "hint",
    };
    try writer.print("{{\"severity\":\"{s}\"", .{severity_str});
    if (diag.code) |code| {
        var buf: [8]u8 = undefined;
        const code_str = code.toCode(&buf);
        try writer.print(",\"code\":\"{s}\"", .{code_str});
    }
    try writer.writeAll(",\"message\":");
    try writeJsonString(diag.message, writer);
    if (diag.loc) |loc| {
        if (loc.file.len > 0) {
            try writer.writeAll(",\"file\":");
            try writeJsonString(loc.file, writer);
        }
        if (loc.line > 0) try writer.print(",\"line\":{d}", .{loc.line});
        if (loc.col  > 0) try writer.print(",\"col\":{d}",  .{loc.col});
    }
    if (diag.parent) |p| {
        try writer.print(",\"parent\":{d}", .{p});
    }
    try writer.writeAll("}");
}

fn writeJsonString(s: []const u8, writer: anytype) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"'  => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

// ── Short format ──────────────────────────────────────────────────────────────

pub fn flushShort(reporter: *const errors.Reporter, writer: anytype) !void {
    for (reporter.diagnostics.items) |*diag| {
        try writeDiagShort(diag, writer);
    }
}

fn writeDiagShort(diag: *const errors.OrhonDiag, writer: anytype) !void {
    var code_buf: [8]u8 = undefined;
    const severity_str: []const u8 = switch (diag.severity) {
        .err     => "error",
        .warning => "warning",
        .note    => "note",
        .hint    => "hint",
    };
    if (diag.loc) |loc| {
        if (loc.file.len > 0 and loc.line > 0) {
            if (loc.col > 0) {
                try writer.print("{s}:{d}:{d}: ", .{ loc.file, loc.line, loc.col });
            } else {
                try writer.print("{s}:{d}: ", .{ loc.file, loc.line });
            }
        }
    }
    if (diag.code) |code| {
        const code_str = code.toCode(&code_buf);
        try writer.print("{s}[{s}]: {s}\n", .{ severity_str, code_str, diag.message });
    } else {
        try writer.print("{s}: {s}\n", .{ severity_str, diag.message });
    }
}

// ── Tests ──────────────────────────────────────────────────────────────────────

test "flushJson produces wrapped JSON object" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();
    _ = try reporter.report(.{
        .code = .unknown_identifier,
        .message = "unknown identifier 'foo'",
        .loc = .{ .file = "src/main.orh", .line = 10, .col = 5 },
    });
    _ = try reporter.warn(.{
        .message = "unused import",
    });
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushJson(&reporter, out.writer(std.testing.allocator));
    // insertion order: error first (appended first), then warning
    const expected =
        \\{"version":1,"diagnostics":[{"severity":"error","code":"E2040","message":"unknown identifier 'foo'","file":"src/main.orh","line":10,"col":5},{"severity":"warning","message":"unused import"}]}
        \\
    ;
    try std.testing.expectEqualStrings(expected, out.items);
}

test "flushShort with loc and code" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();
    _ = try reporter.report(.{
        .code = .unknown_identifier,
        .message = "unknown identifier 'foo'",
        .loc = .{ .file = "src/main.orh", .line = 10, .col = 5 },
    });
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushShort(&reporter, out.writer(std.testing.allocator));
    try std.testing.expectEqualStrings(
        "src/main.orh:10:5: error[E2040]: unknown identifier 'foo'\n",
        out.items,
    );
}

test "flushShort without loc" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();
    _ = try reporter.report(.{ .message = "internal error" });
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushShort(&reporter, out.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("error: internal error\n", out.items);
}

test "flushShort loc with zero col omits col" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();
    _ = try reporter.report(.{
        .message = "type mismatch",
        .loc = .{ .file = "src/foo.orh", .line = 3, .col = 0 },
    });
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushShort(&reporter, out.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("src/foo.orh:3: error: type mismatch\n", out.items);
}

test "flushHuman use_color false produces no ANSI escapes" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();
    _ = try reporter.report(.{ .code = .unknown_identifier, .message = "test error" });
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushHuman(&reporter, .debug, out.writer(std.testing.allocator), false);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1b[") == null);
}

test "flushHuman use_color true contains ANSI escapes" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();
    _ = try reporter.report(.{ .code = .unknown_identifier, .message = "test error" });
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushHuman(&reporter, .debug, out.writer(std.testing.allocator), true);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1b[") != null);
}

test "flushHuman renders note after parent diagnostic" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    const idx = try reporter.report(.{ .code = .unknown_identifier, .message = "unknown 'x'" });
    try reporter.note(idx, .{ .message = "defined here", .loc = .{ .file = "src/a.orh", .line = 5, .col = 0 } });

    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushHuman(&reporter, .debug, out.writer(std.testing.allocator), false);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "unknown 'x'") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "note:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "defined here") != null);
    const parent_pos = std.mem.indexOf(u8, out.items, "unknown 'x'").?;
    const note_pos   = std.mem.indexOf(u8, out.items, "note:").?;
    try std.testing.expect(note_pos > parent_pos);
}

test "flushJson emits severity and parent on note" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    const idx = try reporter.report(.{
        .code = .unknown_identifier,
        .message = "unknown 'x'",
        .loc = .{ .file = "src/a.orh", .line = 3, .col = 1 },
    });
    try reporter.note(idx, .{ .message = "defined here" });

    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try flushJson(&reporter, out.writer(std.testing.allocator));

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"severity\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"severity\":\"note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"parent\":0") != null);
}
