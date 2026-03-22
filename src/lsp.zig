// lsp.zig — Kodr Language Server Protocol (Phase 1: diagnostics)
// JSON-RPC over stdio. Runs analysis passes 1–9 and publishes diagnostics.

const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const module = @import("module.zig");
const declarations = @import("declarations.zig");
const resolver = @import("resolver.zig");
const ownership = @import("ownership.zig");
const borrow = @import("borrow.zig");
const thread_safety = @import("thread_safety.zig");
const propagation = @import("propagation.zig");
const errors = @import("errors.zig");
const cache = @import("cache.zig");

const Io = std.Io;

// ============================================================
// JSON-RPC TRANSPORT
// ============================================================

/// Read a single LSP message from stdin.
/// Format: "Content-Length: N\r\n\r\n<N bytes of JSON>"
fn readMessage(reader: *Io.Reader, allocator: std.mem.Allocator) ![]u8 {
    var content_length: usize = 0;

    // Read headers line by line
    while (true) {
        var line_buf: [1024]u8 = undefined;
        var line_len: usize = 0;

        while (line_len < line_buf.len) {
            const byte = reader.takeByte() catch return error.EndOfStream;
            if (byte == '\r') {
                _ = reader.takeByte() catch return error.EndOfStream;
                break;
            }
            line_buf[line_len] = byte;
            line_len += 1;
        }

        const line = line_buf[0..line_len];
        if (line.len == 0) break;

        const prefix = "Content-Length: ";
        if (std.mem.startsWith(u8, line, prefix)) {
            content_length = std.fmt.parseInt(usize, line[prefix.len..], 10) catch return error.InvalidHeader;
        }
    }

    if (content_length == 0) return error.InvalidHeader;
    return reader.readAlloc(allocator, content_length) catch return error.EndOfStream;
}

/// Write an LSP message to stdout.
fn writeMessage(writer: *Io.Writer, json: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{json.len});
    try writer.writeAll(json);
    try writer.flush();
}

// ============================================================
// JSON HELPERS
// ============================================================

fn jsonStr(value: std.json.Value, key: []const u8) ?[]const u8 {
    const obj = switch (value) { .object => |o| o, else => return null };
    const val = obj.get(key) orelse return null;
    return switch (val) { .string => |s| s, else => null };
}

fn jsonObj(value: std.json.Value, key: []const u8) ?std.json.Value {
    const obj = switch (value) { .object => |o| o, else => return null };
    const val = obj.get(key) orelse return null;
    return switch (val) { .object => val, else => null };
}

fn jsonId(root: std.json.Value) std.json.Value {
    return switch (root) {
        .object => |obj| obj.get("id") orelse .null,
        else => .null,
    };
}

// ============================================================
// JSON RESPONSE BUILDERS
// ============================================================

fn writeJsonValue(w: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: std.json.Value) !void {
    switch (value) {
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
            try w.appendSlice(allocator, s);
        },
        .string => |s| {
            try w.append(allocator, '"');
            try appendJsonString(w, allocator, s);
            try w.append(allocator, '"');
        },
        .null => try w.appendSlice(allocator, "null"),
        else => try w.appendSlice(allocator, "null"),
    }
}

fn appendJsonString(w: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try w.appendSlice(allocator, "\\\""),
            '\\' => try w.appendSlice(allocator, "\\\\"),
            '\n' => try w.appendSlice(allocator, "\\n"),
            '\r' => try w.appendSlice(allocator, "\\r"),
            '\t' => try w.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = undefined;
                    const esc = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch continue;
                    try w.appendSlice(allocator, esc);
                } else {
                    try w.append(allocator, c);
                }
            },
        }
    }
}

fn buildInitializeResult(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator,
        \\,"result":{"capabilities":{"textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":false}}},"serverInfo":{"name":"kodr-lsp","version":"0.1.0"}}}
    );

    return allocator.dupe(u8, buf.items);
}

fn buildEmptyResponse(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator, ",\"result\":null}");

    return allocator.dupe(u8, buf.items);
}

const Diagnostic = struct {
    uri: []const u8,
    line: usize, // 0-based
    col: usize, // 0-based
    severity: u8, // 1=error, 2=warning
    message: []const u8,
};

fn buildDiagnosticsMsg(allocator: std.mem.Allocator, uri: []const u8, diags: []const Diagnostic) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"");
    try appendJsonString(&buf, allocator, uri);
    try buf.appendSlice(allocator, "\",\"diagnostics\":[");

    var first = true;
    for (diags) |d| {
        if (!std.mem.eql(u8, d.uri, uri)) continue;
        if (!first) try buf.append(allocator, ',');
        first = false;

        try buf.appendSlice(allocator, "{\"range\":{\"start\":{\"line\":");
        var nbuf: [16]u8 = undefined;
        var s = std.fmt.bufPrint(&nbuf, "{d}", .{d.line}) catch "0";
        try buf.appendSlice(allocator, s);
        try buf.appendSlice(allocator, ",\"character\":");
        s = std.fmt.bufPrint(&nbuf, "{d}", .{d.col}) catch "0";
        try buf.appendSlice(allocator, s);
        try buf.appendSlice(allocator, "},\"end\":{\"line\":");
        s = std.fmt.bufPrint(&nbuf, "{d}", .{d.line}) catch "0";
        try buf.appendSlice(allocator, s);
        try buf.appendSlice(allocator, ",\"character\":");
        s = std.fmt.bufPrint(&nbuf, "{d}", .{d.col + 1}) catch "0";
        try buf.appendSlice(allocator, s);
        try buf.appendSlice(allocator, "}},\"severity\":");
        s = std.fmt.bufPrint(&nbuf, "{d}", .{d.severity}) catch "1";
        try buf.appendSlice(allocator, s);
        try buf.appendSlice(allocator, ",\"source\":\"kodr\",\"message\":\"");
        try appendJsonString(&buf, allocator, d.message);
        try buf.appendSlice(allocator, "\"}");
    }

    try buf.appendSlice(allocator, "]}}");
    return allocator.dupe(u8, buf.items);
}

// ============================================================
// URI HELPERS
// ============================================================

fn uriToPath(uri: []const u8) ?[]const u8 {
    const prefix = "file://";
    if (std.mem.startsWith(u8, uri, prefix)) return uri[prefix.len..];
    return null;
}

fn pathToUri(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "file://{s}", .{path});
}

/// Given a file path inside src/, find the project root (parent of src/).
fn findProjectRoot(file_path: []const u8) ?[]const u8 {
    var dir = std.fs.path.dirname(file_path) orelse return null;
    var depth: usize = 0;
    while (depth < 10) : (depth += 1) {
        if (std.mem.eql(u8, std.fs.path.basename(dir), "src")) {
            return std.fs.path.dirname(dir);
        }
        const parent = std.fs.path.dirname(dir) orelse return null;
        if (std.mem.eql(u8, parent, dir)) return null;
        dir = parent;
    }
    return null;
}

// ============================================================
// ANALYSIS — run passes 1–9, collect diagnostics
// ============================================================

fn runAnalysis(allocator: std.mem.Allocator, project_root: []const u8) ![]Diagnostic {
    const saved_cwd = std.fs.cwd();
    var proj_dir = std.fs.cwd().openDir(project_root, .{}) catch return &.{};
    defer proj_dir.close();
    proj_dir.setAsCwd() catch return &.{};
    defer saved_cwd.setAsCwd() catch {};

    // Ensure std files exist
    std.fs.cwd().makePath(cache.CACHE_DIR ++ "/std") catch {};

    var reporter = errors.Reporter.init(allocator, .debug);
    defer reporter.deinit();

    var mod_resolver = module.Resolver.init(allocator, &reporter);
    defer mod_resolver.deinit();

    std.fs.cwd().access("src", .{}) catch return &.{};
    mod_resolver.scanDirectory("src") catch return toDiagnostics(allocator, &reporter, project_root);
    if (reporter.hasErrors()) return toDiagnostics(allocator, &reporter, project_root);

    mod_resolver.checkCircularImports() catch {};
    if (reporter.hasErrors()) return toDiagnostics(allocator, &reporter, project_root);

    mod_resolver.parseModules(allocator) catch {};
    if (reporter.hasErrors()) return toDiagnostics(allocator, &reporter, project_root);

    // Second parse pass for std imports
    {
        var has_unparsed = false;
        var it = mod_resolver.modules.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.ast == null) { has_unparsed = true; break; }
        }
        if (has_unparsed) {
            mod_resolver.parseModules(allocator) catch {};
            if (reporter.hasErrors()) return toDiagnostics(allocator, &reporter, project_root);
        }
    }

    mod_resolver.scanAndParseDeps(allocator, "src") catch {};
    if (reporter.hasErrors()) return toDiagnostics(allocator, &reporter, project_root);

    mod_resolver.validateImports(&reporter) catch {};
    if (reporter.hasErrors()) return toDiagnostics(allocator, &reporter, project_root);

    const order = mod_resolver.topologicalOrder(allocator) catch
        return toDiagnostics(allocator, &reporter, project_root);
    defer allocator.free(order);

    // Passes 4–9 per module
    for (order) |mod_name| {
        const mod_ptr = mod_resolver.modules.getPtr(mod_name) orelse continue;
        const ast = mod_ptr.ast orelse continue;
        const locs_ptr: ?*const parser.LocMap = if (mod_ptr.locs) |*l| l else null;
        const source_file: []const u8 = if (mod_ptr.files.len > 0) mod_ptr.files[0] else "";

        // Pass 4: Declarations
        var dc = declarations.DeclCollector.init(allocator, &reporter);
        defer dc.deinit();
        dc.locs = locs_ptr;
        dc.source_file = source_file;
        dc.collect(ast) catch {};
        if (reporter.hasErrors()) break;

        // Pass 5: Type Resolution
        var tr = resolver.TypeResolver.init(allocator, &dc.table, &reporter);
        defer tr.deinit();
        tr.locs = locs_ptr;
        tr.source_file = source_file;
        tr.resolve(ast) catch {};
        if (reporter.hasErrors()) break;

        // Pass 6: Ownership
        var oc = ownership.OwnershipChecker.init(allocator, &reporter);
        oc.locs = locs_ptr;
        oc.source_file = source_file;
        oc.decls = &dc.table;
        oc.check(ast) catch {};
        if (reporter.hasErrors()) break;

        // Pass 7: Borrow Checking
        var bc = borrow.BorrowChecker.init(allocator, &reporter);
        defer bc.deinit();
        bc.locs = locs_ptr;
        bc.source_file = source_file;
        bc.decls = &dc.table;
        bc.check(ast) catch {};
        if (reporter.hasErrors()) break;

        // Pass 8: Thread Safety
        var tc = thread_safety.ThreadSafetyChecker.init(allocator, &reporter);
        defer tc.deinit();
        tc.locs = locs_ptr;
        tc.source_file = source_file;
        tc.check(ast) catch {};
        if (reporter.hasErrors()) break;

        // Pass 9: Error Propagation
        var pc = propagation.PropChecker.init(allocator, &reporter, &dc.table);
        pc.locs = locs_ptr;
        pc.source_file = source_file;
        pc.check(ast) catch {};
        if (reporter.hasErrors()) break;
    }

    return toDiagnostics(allocator, &reporter, project_root);
}

/// Convert Reporter errors/warnings into LSP Diagnostics with file URIs.
fn toDiagnostics(allocator: std.mem.Allocator, reporter: *errors.Reporter, project_root: []const u8) ![]Diagnostic {
    var diags: std.ArrayListUnmanaged(Diagnostic) = .{};

    for (reporter.errors.items) |err| {
        const d = makeDiag(allocator, err, 1, project_root) catch continue;
        try diags.append(allocator, d);
    }
    for (reporter.warnings.items) |warn| {
        const d = makeDiag(allocator, warn, 2, project_root) catch continue;
        try diags.append(allocator, d);
    }

    return if (diags.items.len > 0) allocator.dupe(Diagnostic, diags.items) else &.{};
}

fn makeDiag(allocator: std.mem.Allocator, err: errors.KodrError, severity: u8, project_root: []const u8) !Diagnostic {
    const loc = err.loc orelse return error.NoLoc;
    if (loc.file.len == 0) return error.NoLoc;

    const full_path = if (!std.fs.path.isAbsolute(loc.file))
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ project_root, loc.file })
    else
        try allocator.dupe(u8, loc.file);

    return .{
        .uri = try pathToUri(allocator, full_path),
        .line = if (loc.line > 0) loc.line - 1 else 0,
        .col = if (loc.col > 0) loc.col - 1 else 0,
        .severity = severity,
        .message = try allocator.dupe(u8, err.message),
    };
}

// ============================================================
// LSP SERVER
// ============================================================

fn log(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    var w = std.fs.File.stderr().writer(&buf);
    const stderr = &w.interface;
    stderr.print("[kodr-lsp] " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
}

pub fn serve(allocator: std.mem.Allocator) !void {
    const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    var stdin_buf: [65536]u8 = undefined;
    var stdin_r = stdin_file.reader(&stdin_buf);
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var stdout_buf: [65536]u8 = undefined;
    var stdout_w = stdout_file.writer(&stdout_buf);

    const stdin: *Io.Reader = &stdin_r.interface;
    const stdout: *Io.Writer = &stdout_w.interface;

    log("server starting", .{});

    var initialized = false;
    var project_root: ?[]const u8 = null;

    // Track open document URIs for clearing stale diagnostics
    var open_docs = std.StringHashMap(void).init(allocator);
    defer {
        var it = open_docs.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        open_docs.deinit();
    }

    while (true) {
        const body = readMessage(stdin, allocator) catch |err| {
            if (err == error.EndOfStream) { log("client disconnected", .{}); return; }
            log("read error: {}", .{err});
            continue;
        };
        defer allocator.free(body);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
            log("invalid JSON", .{});
            continue;
        };
        defer parsed.deinit();

        const root = parsed.value;
        const method = jsonStr(root, "method") orelse "";
        const id = jsonId(root);

        if (std.mem.eql(u8, method, "initialize")) {
            log("initialize", .{});
            if (jsonObj(root, "params")) |params| {
                if (jsonStr(params, "rootUri")) |root_uri| {
                    if (uriToPath(root_uri)) |path| {
                        project_root = try allocator.dupe(u8, path);
                        log("project root: {s}", .{path});
                    }
                }
            }
            const resp = try buildInitializeResult(allocator, id);
            defer allocator.free(resp);
            try writeMessage(stdout, resp);

        } else if (std.mem.eql(u8, method, "initialized")) {
            initialized = true;
            log("initialized", .{});
            if (project_root) |r| try publishDiagnostics(allocator, stdout, r, &open_docs);

        } else if (std.mem.eql(u8, method, "shutdown")) {
            log("shutdown", .{});
            const resp = try buildEmptyResponse(allocator, id);
            defer allocator.free(resp);
            try writeMessage(stdout, resp);

        } else if (std.mem.eql(u8, method, "exit")) {
            log("exit", .{});
            return;

        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            if (!initialized) continue;
            if (jsonObj(root, "params")) |params| {
                if (jsonObj(params, "textDocument")) |td| {
                    if (jsonStr(td, "uri")) |uri| {
                        log("didOpen: {s}", .{uri});
                        if (!open_docs.contains(uri))
                            try open_docs.put(try allocator.dupe(u8, uri), {});
                        if (project_root == null) {
                            if (uriToPath(uri)) |path| {
                                if (findProjectRoot(path)) |r| {
                                    project_root = try allocator.dupe(u8, r);
                                    log("detected root: {s}", .{r});
                                }
                            }
                        }
                        if (project_root) |r| try publishDiagnostics(allocator, stdout, r, &open_docs);
                    }
                }
            }

        } else if (std.mem.eql(u8, method, "textDocument/didSave")) {
            if (!initialized) continue;
            log("didSave", .{});
            if (project_root) |r| try publishDiagnostics(allocator, stdout, r, &open_docs);

        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            // Phase 1: analyze on save only (full sync mode registered but we skip re-analysis on typing)
            // This avoids hammering the analysis on every keystroke.

        } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
            if (!initialized) continue;
            if (jsonObj(root, "params")) |params| {
                if (jsonObj(params, "textDocument")) |td| {
                    if (jsonStr(td, "uri")) |uri| {
                        log("didClose: {s}", .{uri});
                        const clear = buildDiagnosticsMsg(allocator, uri, &.{}) catch continue;
                        defer allocator.free(clear);
                        writeMessage(stdout, clear) catch {};
                        if (open_docs.fetchRemove(uri)) |kv| allocator.free(kv.key);
                    }
                }
            }

        } else {
            // Unknown request — respond with null result
            switch (id) {
                .integer, .string => {
                    const resp = try buildEmptyResponse(allocator, id);
                    defer allocator.free(resp);
                    try writeMessage(stdout, resp);
                },
                else => {},
            }
        }
    }
}

/// Run analysis and publish diagnostics for all open files.
fn publishDiagnostics(
    allocator: std.mem.Allocator,
    writer: *Io.Writer,
    project_root: []const u8,
    open_docs: *std.StringHashMap(void),
) !void {
    const diags = try runAnalysis(allocator, project_root);
    defer {
        if (diags.len > 0) {
            for (diags) |d| {
                allocator.free(d.uri);
                allocator.free(d.message);
            }
            allocator.free(diags);
        }
    }

    // Collect unique URIs that have diagnostics
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    for (diags) |d| {
        if (!seen.contains(d.uri)) {
            try seen.put(d.uri, {});
            const msg = try buildDiagnosticsMsg(allocator, d.uri, diags);
            defer allocator.free(msg);
            try writeMessage(writer, msg);
        }
    }

    // Clear diagnostics for open files that have no errors anymore
    var doc_it = open_docs.iterator();
    while (doc_it.next()) |entry| {
        if (!seen.contains(entry.key_ptr.*)) {
            const clear = try buildDiagnosticsMsg(allocator, entry.key_ptr.*, &.{});
            defer allocator.free(clear);
            try writeMessage(writer, clear);
        }
    }
}

// ============================================================
// TESTS
// ============================================================

test "uriToPath converts file URI" {
    const path = uriToPath("file:///home/user/project/src/main.kodr");
    try std.testing.expectEqualStrings("/home/user/project/src/main.kodr", path.?);
}

test "uriToPath returns null for non-file URI" {
    try std.testing.expect(uriToPath("https://example.com") == null);
}

test "findProjectRoot detects src directory" {
    const root = findProjectRoot("/home/user/project/src/main.kodr");
    try std.testing.expectEqualStrings("/home/user/project", root.?);
}

test "appendJsonString escapes special characters" {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try appendJsonString(&buf, std.testing.allocator, "hello \"world\"\nnew\\line");
    try std.testing.expectEqualStrings("hello \\\"world\\\"\\nnew\\\\line", buf.items);
}

test "readMessage parses LSP header" {
    const input = "Content-Length: 13\r\n\r\n{\"test\":true}";
    var reader = Io.Reader.fixed(input);
    const body = try readMessage(&reader, std.testing.allocator);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"test\":true}", body);
}
