// codegen_strings.zig — Interpolated string generation (MirStore path)
// Contains: generateInterpolatedStringMirFromStore — builds allocPrint decl from
//           expression parts, hoists to pre_stmts frame with proper inner-dep ordering.
// Match generators are in codegen_match.zig.
// Compiler-function generators are in codegen_intrinsics.zig.
// All functions receive *CodeGen as first parameter — cross-file calls route through stubs in codegen.zig.

const std = @import("std");
const codegen = @import("codegen.zig");
const mir = @import("../mir/mir.zig");
const types = @import("../types.zig");
const mir_store_mod = @import("../mir_store.zig");
const mir_typed = @import("../mir_typed.zig");

const CodeGen = codegen.CodeGen;
const MirNodeIndex = mir_store_mod.MirNodeIndex;
const MirStore = mir_store_mod.MirStore;

/// MIR-path interpolated string — MirStore variant.
/// Reads (tag, payload) pairs from extra_data[parts_start..parts_end]:
///   tag==0: string literal (payload is StringIndex)
///   tag==1: expression (payload is MirNodeIndex)
/// Builds the allocPrint decl in a local buffer and appends it to the top pre_stmts frame.
/// Per-arg frames capture any inner-dep pre_stmts (from nested expressions when @{} gains
/// full-expression support) and prepend them to the parent frame before this decl.
pub fn generateInterpolatedStringMirFromStore(cg: *CodeGen, store: *const MirStore, parts_start: u32, parts_end: u32) anyerror!void {
    const n = cg.interp_count;
    cg.interp_count += 1;

    // Build indent prefix for hoisted lines
    var indent_buf: [256]u8 = undefined;
    var indent_len: usize = 0;
    var i: usize = 0;
    while (i < cg.indent and indent_len + 4 <= indent_buf.len) : (i += 1) {
        @memcpy(indent_buf[indent_len .. indent_len + 4], "    ");
        indent_len += 4;
    }
    const indent_str = indent_buf[0..indent_len];

    var name_buf: [32]u8 = undefined;
    const var_name = std.fmt.bufPrint(&name_buf, "_interp_{d}", .{n}) catch "_interp";

    // Build the entire decl in a local buffer so inner-dep frames (from nested expressions
    // in arg codegen) can be prepended to the parent frame before this decl is appended,
    // giving correct declaration order: inner deps → outer decl → statement.
    var decl_buf = std.ArrayListUnmanaged(u8){};
    defer decl_buf.deinit(cg.allocator);

    try decl_buf.appendSlice(cg.allocator, indent_str);
    try decl_buf.appendSlice(cg.allocator, "const ");
    try decl_buf.appendSlice(cg.allocator, var_name);
    try decl_buf.appendSlice(cg.allocator, " = std.fmt.allocPrint(std.heap.smp_allocator, \"");

    // Pass 1: build format string into decl_buf
    var j: u32 = parts_start;
    while (j + 1 <= parts_end) : (j += 2) {
        const tag = store.extra_data.items[j];
        const payload = store.extra_data.items[j + 1];
        if (tag == 0) {
            // String literal part — escape for Zig fmt
            const si: mir_typed.StringIndex = @enumFromInt(payload);
            const text = store.strings.get(si);
            for (text) |ch| {
                switch (ch) {
                    '{' => try decl_buf.appendSlice(cg.allocator, "{{"),
                    '}' => try decl_buf.appendSlice(cg.allocator, "}}"),
                    '\\' => try decl_buf.appendSlice(cg.allocator, "\\"),
                    else => try decl_buf.append(cg.allocator, ch),
                }
            }
        } else {
            // Expression part — choose format specifier
            const expr_idx: MirNodeIndex = @enumFromInt(payload);
            if (CodeGen.mirIsStringFromStore(store, expr_idx)) {
                try decl_buf.appendSlice(cg.allocator, "{s}");
            } else {
                try decl_buf.appendSlice(cg.allocator, "{}");
            }
        }
    }
    try decl_buf.appendSlice(cg.allocator, "\", .{");

    // Pass 2: per-arg capture — each arg expression is emitted into a fresh output buffer.
    // A per-arg frame on the pre_stmts stack collects any inner-dep pre_stmts that arg
    // codegen produces, which are flushed to the parent frame before this decl.
    var first = true;
    var k: u32 = parts_start;
    while (k + 1 <= parts_end) : (k += 2) {
        if (store.extra_data.items[k] != 1) continue;
        if (!first) try decl_buf.appendSlice(cg.allocator, ", ");

        try cg.pushPreStmtsFrame(); // frame for inner deps this arg may produce
        const saved_output = cg.output;
        cg.output = .{}; // fresh capture buffer — never aliases pre_stmts_stack
        const expr_idx: MirNodeIndex = @enumFromInt(store.extra_data.items[k + 1]);
        try cg.generateExprMir(expr_idx);
        var arg_buf = cg.output;
        cg.output = saved_output;
        var inner_deps = cg.popPreStmtsFrame();
        defer inner_deps.deinit(cg.allocator);
        defer arg_buf.deinit(cg.allocator);

        // Inner deps go to the parent frame before this decl; arg text goes into decl_buf
        if (inner_deps.items.len > 0) {
            try cg.topPreStmts().appendSlice(cg.allocator, inner_deps.items);
        }
        try decl_buf.appendSlice(cg.allocator, arg_buf.items);
        first = false;
    }

    // Complete the allocPrint call
    const ret_tc = cg.funcReturnTypeClass();
    if (ret_tc == .error_union or ret_tc == .null_error_union) {
        try decl_buf.appendSlice(cg.allocator, "}) catch |err| return err;\n");
    } else {
        try decl_buf.appendSlice(cg.allocator, "}) catch unreachable;\n");
    }
    try decl_buf.appendSlice(cg.allocator, indent_str);
    try decl_buf.appendSlice(cg.allocator, "defer std.heap.smp_allocator.free(");
    try decl_buf.appendSlice(cg.allocator, var_name);
    try decl_buf.appendSlice(cg.allocator, ");\n");

    // Append this decl to the parent frame (after any inner deps already prepended above)
    try cg.topPreStmts().appendSlice(cg.allocator, decl_buf.items);

    // Emit just the temp var name as the expression result
    try cg.emit(var_name);
}
