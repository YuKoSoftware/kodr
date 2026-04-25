// test/runner.zig — Orhon diagnostic fixture test runner
const std = @import("std");

// ── Types ─────────────────────────────────────────────────────────────────────

const Annotation = struct { line: u32, code: []const u8 };
const Diag       = struct { code: []const u8, line: u32 };

const Mismatch = union(enum) {
    missing:    Annotation,
    unexpected: Diag,
};

const TestResult = union(enum) {
    pass,
    skip,
    fail:        []const u8,  // formatted failure message, caller must free
    setup_error: []const u8,  // caller must free
};

// ── Pure functions ─────────────────────────────────────────────────────────────

/// Scan a fixture's source for //> [Exxxx] annotations.
/// Returns (line_number, code) pairs — line numbers are 1-based.
fn scanAnnotationsFromContent(content: []const u8, allocator: std.mem.Allocator) ![]Annotation {
    var list = std.ArrayList(Annotation){};
    errdefer {
        for (list.items) |a| allocator.free(a.code);
        list.deinit(allocator);
    }
    var line_num: u32 = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        line_num += 1;
        const marker_pos = std.mem.indexOf(u8, line, "//>") orelse continue;
        var rest = line[marker_pos + 3..];
        while (std.mem.indexOfScalar(u8, rest, '[')) |open| {
            rest = rest[open + 1..];
            const close = std.mem.indexOfScalar(u8, rest, ']') orelse break;
            const raw = rest[0..close];
            rest = rest[close + 1..];
            if (raw.len < 2 or raw[0] != 'E') continue;
            const digits_ok = for (raw[1..]) |c| {
                if (c < '0' or c > '9') break false;
            } else true;
            if (!digits_ok) continue;
            const code = try allocator.dupe(u8, raw);
            errdefer allocator.free(code);
            try list.append(allocator, .{ .line = line_num, .code = code });
        }
    }
    return list.toOwnedSlice(allocator);
}

/// Extract the module name from the first `module <name>` line in a fixture.
fn extractModuleNameFromContent(content: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, "module ")) continue;
        const after = std.mem.trimLeft(u8, trimmed[7..], " \t");
        const end = std.mem.indexOfAny(u8, after, " \t\r\n") orelse after.len;
        if (end == 0) continue;
        return allocator.dupe(u8, after[0..end]);
    }
    return error.ModuleNotFound;
}

/// Compare expected annotations against actual diagnostics.
/// Missing = annotation with no matching actual diag.
/// Unexpected = actual diag with no matching annotation.
fn compareResults(
    expected: []const Annotation,
    actual:   []const Diag,
    allocator: std.mem.Allocator,
) ![]Mismatch {
    var list = std.ArrayList(Mismatch){};
    errdefer list.deinit(allocator);
    var matched = try allocator.alloc(bool, actual.len);
    defer allocator.free(matched);
    @memset(matched, false);

    for (expected) |ann| {
        var found = false;
        for (actual, 0..) |diag, i| {
            if (matched[i]) continue;
            if (diag.line == ann.line and std.mem.eql(u8, diag.code, ann.code)) {
                matched[i] = true;
                found = true;
                break;
            }
        }
        if (!found) try list.append(allocator, .{ .missing = ann });
    }
    for (actual, 0..) |diag, i| {
        if (!matched[i]) try list.append(allocator, .{ .unexpected = diag });
    }
    return list.toOwnedSlice(allocator);
}

pub fn main() !void {}

// ── Unit tests ────────────────────────────────────────────────────────────────

test "scanAnnotations: no annotations returns empty" {
    const alloc = std.testing.allocator;
    const src = "module foo\nfunc main() void {}\n";
    const anns = try scanAnnotationsFromContent(src, alloc);
    defer { for (anns) |a| alloc.free(a.code); alloc.free(anns); }
    try std.testing.expectEqual(@as(usize, 0), anns.len);
}

test "scanAnnotations: single annotation" {
    const alloc = std.testing.allocator;
    const src = "module foo\n    var x: i32 = 0  //> [E2005]\n";
    const anns = try scanAnnotationsFromContent(src, alloc);
    defer { for (anns) |a| alloc.free(a.code); alloc.free(anns); }
    try std.testing.expectEqual(@as(usize, 1), anns.len);
    try std.testing.expectEqual(@as(u32, 2), anns[0].line);
    try std.testing.expectEqualStrings("E2005", anns[0].code);
}

test "scanAnnotations: multiple on one line" {
    const alloc = std.testing.allocator;
    const src = "func foo(a: i32 = 5, b: i32) void {}  //> [E2002] [E2028]\n";
    const anns = try scanAnnotationsFromContent(src, alloc);
    defer { for (anns) |a| alloc.free(a.code); alloc.free(anns); }
    try std.testing.expectEqual(@as(usize, 2), anns.len);
    try std.testing.expectEqualStrings("E2002", anns[0].code);
    try std.testing.expectEqualStrings("E2028", anns[1].code);
}

test "extractModuleName: basic" {
    const alloc = std.testing.allocator;
    const name = try extractModuleNameFromContent("module my_mod\nfunc f() void {}\n", alloc);
    defer alloc.free(name);
    try std.testing.expectEqualStrings("my_mod", name);
}

test "extractModuleName: missing returns error" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.ModuleNotFound,
        extractModuleNameFromContent("func main() void {}\n", alloc));
}

test "compareResults: exact match is empty mismatches" {
    const alloc = std.testing.allocator;
    const expected = [_]Annotation{.{ .line = 5, .code = "E2005" }};
    const actual   = [_]Diag{      .{ .line = 5, .code = "E2005" }};
    const mm = try compareResults(&expected, &actual, alloc);
    defer alloc.free(mm);
    try std.testing.expectEqual(@as(usize, 0), mm.len);
}

test "compareResults: missing annotation" {
    const alloc = std.testing.allocator;
    const expected = [_]Annotation{.{ .line = 5, .code = "E2005" }};
    const mm = try compareResults(&expected, &[_]Diag{}, alloc);
    defer alloc.free(mm);
    try std.testing.expectEqual(@as(usize, 1), mm.len);
    try std.testing.expect(mm[0] == .missing);
}

test "compareResults: unexpected diagnostic" {
    const alloc = std.testing.allocator;
    const actual = [_]Diag{.{ .line = 3, .code = "E2013" }};
    const mm = try compareResults(&[_]Annotation{}, &actual, alloc);
    defer alloc.free(mm);
    try std.testing.expectEqual(@as(usize, 1), mm.len);
    try std.testing.expect(mm[0] == .unexpected);
}
