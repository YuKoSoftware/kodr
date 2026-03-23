// ini.zig — INI file parsing sidecar for std::ini
// Supports [section] headers, key=value pairs, and # ; comments.

const std = @import("std");
const _rt = @import("_orhon_rt");

const alloc = std.heap.page_allocator;
const OrhonResult = _rt.OrhonResult;

// ── Internal: Parse into section→key→value map ──

const IniMap = struct {
    sections: []const Section,
};

const Section = struct {
    name: []const u8,
    keys: []const Entry,
};

const Entry = struct {
    key: []const u8,
    value: []const u8,
};

fn parseIni(source: []const u8) IniMap {
    var sections = std.ArrayListUnmanaged(Section){};
    var current_name: []const u8 = "";
    var current_entries = std.ArrayListUnmanaged(Entry){};

    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");

        // Skip empty lines and comments
        if (line.len == 0) continue;
        if (line[0] == '#' or line[0] == ';') continue;

        // Section header
        if (line[0] == '[') {
            // Flush previous section
            if (current_name.len > 0 or current_entries.items.len > 0) {
                sections.append(alloc, .{
                    .name = current_name,
                    .keys = alloc.dupe(Entry, current_entries.items) catch &.{},
                }) catch {};
                current_entries.clearRetainingCapacity();
            }
            const end = std.mem.indexOfScalar(u8, line, ']') orelse line.len;
            current_name = alloc.dupe(u8, line[1..end]) catch "";
            continue;
        }

        // Key = Value
        if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
            const key = std.mem.trim(u8, line[0..eq], " \t");
            const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
            current_entries.append(alloc, .{
                .key = alloc.dupe(u8, key) catch "",
                .value = alloc.dupe(u8, value) catch "",
            }) catch {};
        }
    }

    // Flush last section
    if (current_name.len > 0 or current_entries.items.len > 0) {
        sections.append(alloc, .{
            .name = current_name,
            .keys = alloc.dupe(Entry, current_entries.items) catch &.{},
        }) catch {};
    }

    return .{ .sections = sections.items };
}

fn findValue(ini: IniMap, section: []const u8, key: []const u8) ?[]const u8 {
    for (ini.sections) |sec| {
        if (std.mem.eql(u8, sec.name, section)) {
            for (sec.keys) |entry| {
                if (std.mem.eql(u8, entry.key, key)) return entry.value;
            }
        }
    }
    return null;
}

// ── Get ──

pub fn get(source: []const u8, path: []const u8) OrhonResult([]const u8) {
    const dot = std.mem.indexOfScalar(u8, path, '.') orelse {
        return .{ .err = .{ .message = "path must be section.key" } };
    };
    const section = path[0..dot];
    const key = path[dot + 1 ..];
    const ini = parseIni(source);
    if (findValue(ini, section, key)) |val| {
        return .{ .ok = val };
    }
    return .{ .err = .{ .message = "key not found" } };
}

// ── HasKey ──

pub fn hasKey(source: []const u8, path: []const u8) bool {
    const dot = std.mem.indexOfScalar(u8, path, '.') orelse return false;
    const section = path[0..dot];
    const key = path[dot + 1 ..];
    const ini = parseIni(source);
    return findValue(ini, section, key) != null;
}

// ── GetKeys ──

pub fn getKeys(source: []const u8, section: []const u8) OrhonResult([]const u8) {
    const ini = parseIni(source);
    for (ini.sections) |sec| {
        if (std.mem.eql(u8, sec.name, section)) {
            var buf = std.ArrayListUnmanaged(u8){};
            for (sec.keys, 0..) |entry, i| {
                if (i > 0) buf.append(alloc, '\n') catch {};
                buf.appendSlice(alloc, entry.key) catch {};
            }
            return .{ .ok = if (buf.items.len > 0) buf.items else "" };
        }
    }
    return .{ .err = .{ .message = "section not found" } };
}

// ── GetSections ──

pub fn getSections(source: []const u8) []const u8 {
    const ini = parseIni(source);
    var buf = std.ArrayListUnmanaged(u8){};
    for (ini.sections, 0..) |sec, i| {
        if (sec.name.len == 0) continue;
        if (i > 0 and buf.items.len > 0) buf.append(alloc, '\n') catch {};
        buf.appendSlice(alloc, sec.name) catch {};
    }
    return if (buf.items.len > 0) buf.items else "";
}

// ── Tests ──

test "get value" {
    const ini =
        \\[database]
        \\host = localhost
        \\port = 5432
    ;
    const r = get(ini, "database.host");
    try std.testing.expect(r == .ok);
    try std.testing.expect(std.mem.eql(u8, r.ok, "localhost"));
    const r2 = get(ini, "database.port");
    try std.testing.expect(r2 == .ok);
    try std.testing.expect(std.mem.eql(u8, r2.ok, "5432"));
}

test "hasKey" {
    const ini =
        \\[app]
        \\name = orhon
    ;
    try std.testing.expect(hasKey(ini, "app.name"));
    try std.testing.expect(!hasKey(ini, "app.version"));
    try std.testing.expect(!hasKey(ini, "other.name"));
}

test "getKeys" {
    const ini =
        \\[server]
        \\host = 0.0.0.0
        \\port = 8080
        \\debug = true
    ;
    const r = getKeys(ini, "server");
    try std.testing.expect(r == .ok);
    try std.testing.expect(std.mem.eql(u8, r.ok, "host\nport\ndebug"));
}

test "getSections" {
    const ini =
        \\[a]
        \\x = 1
        \\[b]
        \\y = 2
    ;
    const s = getSections(ini);
    try std.testing.expect(std.mem.eql(u8, s, "a\nb"));
}

test "comments ignored" {
    const ini =
        \\# This is a comment
        \\; Another comment
        \\[main]
        \\key = value
    ;
    const r = get(ini, "main.key");
    try std.testing.expect(r == .ok);
    try std.testing.expect(std.mem.eql(u8, r.ok, "value"));
}

test "missing key" {
    const ini =
        \\[db]
        \\host = localhost
    ;
    try std.testing.expect(get(ini, "db.port") == .err);
}
