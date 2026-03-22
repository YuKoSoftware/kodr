// lsp.zig — Kodr Language Server Protocol
// JSON-RPC over stdio. Runs analysis passes 1–9, publishes diagnostics,
// and provides hover, go-to-definition, document symbols, and completion.

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
const types = @import("types.zig");
const builtins = @import("builtins.zig");

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

fn jsonInt(value: std.json.Value, key: []const u8) ?i64 {
    const obj = switch (value) { .object => |o| o, else => return null };
    const val = obj.get(key) orelse return null;
    return switch (val) { .integer => |i| i, else => null };
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

fn appendInt(w: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, val: usize) !void {
    var nbuf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&nbuf, "{d}", .{val}) catch "0";
    try w.appendSlice(allocator, s);
}

fn buildInitializeResult(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator,
        \\,"result":{"capabilities":{"textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":false}},"hoverProvider":true,"definitionProvider":true,"documentSymbolProvider":true,"completionProvider":{"triggerCharacters":["."]}},"serverInfo":{"name":"kodr-lsp","version":"0.3.0"}}}
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
        try appendInt(&buf, allocator, d.line);
        try buf.appendSlice(allocator, ",\"character\":");
        try appendInt(&buf, allocator, d.col);
        try buf.appendSlice(allocator, "},\"end\":{\"line\":");
        try appendInt(&buf, allocator, d.line);
        try buf.appendSlice(allocator, ",\"character\":");
        try appendInt(&buf, allocator, d.col + 1);
        try buf.appendSlice(allocator, "}},\"severity\":");
        try appendInt(&buf, allocator, d.severity);
        try buf.appendSlice(allocator, ",\"source\":\"kodr\",\"message\":\"");
        try appendJsonString(&buf, allocator, d.message);
        try buf.appendSlice(allocator, "\"}");
    }

    try buf.appendSlice(allocator, "]}}");
    return allocator.dupe(u8, buf.items);
}

// ============================================================
// SYMBOL INFO — cached analysis data for hover/definition/symbols
// ============================================================

/// LSP symbol kinds (subset we use)
const SymbolKind = enum(u8) {
    function = 12,
    struct_ = 23,
    enum_ = 10,
    variable = 13,
    constant = 14,
    field = 8,
    enum_member = 22,
};

/// Flattened symbol info extracted from DeclTable + LocMap.
/// All strings are owned by the allocator.
const SymbolInfo = struct {
    name: []const u8,
    detail: []const u8, // type signature for hover
    kind: SymbolKind,
    module: []const u8, // owning module name (e.g. "main", "console")
    parent: []const u8, // parent symbol name (e.g. "MyStruct" for fields, "" for top-level)
    uri: []const u8, // file URI
    line: usize, // 0-based
    col: usize, // 0-based
};

/// Result of running analysis — diagnostics + symbols
const AnalysisResult = struct {
    diagnostics: []Diagnostic,
    symbols: []SymbolInfo,
};

fn freeAnalysisResult(allocator: std.mem.Allocator, result: *AnalysisResult) void {
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| {
            allocator.free(d.uri);
            allocator.free(d.message);
        }
        allocator.free(result.diagnostics);
    }
    freeSymbols(allocator, result.symbols);
}

fn freeSymbols(allocator: std.mem.Allocator, symbols: []SymbolInfo) void {
    if (symbols.len > 0) {
        for (symbols) |s| {
            allocator.free(s.name);
            allocator.free(s.detail);
            allocator.free(s.module);
            if (s.parent.len > 0) allocator.free(s.parent);
            allocator.free(s.uri);
        }
        allocator.free(symbols);
    }
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
// TYPE FORMATTING — for hover display
// ============================================================

fn formatType(allocator: std.mem.Allocator, t: types.ResolvedType) ![]u8 {
    return switch (t) {
        .primitive => |n| allocator.dupe(u8, n),
        .named => |n| allocator.dupe(u8, n),
        .err => allocator.dupe(u8, "Error"),
        .null_type => allocator.dupe(u8, "null"),
        .slice => |inner| blk: {
            const inner_s = try formatType(allocator, inner.*);
            defer allocator.free(inner_s);
            break :blk std.fmt.allocPrint(allocator, "[]{s}", .{inner_s});
        },
        .array => |a| blk: {
            const inner_s = try formatType(allocator, a.elem.*);
            defer allocator.free(inner_s);
            const size_str = if (a.size.* == .int_literal) a.size.int_literal else "N";
            break :blk std.fmt.allocPrint(allocator, "[{s}]{s}", .{ size_str, inner_s });
        },
        .error_union => |inner| blk: {
            const inner_s = try formatType(allocator, inner.*);
            defer allocator.free(inner_s);
            break :blk std.fmt.allocPrint(allocator, "(Error | {s})", .{inner_s});
        },
        .null_union => |inner| blk: {
            const inner_s = try formatType(allocator, inner.*);
            defer allocator.free(inner_s);
            break :blk std.fmt.allocPrint(allocator, "(null | {s})", .{inner_s});
        },
        .generic => |g| allocator.dupe(u8, g.name),
        .func_ptr => |f| blk: {
            const ret_s = try formatType(allocator, f.return_type.*);
            defer allocator.free(ret_s);
            break :blk std.fmt.allocPrint(allocator, "func(...) {s}", .{ret_s});
        },
        .ptr => |p| allocator.dupe(u8, p.kind),
        .inferred => allocator.dupe(u8, "inferred"),
        .unknown => allocator.dupe(u8, "unknown"),
        .tuple, .union_type => allocator.dupe(u8, t.name()),
    };
}

fn formatFuncSig(allocator: std.mem.Allocator, sig: declarations.FuncSig) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "func ");
    try buf.appendSlice(allocator, sig.name);
    try buf.append(allocator, '(');

    for (sig.params, 0..) |p, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, p.name);
        try buf.appendSlice(allocator, ": ");
        const ts = try formatType(allocator, p.type_);
        defer allocator.free(ts);
        try buf.appendSlice(allocator, ts);
    }

    try buf.appendSlice(allocator, ") ");
    const ret_s = try formatType(allocator, sig.return_type);
    defer allocator.free(ret_s);
    try buf.appendSlice(allocator, ret_s);

    return allocator.dupe(u8, buf.items);
}

fn formatStructSig(allocator: std.mem.Allocator, sig: declarations.StructSig) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "struct ");
    try buf.appendSlice(allocator, sig.name);
    try buf.appendSlice(allocator, " { ");

    for (sig.fields, 0..) |f, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, f.name);
        try buf.appendSlice(allocator, ": ");
        const ts = try formatType(allocator, f.type_);
        defer allocator.free(ts);
        try buf.appendSlice(allocator, ts);
    }

    try buf.appendSlice(allocator, " }");
    return allocator.dupe(u8, buf.items);
}

fn formatEnumSig(allocator: std.mem.Allocator, sig: declarations.EnumSig) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "enum ");
    try buf.appendSlice(allocator, sig.name);
    try buf.appendSlice(allocator, " { ");

    for (sig.variants, 0..) |v, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, v);
    }

    try buf.appendSlice(allocator, " }");
    return allocator.dupe(u8, buf.items);
}

// ============================================================
// ANALYSIS — run passes 1–9, collect diagnostics + symbols
// ============================================================

fn runAnalysis(allocator: std.mem.Allocator, project_root: []const u8) !AnalysisResult {
    var empty = AnalysisResult{ .diagnostics = &.{}, .symbols = &.{} };

    const saved_cwd = std.fs.cwd();
    var proj_dir = std.fs.cwd().openDir(project_root, .{}) catch return empty;
    defer proj_dir.close();
    proj_dir.setAsCwd() catch return empty;
    defer saved_cwd.setAsCwd() catch {};

    // Ensure std files exist
    std.fs.cwd().makePath(cache.CACHE_DIR ++ "/std") catch {};

    var reporter = errors.Reporter.init(allocator, .debug);
    defer reporter.deinit();

    var mod_resolver = module.Resolver.init(allocator, &reporter);
    defer mod_resolver.deinit();

    std.fs.cwd().access("src", .{}) catch return empty;
    mod_resolver.scanDirectory("src") catch {
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    };
    if (reporter.hasErrors()) {
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    }

    mod_resolver.checkCircularImports() catch {};
    if (reporter.hasErrors()) {
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    }

    mod_resolver.parseModules(allocator) catch {};
    if (reporter.hasErrors()) {
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    }

    // Second parse pass for std imports
    {
        var has_unparsed = false;
        var it = mod_resolver.modules.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.ast == null) { has_unparsed = true; break; }
        }
        if (has_unparsed) {
            mod_resolver.parseModules(allocator) catch {};
            if (reporter.hasErrors()) {
                empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
                return empty;
            }
        }
    }

    mod_resolver.scanAndParseDeps(allocator, "src") catch {};
    if (reporter.hasErrors()) {
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    }

    mod_resolver.validateImports(&reporter) catch {};
    if (reporter.hasErrors()) {
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    }

    const order = mod_resolver.topologicalOrder(allocator) catch {
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    };
    defer allocator.free(order);

    // Collect symbols from all modules
    var all_symbols: std.ArrayListUnmanaged(SymbolInfo) = .{};

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

        // Extract symbols from DeclTable + AST locations
        extractSymbols(allocator, &all_symbols, &dc.table, ast, locs_ptr, source_file, project_root, mod_name) catch {};

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

    const diags = toDiagnostics(allocator, &reporter, project_root) catch
        @as([]Diagnostic, &.{});
    const symbols = if (all_symbols.items.len > 0)
        (allocator.dupe(SymbolInfo, all_symbols.items) catch @as([]SymbolInfo, &.{}))
    else
        @as([]SymbolInfo, &.{});

    return .{ .diagnostics = diags, .symbols = symbols };
}

/// Walk AST top-level nodes and match them against DeclTable to build SymbolInfo entries.
fn extractSymbols(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayListUnmanaged(SymbolInfo),
    table: *declarations.DeclTable,
    ast: *parser.Node,
    locs: ?*const parser.LocMap,
    source_file: []const u8,
    project_root: []const u8,
    mod_name: []const u8,
) !void {
    if (ast.* != .program) return;

    for (ast.program.top_level) |node| {
        switch (node.*) {
            .func_decl => |f| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const detail = if (table.funcs.get(f.name)) |sig|
                    formatFuncSig(allocator, sig) catch try allocator.dupe(u8, "func")
                else
                    try allocator.dupe(u8, "func");
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, f.name),
                    .detail = detail,
                    .kind = .function,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = "",
                    .uri = try makeUri(allocator, source_file, project_root),
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
            },
            .struct_decl => |s| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const detail = if (table.structs.get(s.name)) |sig|
                    formatStructSig(allocator, sig) catch try allocator.dupe(u8, "struct")
                else
                    try allocator.dupe(u8, "struct");
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, s.name),
                    .detail = detail,
                    .kind = .struct_,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = "",
                    .uri = try makeUri(allocator, source_file, project_root),
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
                // Add struct fields as child symbols
                for (s.members) |member| {
                    if (member.* == .field_decl) {
                        const floc = nodeLocInfo(locs, member) orelse continue;
                        const fd = member.field_decl;
                        const ftype = if (table.structs.get(s.name)) |sig| blk: {
                            for (sig.fields) |field| {
                                if (std.mem.eql(u8, field.name, fd.name)) {
                                    break :blk formatType(allocator, field.type_) catch try allocator.dupe(u8, "field");
                                }
                            }
                            break :blk try allocator.dupe(u8, "field");
                        } else try allocator.dupe(u8, "field");
                        try symbols.append(allocator, .{
                            .name = try allocator.dupe(u8, fd.name),
                            .detail = ftype,
                            .kind = .field,
                            .module = try allocator.dupe(u8, mod_name),
                            .parent = try allocator.dupe(u8, s.name),
                            .uri = try makeUri(allocator, source_file, project_root),
                            .line = if (floc.line > 0) floc.line - 1 else 0,
                            .col = if (floc.col > 0) floc.col - 1 else 0,
                        });
                    }
                }
            },
            .enum_decl => |e| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const detail = if (table.enums.get(e.name)) |sig|
                    formatEnumSig(allocator, sig) catch try allocator.dupe(u8, "enum")
                else
                    try allocator.dupe(u8, "enum");
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, e.name),
                    .detail = detail,
                    .kind = .enum_,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = "",
                    .uri = try makeUri(allocator, source_file, project_root),
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
                // Add enum variants
                for (e.members) |member| {
                    const mloc = nodeLocInfo(locs, member) orelse continue;
                    const vname = switch (member.*) {
                        .identifier => |id| id,
                        else => continue,
                    };
                    try symbols.append(allocator, .{
                        .name = try allocator.dupe(u8, vname),
                        .detail = try allocator.dupe(u8, e.name),
                        .kind = .enum_member,
                        .module = try allocator.dupe(u8, mod_name),
                        .parent = try allocator.dupe(u8, e.name),
                        .uri = try makeUri(allocator, source_file, project_root),
                        .line = if (mloc.line > 0) mloc.line - 1 else 0,
                        .col = if (mloc.col > 0) mloc.col - 1 else 0,
                    });
                }
            },
            .var_decl => |v| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const detail = if (table.vars.get(v.name)) |sig| blk: {
                    if (sig.type_) |t| break :blk formatType(allocator, t) catch try allocator.dupe(u8, "var");
                    break :blk try allocator.dupe(u8, "var");
                } else try allocator.dupe(u8, "var");
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, v.name),
                    .detail = detail,
                    .kind = .variable,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = "",
                    .uri = try makeUri(allocator, source_file, project_root),
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
            },
            .const_decl => |cd| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const detail = if (table.vars.get(cd.name)) |sig| blk: {
                    if (sig.type_) |t| break :blk formatType(allocator, t) catch try allocator.dupe(u8, "const");
                    break :blk try allocator.dupe(u8, "const");
                } else try allocator.dupe(u8, "const");
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, cd.name),
                    .detail = detail,
                    .kind = .constant,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = "",
                    .uri = try makeUri(allocator, source_file, project_root),
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
            },
            else => {},
        }
    }
}

fn nodeLocInfo(locs: ?*const parser.LocMap, node: *parser.Node) ?errors.SourceLoc {
    const l = locs orelse return null;
    return l.get(node);
}

fn makeUri(allocator: std.mem.Allocator, source_file: []const u8, project_root: []const u8) ![]u8 {
    if (source_file.len == 0) return allocator.dupe(u8, "file:///unknown");
    const full_path = if (!std.fs.path.isAbsolute(source_file))
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ project_root, source_file })
    else
        try allocator.dupe(u8, source_file);
    defer if (!std.fs.path.isAbsolute(source_file)) allocator.free(full_path);
    return pathToUri(allocator, full_path);
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
// PHASE 2 RESPONSE BUILDERS
// ============================================================

fn buildHoverResponse(allocator: std.mem.Allocator, id: std.json.Value, detail: []const u8) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator, ",\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```kodr\\n");
    try appendJsonString(&buf, allocator, detail);
    try buf.appendSlice(allocator, "\\n```\"}}}");

    return allocator.dupe(u8, buf.items);
}

fn buildDefinitionResponse(allocator: std.mem.Allocator, id: std.json.Value, uri: []const u8, line: usize, col: usize) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator, ",\"result\":{\"uri\":\"");
    try appendJsonString(&buf, allocator, uri);
    try buf.appendSlice(allocator, "\",\"range\":{\"start\":{\"line\":");
    try appendInt(&buf, allocator, line);
    try buf.appendSlice(allocator, ",\"character\":");
    try appendInt(&buf, allocator, col);
    try buf.appendSlice(allocator, "},\"end\":{\"line\":");
    try appendInt(&buf, allocator, line);
    try buf.appendSlice(allocator, ",\"character\":");
    try appendInt(&buf, allocator, col);
    try buf.appendSlice(allocator, "}}}}");

    return allocator.dupe(u8, buf.items);
}

fn buildDocumentSymbolsResponse(allocator: std.mem.Allocator, id: std.json.Value, symbols: []const SymbolInfo, uri: []const u8) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator, ",\"result\":[");

    var first = true;
    for (symbols) |s| {
        if (!std.mem.eql(u8, s.uri, uri)) continue;
        if (!first) try buf.append(allocator, ',');
        first = false;

        try buf.appendSlice(allocator, "{\"name\":\"");
        try appendJsonString(&buf, allocator, s.name);
        try buf.appendSlice(allocator, "\",\"kind\":");
        try appendInt(&buf, allocator, @intFromEnum(s.kind));
        try buf.appendSlice(allocator, ",\"location\":{\"uri\":\"");
        try appendJsonString(&buf, allocator, s.uri);
        try buf.appendSlice(allocator, "\",\"range\":{\"start\":{\"line\":");
        try appendInt(&buf, allocator, s.line);
        try buf.appendSlice(allocator, ",\"character\":");
        try appendInt(&buf, allocator, s.col);
        try buf.appendSlice(allocator, "},\"end\":{\"line\":");
        try appendInt(&buf, allocator, s.line);
        try buf.appendSlice(allocator, ",\"character\":");
        try appendInt(&buf, allocator, s.col);
        try buf.appendSlice(allocator, "}}}}");
    }

    try buf.appendSlice(allocator, "]}");
    return allocator.dupe(u8, buf.items);
}

// ============================================================
// WORD-AT-POSITION — extract the identifier under cursor from source
// ============================================================

fn getWordAtPosition(source: []const u8, line_0: usize, col_0: usize) ?[]const u8 {
    // Find the target line
    var current_line: usize = 0;
    var line_start: usize = 0;
    for (source, 0..) |c, i| {
        if (current_line == line_0) {
            line_start = i;
            break;
        }
        if (c == '\n') current_line += 1;
    } else {
        // Reached end without finding the line
        if (current_line == line_0) line_start = source.len else return null;
    }

    // Find line end
    var line_end = line_start;
    while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}

    const line_text = source[line_start..line_end];
    if (col_0 >= line_text.len) return null;

    // Expand from cursor position to find word boundaries
    var start = col_0;
    while (start > 0 and isIdentChar(line_text[start - 1])) : (start -= 1) {}
    var end = col_0;
    while (end < line_text.len and isIdentChar(line_text[end])) : (end += 1) {}

    if (start == end) return null;
    return line_text[start..end];
}

fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

/// Get the object name before the dot if the word is part of a `obj.member` expression.
/// Returns null if there's no dot prefix.
fn getDotContext(source: []const u8, line_0: usize, col_0: usize) ?[]const u8 {
    var current_line: usize = 0;
    var line_start: usize = 0;
    for (source, 0..) |c, i| {
        if (current_line == line_0) {
            line_start = i;
            break;
        }
        if (c == '\n') current_line += 1;
    } else {
        if (current_line == line_0) line_start = source.len else return null;
    }

    var line_end = line_start;
    while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}

    const line_text = source[line_start..line_end];
    if (col_0 >= line_text.len) return null;

    // Find start of current word
    var start = col_0;
    while (start > 0 and isIdentChar(line_text[start - 1])) : (start -= 1) {}

    // Check if there's a dot before the word
    if (start == 0 or line_text[start - 1] != '.') return null;

    // Find the object name before the dot
    const obj_end = start - 1;
    var obj_start = obj_end;
    while (obj_start > 0 and isIdentChar(line_text[obj_start - 1])) : (obj_start -= 1) {}

    if (obj_start == obj_end) return null;
    return line_text[obj_start..obj_end];
}

// ============================================================
// SYMBOL LOOKUP — find symbol by name in cached symbols
// ============================================================

fn findSymbolByName(symbols: []const SymbolInfo, name: []const u8) ?SymbolInfo {
    // Prefer top-level symbols (not fields/enum members)
    for (symbols) |s| {
        if (std.mem.eql(u8, s.name, name) and s.parent.len == 0) return s;
    }
    // Fallback: any symbol with this name
    for (symbols) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

/// Find a symbol by name within a specific module or parent context
fn findSymbolInContext(symbols: []const SymbolInfo, name: []const u8, context: []const u8) ?SymbolInfo {
    // Check if it's a module function (e.g. console.println → module=console, name=println)
    for (symbols) |s| {
        if (std.mem.eql(u8, s.name, name) and std.mem.eql(u8, s.module, context)) return s;
    }
    // Check if it's a struct field (e.g. MyStruct.name → parent=MyStruct, name=name)
    for (symbols) |s| {
        if (std.mem.eql(u8, s.name, name) and std.mem.eql(u8, s.parent, context)) return s;
    }
    return null;
}

/// Check if a name is a known module in the symbol cache
fn isModuleName(symbols: []const SymbolInfo, name: []const u8) bool {
    for (symbols) |s| {
        if (std.mem.eql(u8, s.module, name)) return true;
    }
    return false;
}

/// Look up a builtin type or primitive by name, return hover detail
fn builtinDetail(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // Primitive types
    const primitives = [_][]const u8{
        "String", "bool", "void",
        "i8", "i16", "i32", "i64", "i128",
        "u8", "u16", "u32", "u64", "u128",
        "isize", "usize",
        "f16", "f32", "f64", "f128", "bf16",
    };
    for (primitives) |p| {
        if (std.mem.eql(u8, name, p)) {
            return std.fmt.allocPrint(allocator, "(primitive type) {s}", .{p}) catch null;
        }
    }
    // Builtin types
    for (builtins.BUILTIN_TYPES) |bt| {
        if (std.mem.eql(u8, name, bt)) {
            return std.fmt.allocPrint(allocator, "(builtin type) {s}", .{bt}) catch null;
        }
    }
    // Keywords that might be hovered
    if (std.mem.eql(u8, name, "null")) return allocator.dupe(u8, "(keyword) null") catch null;
    if (std.mem.eql(u8, name, "true") or std.mem.eql(u8, name, "false"))
        return allocator.dupe(u8, "(keyword) bool literal") catch null;
    return null;
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

    // Format into a stack buffer, then append to log file
    var log_buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&log_buf, "[kodr-lsp] " ++ fmt ++ "\n", args) catch return;
    const log_path = "/tmp/kodr-lsp.log";
    const file = std.fs.cwd().openFile(log_path, .{ .mode = .write_only }) catch
        std.fs.cwd().createFile(log_path, .{}) catch return;
    defer file.close();
    file.seekFromEnd(0) catch {};
    file.writeAll(msg) catch {};
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

    // Cached symbols from last analysis
    var cached_symbols: []SymbolInfo = &.{};
    defer freeSymbols(allocator, cached_symbols);

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
            if (project_root) |r| {
                cached_symbols = try runAndPublish(allocator, stdout, r, &open_docs, cached_symbols);
            }

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
                        if (project_root) |r| {
                            cached_symbols = try runAndPublish(allocator, stdout, r, &open_docs, cached_symbols);
                        }
                    }
                }
            }

        } else if (std.mem.eql(u8, method, "textDocument/didSave")) {
            if (!initialized) continue;
            log("didSave", .{});
            if (project_root) |r| {
                cached_symbols = try runAndPublish(allocator, stdout, r, &open_docs, cached_symbols);
            }

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

        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            if (!initialized) continue;
            const resp = handleHover(allocator, root, id, cached_symbols) catch |err| {
                log("hover error: {}", .{err});
                try writeMessage(stdout, try buildEmptyResponse(allocator, id));
                continue;
            };
            defer allocator.free(resp);
            try writeMessage(stdout, resp);

        } else if (std.mem.eql(u8, method, "textDocument/definition")) {
            if (!initialized) continue;
            const resp = handleDefinition(allocator, root, id, cached_symbols) catch |err| {
                log("definition error: {}", .{err});
                try writeMessage(stdout, try buildEmptyResponse(allocator, id));
                continue;
            };
            defer allocator.free(resp);
            try writeMessage(stdout, resp);

        } else if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
            if (!initialized) continue;
            const resp = handleDocumentSymbols(allocator, root, id, cached_symbols) catch |err| {
                log("documentSymbol error: {}", .{err});
                try writeMessage(stdout, try buildEmptyResponse(allocator, id));
                continue;
            };
            defer allocator.free(resp);
            try writeMessage(stdout, resp);

        } else if (std.mem.eql(u8, method, "textDocument/completion")) {
            if (!initialized) continue;
            const resp = handleCompletion(allocator, root, id, cached_symbols) catch |err| {
                log("completion error: {}", .{err});
                try writeMessage(stdout, try buildEmptyResponse(allocator, id));
                continue;
            };
            defer allocator.free(resp);
            try writeMessage(stdout, resp);

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

/// Run analysis, publish diagnostics, return new cached symbols.
fn runAndPublish(
    allocator: std.mem.Allocator,
    writer: *Io.Writer,
    project_root: []const u8,
    open_docs: *std.StringHashMap(void),
    old_symbols: []SymbolInfo,
) ![]SymbolInfo {
    const result = try runAnalysis(allocator, project_root);

    // Free old symbols
    freeSymbols(allocator, old_symbols);

    // Publish diagnostics
    defer {
        if (result.diagnostics.len > 0) {
            for (result.diagnostics) |d| {
                allocator.free(d.uri);
                allocator.free(d.message);
            }
            allocator.free(result.diagnostics);
        }
    }

    // Collect unique URIs that have diagnostics
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    for (result.diagnostics) |d| {
        if (!seen.contains(d.uri)) {
            try seen.put(d.uri, {});
            const msg = try buildDiagnosticsMsg(allocator, d.uri, result.diagnostics);
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

    log("cached {d} symbols", .{result.symbols.len});
    for (result.symbols) |s| {
        if (s.parent.len > 0) {
            log("  symbol: {s}.{s} (module={s})", .{ s.parent, s.name, s.module });
        } else {
            log("  symbol: {s} (module={s})", .{ s.name, s.module });
        }
    }
    return result.symbols;
}

// ============================================================
// PHASE 2 HANDLERS
// ============================================================

fn handleHover(allocator: std.mem.Allocator, root: std.json.Value, id: std.json.Value, symbols: []const SymbolInfo) ![]u8 {
    const params = jsonObj(root, "params") orelse return buildEmptyResponse(allocator, id);
    const td = jsonObj(params, "textDocument") orelse return buildEmptyResponse(allocator, id);
    const uri = jsonStr(td, "uri") orelse return buildEmptyResponse(allocator, id);
    const pos = jsonObj(params, "position") orelse return buildEmptyResponse(allocator, id);
    const line_0: usize = @intCast(jsonInt(pos, "line") orelse return buildEmptyResponse(allocator, id));
    const col_0: usize = @intCast(jsonInt(pos, "character") orelse return buildEmptyResponse(allocator, id));

    // Read the source file to find word at cursor
    const path = uriToPath(uri) orelse return buildEmptyResponse(allocator, id);
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        log("hover: failed to read {s}: {}", .{ path, err });
        return buildEmptyResponse(allocator, id);
    };
    defer allocator.free(source);

    const word = getWordAtPosition(source, line_0, col_0) orelse {
        log("hover: no word at {d}:{d}", .{ line_0, col_0 });
        return buildEmptyResponse(allocator, id);
    };
    // Check for dot context (e.g. hovering over "println" in "console.println")
    const dot_ctx = getDotContext(source, line_0, col_0);
    if (dot_ctx) |ctx| {
        log("hover: '{s}.{s}' at {d}:{d} ({d} symbols cached)", .{ ctx, word, line_0, col_0, symbols.len });
    } else {
        log("hover: '{s}' at {d}:{d} ({d} symbols cached)", .{ word, line_0, col_0, symbols.len });
    }

    // 1. Context-aware lookup (module.func or struct.field)
    if (dot_ctx) |ctx| {
        if (findSymbolInContext(symbols, word, ctx)) |sym| {
            return buildHoverResponse(allocator, id, sym.detail);
        }
    }

    // 2. Check project symbols by name
    if (findSymbolByName(symbols, word)) |sym| {
        return buildHoverResponse(allocator, id, sym.detail);
    }

    // 3. Check if hovering over a module name (only if no symbol matched)
    if (isModuleName(symbols, word)) {
        const detail = try std.fmt.allocPrint(allocator, "(module) {s}", .{word});
        defer allocator.free(detail);
        return buildHoverResponse(allocator, id, detail);
    }

    // 4. Check builtin/primitive types
    if (builtinDetail(allocator, word)) |detail| {
        defer allocator.free(detail);
        return buildHoverResponse(allocator, id, detail);
    }

    log("hover: no match for '{s}'", .{word});
    return buildEmptyResponse(allocator, id);
}

fn handleDefinition(allocator: std.mem.Allocator, root: std.json.Value, id: std.json.Value, symbols: []const SymbolInfo) ![]u8 {
    const params = jsonObj(root, "params") orelse return buildEmptyResponse(allocator, id);
    const td = jsonObj(params, "textDocument") orelse return buildEmptyResponse(allocator, id);
    const uri = jsonStr(td, "uri") orelse return buildEmptyResponse(allocator, id);
    const pos = jsonObj(params, "position") orelse return buildEmptyResponse(allocator, id);
    const line_0: usize = @intCast(jsonInt(pos, "line") orelse return buildEmptyResponse(allocator, id));
    const col_0: usize = @intCast(jsonInt(pos, "character") orelse return buildEmptyResponse(allocator, id));

    const path = uriToPath(uri) orelse return buildEmptyResponse(allocator, id);
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch
        return buildEmptyResponse(allocator, id);
    defer allocator.free(source);

    const word = getWordAtPosition(source, line_0, col_0) orelse return buildEmptyResponse(allocator, id);
    const dot_ctx = getDotContext(source, line_0, col_0);
    log("definition: '{s}' ({d} symbols)", .{ word, symbols.len });

    // Context-aware lookup first
    if (dot_ctx) |ctx| {
        if (findSymbolInContext(symbols, word, ctx)) |sym| {
            return buildDefinitionResponse(allocator, id, sym.uri, sym.line, sym.col);
        }
    }

    const sym = findSymbolByName(symbols, word) orelse return buildEmptyResponse(allocator, id);
    return buildDefinitionResponse(allocator, id, sym.uri, sym.line, sym.col);
}

fn handleDocumentSymbols(allocator: std.mem.Allocator, root: std.json.Value, id: std.json.Value, symbols: []const SymbolInfo) ![]u8 {
    const params = jsonObj(root, "params") orelse return buildEmptyResponse(allocator, id);
    const td = jsonObj(params, "textDocument") orelse return buildEmptyResponse(allocator, id);
    const uri = jsonStr(td, "uri") orelse return buildEmptyResponse(allocator, id);
    log("documentSymbol: {s}", .{uri});

    return buildDocumentSymbolsResponse(allocator, id, symbols, uri);
}

// ============================================================
// COMPLETION
// ============================================================

/// LSP CompletionItemKind values
const CompletionItemKind = enum(u8) {
    keyword = 14,
    function = 3,
    struct_ = 22,
    enum_ = 13,
    variable = 6,
    constant = 21,
    field = 5,
    enum_member = 20,
    type_ = 25, // for builtin/primitive types
};

fn handleCompletion(allocator: std.mem.Allocator, root: std.json.Value, id: std.json.Value, symbols: []const SymbolInfo) ![]u8 {
    const params = jsonObj(root, "params") orelse return buildEmptyResponse(allocator, id);
    const td = jsonObj(params, "textDocument") orelse return buildEmptyResponse(allocator, id);
    const uri = jsonStr(td, "uri") orelse return buildEmptyResponse(allocator, id);
    const pos = jsonObj(params, "position") orelse return buildEmptyResponse(allocator, id);
    const line_0: usize = @intCast(jsonInt(pos, "line") orelse return buildEmptyResponse(allocator, id));
    const col_0: usize = @intCast(jsonInt(pos, "character") orelse return buildEmptyResponse(allocator, id));

    // Read source to determine context
    const path = uriToPath(uri) orelse return buildEmptyResponse(allocator, id);
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch
        return buildEmptyResponse(allocator, id);
    defer allocator.free(source);

    // Get the text before cursor on this line to determine context
    const prefix = getLinePrefix(source, line_0, col_0);
    log("completion: prefix='{s}'", .{prefix});

    // Check if we're after a dot — offer struct fields or module functions
    if (getDotPrefix(prefix)) |obj_name| {
        log("completion: dot context, object='{s}'", .{obj_name});
        return buildDotCompletionResponse(allocator, id, symbols, obj_name);
    }

    // General completion: keywords + symbols + types
    return buildGeneralCompletionResponse(allocator, id, symbols);
}

fn getLinePrefix(source: []const u8, line_0: usize, col_0: usize) []const u8 {
    var current_line: usize = 0;
    var line_start: usize = 0;
    for (source, 0..) |c, i| {
        if (current_line == line_0) {
            line_start = i;
            break;
        }
        if (c == '\n') current_line += 1;
    } else {
        if (current_line == line_0) line_start = source.len else return "";
    }

    var line_end = line_start;
    while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}

    const line_text = source[line_start..line_end];
    if (col_0 > line_text.len) return line_text;
    return line_text[0..col_0];
}

/// If prefix ends with `identifier.`, return the identifier before the dot.
fn getDotPrefix(prefix: []const u8) ?[]const u8 {
    if (prefix.len == 0) return null;
    // Find the last dot
    var i = prefix.len;
    while (i > 0) : (i -= 1) {
        if (prefix[i - 1] == '.') {
            // Walk backwards from dot to find identifier start
            var j = i - 1;
            while (j > 0 and isIdentChar(prefix[j - 1])) : (j -= 1) {}
            if (j < i - 1) return prefix[j .. i - 1];
            return null;
        }
        if (!isIdentChar(prefix[i - 1])) return null;
    }
    return null;
}

fn buildDotCompletionResponse(allocator: std.mem.Allocator, id: std.json.Value, symbols: []const SymbolInfo, obj_name: []const u8) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator, ",\"result\":{\"isIncomplete\":false,\"items\":[");

    var first = true;

    for (symbols) |s| {
        // Struct fields: parent matches obj_name (e.g. MyStruct.name)
        if (s.parent.len > 0 and std.mem.eql(u8, s.parent, obj_name)) {
            if (!first) try buf.append(allocator, ',');
            first = false;
            const kind: CompletionItemKind = switch (s.kind) {
                .field => .field,
                .enum_member => .enum_member,
                else => .field,
            };
            try appendCompletionItem(&buf, allocator, s.name, s.detail, kind);
            continue;
        }
        // Module functions: module matches obj_name (e.g. console.println)
        if (std.mem.eql(u8, s.module, obj_name) and s.parent.len == 0) {
            if (!first) try buf.append(allocator, ',');
            first = false;
            const kind: CompletionItemKind = switch (s.kind) {
                .function => .function,
                .struct_ => .struct_,
                .enum_ => .enum_,
                .variable => .variable,
                .constant => .constant,
                else => .function,
            };
            try appendCompletionItem(&buf, allocator, s.name, s.detail, kind);
        }
    }

    try buf.appendSlice(allocator, "]}}");
    return allocator.dupe(u8, buf.items);
}

fn buildGeneralCompletionResponse(allocator: std.mem.Allocator, id: std.json.Value, symbols: []const SymbolInfo) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(&buf, allocator, id);
    try buf.appendSlice(allocator, ",\"result\":{\"isIncomplete\":false,\"items\":[");

    var first = true;

    // Keywords
    const keywords = [_][]const u8{
        "func", "var", "const", "if", "else", "for", "while", "return",
        "import", "pub", "match", "struct", "enum", "bitfield", "defer",
        "thread", "null", "void", "compt", "any", "module", "test",
        "and", "or", "not", "as", "break", "continue", "true", "false",
        "extern", "is",
    };
    for (keywords) |kw| {
        if (!first) try buf.append(allocator, ',');
        first = false;
        try appendCompletionItem(&buf, allocator, kw, "keyword", .keyword);
    }

    // Primitive types
    const primitives = [_][]const u8{
        "String", "bool", "i8", "i16", "i32", "i64", "i128",
        "u8", "u16", "u32", "u64", "u128", "isize", "usize",
        "f16", "f32", "f64", "f128", "bf16",
    };
    for (primitives) |pt| {
        if (!first) try buf.append(allocator, ',');
        first = false;
        try appendCompletionItem(&buf, allocator, pt, "primitive type", .type_);
    }

    // Builtin types
    for (builtins.BUILTIN_TYPES) |bt| {
        if (!first) try buf.append(allocator, ',');
        first = false;
        try appendCompletionItem(&buf, allocator, bt, "builtin type", .type_);
    }

    // Project symbols
    for (symbols) |s| {
        if (!first) try buf.append(allocator, ',');
        first = false;
        const kind: CompletionItemKind = switch (s.kind) {
            .function => .function,
            .struct_ => .struct_,
            .enum_ => .enum_,
            .variable => .variable,
            .constant => .constant,
            .field => .field,
            .enum_member => .enum_member,
        };
        try appendCompletionItem(&buf, allocator, s.name, s.detail, kind);
    }

    try buf.appendSlice(allocator, "]}}");
    return allocator.dupe(u8, buf.items);
}

fn appendCompletionItem(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, label: []const u8, detail: []const u8, kind: CompletionItemKind) !void {
    try buf.appendSlice(allocator, "{\"label\":\"");
    try appendJsonString(buf, allocator, label);
    try buf.appendSlice(allocator, "\",\"kind\":");
    try appendInt(buf, allocator, @intFromEnum(kind));
    try buf.appendSlice(allocator, ",\"detail\":\"");
    try appendJsonString(buf, allocator, detail);
    try buf.appendSlice(allocator, "\"}");
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

test "getWordAtPosition finds identifier" {
    const source = "func main() void {\n    console.println(x)\n}";
    const word = getWordAtPosition(source, 0, 5);
    try std.testing.expectEqualStrings("main", word.?);
}

test "getWordAtPosition finds word on second line" {
    const source = "func main() void {\n    console.println(x)\n}";
    const word = getWordAtPosition(source, 1, 6);
    try std.testing.expectEqualStrings("console", word.?);
}

test "isIdentChar recognizes valid chars" {
    try std.testing.expect(isIdentChar('a'));
    try std.testing.expect(isIdentChar('Z'));
    try std.testing.expect(isIdentChar('_'));
    try std.testing.expect(isIdentChar('5'));
    try std.testing.expect(!isIdentChar('.'));
    try std.testing.expect(!isIdentChar(' '));
}
