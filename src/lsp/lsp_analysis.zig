// lsp_analysis.zig — Compiler analysis and type formatting

const std = @import("std");
const lsp_types = @import("lsp_types.zig");
const lsp_utils = @import("lsp_utils.zig");
const parser = @import("../parser.zig");
const module = @import("../module.zig");
const declarations = @import("../declarations.zig");
const resolver = @import("../resolver.zig");
const ownership = @import("../ownership.zig");
const borrow = @import("../borrow.zig");
const propagation = @import("../propagation.zig");
const sema = @import("../sema.zig");
const errors = @import("../errors.zig");
const cache = @import("../cache.zig");
const ast_conv = @import("../ast_conv.zig");
const pipeline_passes = @import("../pipeline_passes.zig");
const pipeline_context = @import("../pipeline_context.zig");
const types = @import("../types.zig");

const SymbolInfo = lsp_types.SymbolInfo;
const SymbolKind = lsp_types.SymbolKind;
const AnalysisResult = lsp_types.AnalysisResult;
const Diagnostic = lsp_types.Diagnostic;

const lspLog = lsp_utils.lspLog;
const pathToUri = lsp_utils.pathToUri;

// ============================================================
// TYPE FORMATTING — for hover display
// ============================================================

pub fn formatType(allocator: std.mem.Allocator, t: types.ResolvedType) anyerror![]u8 {
    return switch (t) {
        .primitive => |p| allocator.dupe(u8, p.toName()),
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
        .generic => |g| allocator.dupe(u8, g.name),
        .func_ptr => |f| blk: {
            const ret_s = try formatType(allocator, f.return_type.*);
            defer allocator.free(ret_s);
            break :blk std.fmt.allocPrint(allocator, "func(...) {s}", .{ret_s});
        },
        .ptr => |p| try allocator.dupe(u8, if (p.kind == .mut_ref) "mut&" else "const&"),
        .inferred => allocator.dupe(u8, "inferred"),
        .unknown => allocator.dupe(u8, "unknown"),
        .type_param => |tp| allocator.dupe(u8, tp.name),
        .tuple, .union_type => allocator.dupe(u8, t.name()),
    };
}

pub fn formatFuncSig(allocator: std.mem.Allocator, sig: declarations.FuncSig) ![]u8 {
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

pub fn formatStructSig(allocator: std.mem.Allocator, sig: declarations.StructSig) ![]u8 {
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

pub fn formatEnumSig(allocator: std.mem.Allocator, sig: declarations.EnumSig) ![]u8 {
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
// ANALYSIS — run passes 1-9, collect diagnostics + symbols
// ============================================================

pub fn runAnalysis(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    stop_after: pipeline_passes.Pass,
) !AnalysisResult {
    var empty = AnalysisResult{ .diagnostics = &.{}, .symbols = &.{} };

    const saved_cwd = std.fs.cwd();
    var proj_dir = std.fs.cwd().openDir(project_root, .{}) catch {
        lspLog("analysis: failed to open project dir '{s}'", .{project_root});
        return empty;
    };
    defer proj_dir.close();
    proj_dir.setAsCwd() catch {
        lspLog("analysis: failed to setAsCwd", .{});
        return empty;
    };
    defer saved_cwd.setAsCwd() catch {};

    // Scratch arena for all analysis pass objects -- bulk-freed on function exit.
    // Results (diagnostics, symbols) are allocated with the long-lived `allocator`
    // so they survive the arena deinit and can be freed by freeDiagnostics/freeSymbols.
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();

    // Ensure std files exist
    std.fs.cwd().makePath(cache.CACHE_DIR ++ "/std") catch {};

    var reporter = errors.Reporter.init(a, .debug);
    var mod_resolver = module.Resolver.init(a, &reporter);

    std.fs.cwd().access("src", .{}) catch {
        lspLog("analysis: no 'src' directory in '{s}'", .{project_root});
        return empty;
    };
    mod_resolver.scanDirectory("src") catch {
        lspLog("analysis: scanDirectory failed", .{});
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    };
    if (reporter.hasErrors()) {
        lspLog("analysis: errors after scan", .{});
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    }

    mod_resolver.parseModules(a) catch {};
    if (reporter.hasErrors()) {
        lspLog("analysis: parse errors (continuing with partial symbols)", .{});
    }

    // Validate imports and get compilation order
    const order = mod_resolver.validateAndOrder(a) catch {
        lspLog("analysis: validation failed", .{});
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    } orelse {
        lspLog("analysis: validation errors", .{});
        empty.diagnostics = toDiagnostics(allocator, &reporter, project_root) catch &.{};
        return empty;
    };
    // order is arena-allocated -- freed automatically by scratch.deinit()

    var all_symbols: std.ArrayListUnmanaged(SymbolInfo) = .{};
    lspLog("analysis: processing {d} modules (stop_after={})", .{ order.len, stop_after });

    // Cross-module decl accumulator for pass 5 type resolution.
    var all_module_decls = std.StringHashMap(*declarations.DeclTable).init(a);
    var cross_module_index: declarations.CrossModuleIndex = .{};

    var modules: std.ArrayList(pipeline_context.ModuleCompile) = .{};
    try modules.ensureTotalCapacity(a, order.len);
    defer {
        var i: usize = modules.items.len;
        while (i > 0) : (i -= 1) modules.items[i - 1].deinit();
        modules.deinit(a);
    }

    for (order) |mod_name| {
        const mod_ptr = mod_resolver.modules.getPtr(mod_name) orelse continue;
        const ast = mod_ptr.ast orelse continue;
        const locs_ptr: ?*const parser.LocMap = if (mod_ptr.locs) |*l| l else null;
        const file_offsets = mod_ptr.file_offsets;
        const source_file: []const u8 = if (mod_ptr.files.len > 0) mod_ptr.files[0] else "";
        const diag_count_before = reporter.diagnostics.items.len;

        try modules.append(a, undefined);
        const mc = &modules.items[modules.items.len - 1];
        try mc.init(a, &reporter, mod_name, mod_ptr);
        mc.decl_collector.locs = locs_ptr;
        mc.decl_collector.file_offsets = file_offsets;
        const ma = mc.bodyAllocator();

        // Pass 4: Declaration collection (always runs)
        var conv = ast_conv.ConvContext.init(ma);
        defer conv.deinit();
        const ast_root = ast_conv.convertNode(&conv, ast) catch continue;
        mc.decl_collector.collect(&conv.store, ast_root, &conv.reverse_map) catch {};
        try all_module_decls.put(mod_name, &mc.decl_collector.table);

        // Incrementally populate the cross-module reverse index.
        {
            var sym_it = mc.decl_collector.table.symbols.iterator();
            while (sym_it.next()) |s_entry| {
                const name = s_entry.key_ptr.*;
                const sym = s_entry.value_ptr.*;
                if (!sym.isPub()) continue;
                if (cross_module_index.contains(name)) continue;
                cross_module_index.put(allocator, name, .{
                    .module_name = mod_name,
                    .decls_ptr = &mc.decl_collector.table,
                }) catch {};
            }
        }

        extractSymbols(allocator, &all_symbols, &mc.decl_collector.table, ast, locs_ptr, source_file, project_root, mod_name) catch {};

        if (!stop_after.atLeast(.type_resolve)) continue;

        var new_err_count: usize = 0;
        for (reporter.diagnostics.items[diag_count_before..]) |d| {
            if (d.severity == .err) new_err_count += 1;
        }
        if (new_err_count > 0) continue;

        // Pass 5: Type resolution
        var sema_ctx = sema.SemanticContext{
            .allocator = ma,
            .reporter = &reporter,
            .decls = &mc.decl_collector.table,
            .is_zig_module = mc.mod_ptr.is_zig_module,
            .locs = locs_ptr,
            .file_offsets = file_offsets,
            .all_decls = &all_module_decls,
            .cross_module_index = &cross_module_index,
            .ast = &conv.store,
            .reverse_map = &conv.reverse_map,
        };
        var tr = resolver.TypeResolver.init(&sema_ctx);
        defer tr.deinit();
        tr.resolve(&conv.store, ast_root) catch {};
        sema_ctx.type_map = &tr.type_map;

        if (!stop_after.atLeast(.ownership)) continue;

        new_err_count = 0;
        for (reporter.diagnostics.items[diag_count_before..]) |d| {
            if (d.severity == .err) new_err_count += 1;
        }
        if (new_err_count > 0) continue;

        // Pass 6: Ownership analysis
        var oc = ownership.OwnershipChecker.init(ma, &sema_ctx);
        oc.check(ast) catch {};

        if (!stop_after.atLeast(.borrow)) continue;

        new_err_count = 0;
        for (reporter.diagnostics.items[diag_count_before..]) |d| {
            if (d.severity == .err) new_err_count += 1;
        }
        if (new_err_count > 0) continue;

        // Pass 7: Borrow checking
        var bc = borrow.BorrowChecker.init(ma, &sema_ctx);
        defer bc.deinit();
        bc.check(ast) catch {};

        if (!stop_after.atLeast(.propagation)) continue;

        new_err_count = 0;
        for (reporter.diagnostics.items[diag_count_before..]) |d| {
            if (d.severity == .err) new_err_count += 1;
        }
        if (new_err_count > 0) continue;

        // Pass 8: Error propagation
        var prop_checker = propagation.PropagationChecker.init(ma, &sema_ctx);
        prop_checker.check(&conv.store, ast_root) catch {};
    }

    const diags = if (stop_after.atLeast(.type_resolve))
        toDiagnostics(allocator, &reporter, project_root) catch @as([]Diagnostic, &.{})
    else
        @as([]Diagnostic, &.{});

    const symbols = if (all_symbols.items.len > 0) blk: {
        const duped = allocator.dupe(SymbolInfo, all_symbols.items) catch @as([]SymbolInfo, &.{});
        all_symbols.deinit(allocator);
        break :blk duped;
    } else @as([]SymbolInfo, &.{});

    return .{ .diagnostics = diags, .symbols = symbols };
}

/// Walk AST top-level nodes and match them against DeclTable to build SymbolInfo entries.
pub fn extractSymbols(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayListUnmanaged(SymbolInfo),
    table: *declarations.DeclTable,
    ast: *parser.Node,
    locs: ?*const parser.LocMap,
    source_file: []const u8,
    project_root: []const u8,
    mod_name: []const u8,
) anyerror!void {
    if (ast.* != .program) return;

    for (ast.program.top_level) |node| {
        switch (node.*) {
            .func_decl => |f| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const func_sig: ?declarations.FuncSig = if (table.symbols.get(f.name)) |sym| switch (sym) {
                    .func => |s| s,
                    else => null,
                } else null;
                const detail = if (func_sig) |sig|
                    formatFuncSig(allocator, sig) catch try allocator.dupe(u8, "func")
                else
                    try allocator.dupe(u8, "func");
                const func_uri = try makeUri(allocator, source_file, project_root);
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, f.name),
                    .detail = detail,
                    .kind = .function,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = "",
                    .uri = func_uri,
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
                // Extract function parameters as symbols
                if (func_sig) |sig| {
                    for (f.params, 0..) |param_node, pi| {
                        const ploc = nodeLocInfo(locs, param_node) orelse continue;
                        const ptype = if (pi < sig.params.len)
                            formatType(allocator, sig.params[pi].type_) catch try allocator.dupe(u8, "param")
                        else
                            try allocator.dupe(u8, "param");
                        try symbols.append(allocator, .{
                            .name = try allocator.dupe(u8, sig.params[pi].name),
                            .detail = ptype,
                            .kind = .variable,
                            .module = try allocator.dupe(u8, mod_name),
                            .parent = try allocator.dupe(u8, f.name),
                            .uri = try allocator.dupe(u8, func_uri),
                            .line = if (ploc.line > 0) ploc.line - 1 else 0,
                            .col = if (ploc.col > 0) ploc.col - 1 else 0,
                        });
                    }
                }
                // Extract local variables from function body
                if (f.body.* == .block) {
                    extractLocals(allocator, symbols, f.body.block.statements, locs, func_uri, mod_name, f.name) catch {};
                }
            },
            .struct_decl => |s| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const struct_sig: ?declarations.StructSig = if (table.symbols.get(s.name)) |sym| switch (sym) {
                    .@"struct" => |ss| ss,
                    else => null,
                } else null;
                const detail = if (struct_sig) |sig|
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
                        const ftype = if (struct_sig) |sig| blk: {
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
                const enum_sig: ?declarations.EnumSig = if (table.symbols.get(e.name)) |sym| switch (sym) {
                    .@"enum" => |es| es,
                    else => null,
                } else null;
                const detail = if (enum_sig) |sig|
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
            .handle_decl => |h| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, h.name),
                    .detail = try allocator.dupe(u8, "handle"),
                    .kind = .struct_,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = "",
                    .uri = try makeUri(allocator, source_file, project_root),
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
            },
            .var_decl => |v| {
                const loc = nodeLocInfo(locs, node) orelse continue;
                const sym_kind: SymbolKind = if (v.mutability == .constant) .constant else .variable;
                const default_label = if (v.mutability == .constant) "const" else "var";
                const var_sig: ?declarations.VarSig = if (table.symbols.get(v.name)) |sym| switch (sym) {
                    .@"var" => |vs| vs,
                    else => null,
                } else null;
                const detail = if (var_sig) |sig| blk: {
                    if (sig.type_) |t| break :blk formatType(allocator, t) catch try allocator.dupe(u8, default_label);
                    break :blk try allocator.dupe(u8, default_label);
                } else try allocator.dupe(u8, default_label);
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, v.name),
                    .detail = detail,
                    .kind = sym_kind,
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

/// Walk statements to extract local var/const declarations.
fn extractLocals(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayListUnmanaged(SymbolInfo),
    statements: []*parser.Node,
    locs: ?*const parser.LocMap,
    uri: []const u8,
    mod_name: []const u8,
    func_name: []const u8,
) anyerror!void {
    for (statements) |stmt| {
        switch (stmt.*) {
            .var_decl => |v| {
                const loc = nodeLocInfo(locs, stmt) orelse continue;
                const sym_kind: SymbolKind = if (v.mutability == .constant) .constant else .variable;
                const default_label = if (v.mutability == .constant) "const" else "var";
                const detail = if (v.type_annotation) |ta|
                    nodeTypeStr(ta)
                else
                    default_label;
                try symbols.append(allocator, .{
                    .name = try allocator.dupe(u8, v.name),
                    .detail = try allocator.dupe(u8, detail),
                    .kind = sym_kind,
                    .module = try allocator.dupe(u8, mod_name),
                    .parent = try allocator.dupe(u8, func_name),
                    .uri = try allocator.dupe(u8, uri),
                    .line = if (loc.line > 0) loc.line - 1 else 0,
                    .col = if (loc.col > 0) loc.col - 1 else 0,
                });
            },
            // Recurse into nested blocks
            .block => |b| try extractLocals(allocator, symbols, b.statements, locs, uri, mod_name, func_name),
            .if_stmt => |ifs| {
                if (ifs.then_block.* == .block)
                    try extractLocals(allocator, symbols, ifs.then_block.block.statements, locs, uri, mod_name, func_name);
                if (ifs.else_block) |eb| {
                    if (eb.* == .block)
                        try extractLocals(allocator, symbols, eb.block.statements, locs, uri, mod_name, func_name);
                }
            },
            .for_stmt => |fs| {
                if (fs.body.* == .block)
                    try extractLocals(allocator, symbols, fs.body.block.statements, locs, uri, mod_name, func_name);
            },
            .while_stmt => |ws| {
                if (ws.body.* == .block)
                    try extractLocals(allocator, symbols, ws.body.block.statements, locs, uri, mod_name, func_name);
            },
            else => {},
        }
    }
}

/// Get a simple type name string from a type annotation AST node.
fn nodeTypeStr(node: *parser.Node) []const u8 {
    return switch (node.*) {
        .type_named => |n| n,
        .identifier => |id| id,
        else => "var",
    };
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

/// Convert Reporter diagnostics into LSP Diagnostics with file URIs.
pub fn toDiagnostics(allocator: std.mem.Allocator, reporter: *errors.Reporter, project_root: []const u8) ![]Diagnostic {
    var diags: std.ArrayListUnmanaged(Diagnostic) = .{};
    defer diags.deinit(allocator);

    for (reporter.diagnostics.items) |diag| {
        if (diag.parent != null) continue; // skip notes/hints
        const lsp_severity: u8 = switch (diag.severity) {
            .err     => 1,
            .warning => 2,
            .note    => 3,
            .hint    => 4,
        };
        const d = makeDiag(allocator, diag, lsp_severity, project_root) catch continue;
        try diags.append(allocator, d);
    }

    return if (diags.items.len > 0) try allocator.dupe(Diagnostic, diags.items) else &.{};
}

fn makeDiag(allocator: std.mem.Allocator, err: errors.OrhonDiag, severity: u8, project_root: []const u8) !Diagnostic {
    const loc = err.loc orelse return error.NoLoc;
    if (loc.file.len == 0) return error.NoLoc;

    const full_path = if (!std.fs.path.isAbsolute(loc.file))
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ project_root, loc.file })
    else
        try allocator.dupe(u8, loc.file);
    defer allocator.free(full_path);

    return .{
        .uri = try pathToUri(allocator, full_path),
        .line = if (loc.line > 0) loc.line - 1 else 0,
        .col = if (loc.col > 0) loc.col - 1 else 0,
        .severity = severity,
        .message = try allocator.dupe(u8, err.message),
    };
}

// ============================================================
// TESTS
// ============================================================

test "runAnalysis arena does not leak or corrupt returned data" {
    // std.testing.allocator detects use-after-free and leaks in debug mode.
    // runAnalysis creates a scratch arena internally; returned diagnostics/symbols
    // must be allocated with the long-lived allocator (std.testing.allocator here)
    // and survive the arena deinit.
    const result = runAnalysis(std.testing.allocator, ".", .propagation) catch |err| {
        // Analysis may fail on missing project structure -- that's OK.
        // The important thing is that the arena was cleaned up without error.
        _ = err;
        return;
    };
    // If we got results, verify they can be read and freed without allocator errors.
    // std.testing.allocator will panic on use-after-free or double-free.
    lsp_types.freeDiagnostics(std.testing.allocator, result.diagnostics);
    lsp_types.freeSymbols(std.testing.allocator, result.symbols);
}

test "runAnalysis can be called twice without accumulation" {
    // Two sequential calls prove the arena from the first call is fully released.
    // std.testing.allocator detects leaks at test end.
    for (0..2) |_| {
        const result = runAnalysis(std.testing.allocator, ".", .propagation) catch {
            continue;
        };
        lsp_types.freeDiagnostics(std.testing.allocator, result.diagnostics);
        lsp_types.freeSymbols(std.testing.allocator, result.symbols);
    }
}
