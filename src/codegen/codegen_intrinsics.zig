// codegen_intrinsics.zig — Compiler-function generators and arithmetic builtins
// Contains: generateCompilerFuncMir (dispatch hub for @cast, @typename, @size, @copy, @move,
//           @assert, @swap, @hasField, @hasDecl, @fieldType, @fieldNames, @typeOf, @splitAt,
//           @wrap, @sat, @overflow, @compileError), emitIntrospectionType, wrapping/saturating/overflow helpers.
// Generated string interpolation is in codegen_strings.zig.
// Match generators are in codegen_match.zig.
// All functions receive *CodeGen as first parameter — cross-file calls route through stubs in codegen.zig.

const std = @import("std");
const codegen = @import("codegen.zig");
const parser = @import("../parser.zig");
const mir = @import("../mir/mir.zig");
const builtins = @import("../builtins.zig");
const types = @import("../types.zig");
const mir_store_mod = @import("../mir_store.zig");
const mir_typed = @import("../mir_typed.zig");

const CodeGen = codegen.CodeGen;
const MirNodeIndex = mir_store_mod.MirNodeIndex;
const MirStore = mir_store_mod.MirStore;

/// Emit the first argument to a struct-introspection compiler function.
/// If the arg is a type reference (type_expr, or an identifier whose name IS the
/// resolved type name — i.e. a struct/enum name used directly), emit it as-is.
/// Otherwise wrap in @TypeOf() to handle value arguments (e.g. a variable).
fn emitIntrospectionType(cg: *CodeGen, store: *const MirStore, arg_idx: MirNodeIndex) anyerror!void {
    const entry = store.getNode(arg_idx);
    const is_type_ref: bool = switch (entry.tag) {
        .type_expr => true,
        .identifier => blk: {
            const rec = mir_typed.Identifier.unpack(store, arg_idx);
            const id_name = store.strings.get(rec.name);
            if (entry.type_id == .none) {
                // Unknown-type identifier in a compt func — likely a type parameter.
                break :blk cg.inComptFunc();
            }
            const rt = store.types.get(entry.type_id);
            break :blk switch (rt) {
                .named => |n| std.mem.eql(u8, id_name, n),
                .primitive => |p| p == .@"type" and cg.inComptFunc(),
                else => false,
            };
        },
        else => blk: {
            if (entry.type_id == .none) {
                if (entry.tag == .compiler_fn) {
                    const cf_rec = mir_typed.CompilerFn.unpack(store, arg_idx);
                    const name = store.strings.get(cf_rec.name);
                    if (std.mem.eql(u8, name, "fieldType")) break :blk true;
                }
                break :blk false;
            }
            const rt = store.types.get(entry.type_id);
            break :blk rt == .primitive and rt.primitive == .@"type";
        },
    };
    if (is_type_ref) {
        try cg.generateExprMir(arg_idx);
    } else {
        try cg.emit("@TypeOf(");
        try cg.generateExprMir(arg_idx);
        try cg.emit(")");
    }
}

/// MIR-path compiler function (@typename, @cast, @size, etc.).
pub fn generateCompilerFuncMir(cg: *CodeGen, idx: MirNodeIndex) anyerror!void {
    const store = cg.mir_store orelse return;
    const rec = mir_typed.CompilerFn.unpack(store, idx);
    const cf_name = store.strings.get(rec.name);
    const args_extra = store.extra_data.items[rec.args_start..rec.args_end];

    switch (builtins.CompilerFunc.fromName(cf_name) orelse unreachable) {
        .typename => {
            try cg.emit("@typeName(@TypeOf(");
            if (args_extra.len > 0) try cg.generateExprMir(@enumFromInt(args_extra[0]));
            try cg.emit("))");
        },
        .typeid => {
            try cg.emit("@intFromPtr(@typeName(@TypeOf(");
            if (args_extra.len > 0) try cg.generateExprMir(@enumFromInt(args_extra[0]));
            try cg.emit(")).ptr)");
        },
        .cast => {
            if (args_extra.len >= 2) {
                const arg0: MirNodeIndex = @enumFromInt(args_extra[0]);
                const arg1: MirNodeIndex = @enumFromInt(args_extra[1]);
                const arg0_entry = store.getNode(arg0);
                const arg1_entry = store.getNode(arg1);
                // Use resolved MIR type when available; fall back to AST walk otherwise
                const target_type = if (arg0_entry.type_id != .none)
                    try cg.zigOfRT(store.types.get(arg0_entry.type_id))
                else blk: {
                    const span0 = arg0_entry.span;
                    const ast_node0 = cg.getAstNode(span0) orelse return;
                    break :blk try cg.typeToZig(ast_node0);
                };
                const target_is_float = target_type.len > 0 and target_type[0] == 'f';
                const target_is_enum = arg0_entry.tag == .identifier and
                    mir_typed.Identifier.unpack(store, arg0).resolved_kind == 2; // enum_type_name
                const source_is_float = blk: {
                    if (arg1_entry.tag == .literal) {
                        const lit = mir_typed.Literal.unpack(store, arg1);
                        if (lit.kind == @intFromEnum(mir.LiteralKind.float)) break :blk true;
                    }
                    if (arg1_entry.type_id != .none) {
                        const rt = store.types.get(arg1_entry.type_id);
                        if (rt == .primitive and rt.primitive.isFloat()) break :blk true;
                    }
                    break :blk false;
                };
                try cg.emitFmt("@as({s}, ", .{target_type});
                if (target_is_enum) {
                    try cg.emit("@enumFromInt(");
                } else if (target_is_float and source_is_float) {
                    try cg.emit("@floatCast(");
                } else if (target_is_float) {
                    try cg.emit("@floatFromInt(");
                } else if (source_is_float) {
                    try cg.emit("@intFromFloat(");
                } else {
                    try cg.emit("@intCast(");
                }
                try cg.generateExprMir(arg1);
                try cg.emit("))");
            } else if (args_extra.len == 1) {
                try cg.emit("@intCast(");
                try cg.generateExprMir(@enumFromInt(args_extra[0]));
                try cg.emit(")");
            }
        },
        .size => {
            try cg.emit("@sizeOf(");
            if (args_extra.len > 0) try emitIntrospectionType(cg, store, @enumFromInt(args_extra[0]));
            try cg.emit(")");
        },
        .@"align" => {
            try cg.emit("@alignOf(");
            if (args_extra.len > 0) try emitIntrospectionType(cg, store, @enumFromInt(args_extra[0]));
            try cg.emit(")");
        },
        .copy => {
            if (args_extra.len > 0) try cg.generateExprMir(@enumFromInt(args_extra[0]));
        },
        .move => {
            if (args_extra.len > 0) try cg.generateExprMir(@enumFromInt(args_extra[0]));
        },
        .assert => {
            if (args_extra.len >= 2) {
                try cg.emit("if (!(");
                try cg.generateExprMir(@enumFromInt(args_extra[0]));
                try cg.emit(")) @panic(");
                try cg.generateExprMir(@enumFromInt(args_extra[1]));
                try cg.emit(")");
            } else {
                if (cg.in_test_block) {
                    try cg.emit("try std.testing.expect(");
                } else {
                    try cg.emit("std.debug.assert(");
                }
                if (args_extra.len > 0) try cg.generateExprMir(@enumFromInt(args_extra[0]));
                try cg.emit(")");
            }
        },
        .swap => {
            if (args_extra.len == 2) {
                const arg0: MirNodeIndex = @enumFromInt(args_extra[0]);
                const arg1: MirNodeIndex = @enumFromInt(args_extra[1]);
                try cg.emit("std.mem.swap(@TypeOf(");
                try cg.generateExprMir(arg0);
                try cg.emit("), &");
                try cg.generateExprMir(arg0);
                try cg.emit(", &");
                try cg.generateExprMir(arg1);
                try cg.emit(")");
            }
        },
        .hasField => {
            try cg.emit("@hasField(");
            if (args_extra.len >= 1) try emitIntrospectionType(cg, store, @enumFromInt(args_extra[0]));
            if (args_extra.len >= 2) {
                try cg.emit(", ");
                try cg.generateExprMir(@enumFromInt(args_extra[1]));
            }
            try cg.emit(")");
        },
        .hasDecl => {
            try cg.emit("@hasDecl(");
            if (args_extra.len >= 1) try emitIntrospectionType(cg, store, @enumFromInt(args_extra[0]));
            if (args_extra.len >= 2) {
                try cg.emit(", ");
                try cg.generateExprMir(@enumFromInt(args_extra[1]));
            }
            try cg.emit(")");
        },
        .fieldType => {
            try cg.emit("@FieldType(");
            if (args_extra.len >= 1) try emitIntrospectionType(cg, store, @enumFromInt(args_extra[0]));
            if (args_extra.len >= 2) {
                try cg.emit(", ");
                try cg.generateExprMir(@enumFromInt(args_extra[1]));
            }
            try cg.emit(")");
        },
        .fieldNames => {
            try cg.emit("std.meta.fieldNames(");
            if (args_extra.len >= 1) try emitIntrospectionType(cg, store, @enumFromInt(args_extra[0]));
            try cg.emit(")");
        },
        .typeOf => {
            try cg.emit("@TypeOf(");
            if (args_extra.len > 0) try cg.generateExprMir(@enumFromInt(args_extra[0]));
            try cg.emit(")");
        },
        .splitAt => {
            try cg.emit("/* @splitAt must be used with destructuring: const a, b = @splitAt(arr, n) */");
        },
        .wrap => {
            if (args_extra.len > 0) try generateWrappingExprMir(cg, @enumFromInt(args_extra[0]));
        },
        .sat => {
            if (args_extra.len > 0) try generateSaturatingExprMir(cg, @enumFromInt(args_extra[0]));
        },
        .overflow => {
            if (args_extra.len > 0) try generateOverflowExprMir(cg, @enumFromInt(args_extra[0]));
        },
        .compileError => {
            try cg.emit("@compileError(");
            if (args_extra.len > 0) try cg.generateExprMir(@enumFromInt(args_extra[0]));
            try cg.emit(")");
        },
        // @type is an internal desugaring artifact from `x is T` — always handled as
        // part of binary `is` expression in codegen_exprs, never reaches here standalone
        .@"type" => {
            _ = try cg.reporter.reportFmt(.internal_zig_codegen, null,
                "internal: @type should not reach generateCompilerFuncMir", .{});
            return error.CompileError;
        },
    }
}

// ── Operator maps for arithmetic builtins ───────────────────────

fn mapWrappingOp(op: parser.Operator) ?[]const u8 {
    return switch (op) {
        .add => "+%",
        .sub => "-%",
        .mul => "*%",
        else => null,
    };
}

fn mapSaturatingOp(op: parser.Operator) ?[]const u8 {
    return switch (op) {
        .add => "+|",
        .sub => "-|",
        .mul => "*|",
        else => null,
    };
}

fn mapOverflowBuiltin(op: parser.Operator) ?[]const u8 {
    return switch (op) {
        .add => "@addWithOverflow",
        .sub => "@subWithOverflow",
        .mul => "@mulWithOverflow",
        else => null,
    };
}

// ── Wrapping / saturating / overflow: MIR paths ────────────────────

pub fn generateWrappingExprMir(cg: *CodeGen, idx: MirNodeIndex) anyerror!void {
    const store = cg.mir_store orelse return;
    const entry = store.getNode(idx);
    if (entry.tag == .binary) {
        const bin = mir_typed.Binary.unpack(store, idx);
        const op: parser.Operator = @enumFromInt(bin.op);
        if (mapWrappingOp(op)) |wop| {
            try cg.generateExprMir(bin.lhs);
            try cg.emitFmt(" {s} ", .{wop});
            try cg.generateExprMir(bin.rhs);
            return;
        }
    }
    try cg.generateExprMir(idx);
}

pub fn generateSaturatingExprMir(cg: *CodeGen, idx: MirNodeIndex) anyerror!void {
    const store = cg.mir_store orelse return;
    const entry = store.getNode(idx);
    if (entry.tag == .binary) {
        const bin = mir_typed.Binary.unpack(store, idx);
        const op: parser.Operator = @enumFromInt(bin.op);
        if (mapSaturatingOp(op)) |sop| {
            try cg.generateExprMir(bin.lhs);
            try cg.emitFmt(" {s} ", .{sop});
            try cg.generateExprMir(bin.rhs);
            return;
        }
    }
    try cg.generateExprMir(idx);
}

// ── Overflow: MIR path ──────────────────────────────────────────
// overflow(a + b) → (blk: { const _ov = @addWithOverflow(a, b);
//   if (_ov[1] != 0) break :blk @as(anyerror!@TypeOf(a), error.overflow)
//   else break :blk @as(anyerror!@TypeOf(a), _ov[0]); })

pub fn generateOverflowExprMir(cg: *CodeGen, idx: MirNodeIndex) anyerror!void {
    const store = cg.mir_store orelse return;
    const entry = store.getNode(idx);
    if (entry.tag == .binary) {
        const bin = mir_typed.Binary.unpack(store, idx);
        const op: parser.Operator = @enumFromInt(bin.op);
        if (mapOverflowBuiltin(op)) |builtin| {
            try cg.emit("(blk: { const _ov = ");
            try cg.emitFmt("{s}(", .{builtin});
            try cg.generateExprMir(bin.lhs);
            try cg.emit(", ");
            try cg.generateExprMir(bin.rhs);
            try cg.emit("); if (_ov[1] != 0) break :blk @as(anyerror!@TypeOf(");
            try cg.generateExprMir(bin.lhs);
            try cg.emit("), error.overflow) else break :blk @as(anyerror!@TypeOf(");
            try cg.generateExprMir(bin.lhs);
            try cg.emit("), _ov[0]); })");
            return;
        }
    }
    try cg.generateExprMir(idx);
}

// ── Tests ──────────────────────────────────────────────────

test "mapWrappingOp" {
    try std.testing.expectEqualStrings("+%", mapWrappingOp(.add).?);
    try std.testing.expectEqualStrings("-%", mapWrappingOp(.sub).?);
    try std.testing.expectEqualStrings("*%", mapWrappingOp(.mul).?);
    try std.testing.expect(mapWrappingOp(.div) == null);
    try std.testing.expect(mapWrappingOp(.mod) == null);
}

test "mapSaturatingOp" {
    try std.testing.expectEqualStrings("+|", mapSaturatingOp(.add).?);
    try std.testing.expectEqualStrings("-|", mapSaturatingOp(.sub).?);
    try std.testing.expectEqualStrings("*|", mapSaturatingOp(.mul).?);
    try std.testing.expect(mapSaturatingOp(.div) == null);
}

test "mapOverflowBuiltin" {
    try std.testing.expectEqualStrings("@addWithOverflow", mapOverflowBuiltin(.add).?);
    try std.testing.expectEqualStrings("@subWithOverflow", mapOverflowBuiltin(.sub).?);
    try std.testing.expectEqualStrings("@mulWithOverflow", mapOverflowBuiltin(.mul).?);
    try std.testing.expect(mapOverflowBuiltin(.div) == null);
}
