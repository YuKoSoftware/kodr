// codegen_match.zig — Match, string match, and guarded match generators
// Contains: match/type match/string match/guarded match, fillDefaultArgsMir, utility functions.
// Compiler-function generators and arithmetic builtins are in codegen_intrinsics.zig.
// Interpolated string generation is in codegen_strings.zig.
// All functions receive *CodeGen as first parameter — cross-file calls route through stubs in codegen.zig.

const std = @import("std");
const codegen = @import("codegen.zig");
const parser = @import("../parser.zig");
const mir = @import("../mir/mir.zig");
const declarations = @import("../declarations.zig");
const types = @import("../types.zig");
const builtins = @import("../builtins.zig");
const mir_store_mod = @import("../mir_store.zig");
const mir_typed = @import("../mir_typed.zig");

const CodeGen = codegen.CodeGen;
const MirNodeIndex = mir_store_mod.MirNodeIndex;
const MirStore = mir_store_mod.MirStore;

/// MirStore-based implementation — used by new callers that already have MirNodeIndex.
pub fn mirContainsIdentifier(store: *const MirStore, idx: MirNodeIndex, name: []const u8) bool {
    if (idx == .none) return false;
    const entry = store.getNode(idx);
    if (entry.tag == .identifier) {
        const rec = mir_typed.Identifier.unpack(store, idx);
        return std.mem.eql(u8, store.strings.get(rec.name), name);
    }
    switch (entry.tag) {
        .block => {
            for (mir_typed.Block.getStmts(store, idx)) |s|
                if (mirContainsIdentifier(store, s, name)) return true;
        },
        .binary => {
            const rec = mir_typed.Binary.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.lhs, name)) return true;
            if (mirContainsIdentifier(store, rec.rhs, name)) return true;
        },
        .call => {
            const rec = mir_typed.Call.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.callee, name)) return true;
            for (store.extra_data.items[rec.args_start..rec.args_end]) |u|
                if (mirContainsIdentifier(store, @enumFromInt(u), name)) return true;
        },
        .field_access => {
            const rec = mir_typed.FieldAccess.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.object, name)) return true;
        },
        .if_stmt => {
            const rec = mir_typed.IfStmt.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.condition, name)) return true;
            if (rec.then_block != .none) if (mirContainsIdentifier(store, rec.then_block, name)) return true;
            if (rec.else_block != .none) if (mirContainsIdentifier(store, rec.else_block, name)) return true;
        },
        .var_decl => {
            const rec = mir_typed.VarDecl.unpack(store, idx);
            if (rec.value != .none) if (mirContainsIdentifier(store, rec.value, name)) return true;
        },
        .unary => {
            const rec = mir_typed.Unary.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.operand, name)) return true;
        },
        .return_stmt => {
            const rec = mir_typed.ReturnStmt.unpack(store, idx);
            if (rec.value != .none) if (mirContainsIdentifier(store, rec.value, name)) return true;
        },
        .assignment => {
            const rec = mir_typed.Assignment.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.lhs, name)) return true;
            if (mirContainsIdentifier(store, rec.rhs, name)) return true;
        },
        .index => {
            const rec = mir_typed.Index.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.object, name)) return true;
            if (mirContainsIdentifier(store, rec.index, name)) return true;
        },
        .while_stmt => {
            const rec = mir_typed.WhileStmt.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.condition, name)) return true;
            if (mirContainsIdentifier(store, rec.body, name)) return true;
        },
        .for_stmt => {
            const rec = mir_typed.ForStmt.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.body, name)) return true;
        },
        .defer_stmt => {
            const rec = mir_typed.DeferStmt.unpack(store, idx);
            if (mirContainsIdentifier(store, rec.body, name)) return true;
        },
        // Unknown node kinds are assumed not to contain the identifier. New kinds
        // must be added here if they can appear in narrowing contexts.
        else => {},
    }
    return false;
}

/// Generate a match arm body with variable name substitution.
/// Inside the body, references to `match_var` compile as `capture` instead.
/// Saves and restores the previous substitution for nested match support.
fn generateArmBodyWithSubst(cg: *CodeGen, body: MirNodeIndex, match_var: ?[]const u8, capture: []const u8) anyerror!void {
    const prev = cg.match_var_subst;
    if (match_var) |mv| {
        cg.match_var_subst = .{ .original = mv, .capture = capture };
    }
    try cg.generateBlockMir(body);
    cg.match_var_subst = prev;
}

/// Guarded match — emits as a scoped if/else chain with a temp variable.
/// Used when any arm has a guard expression (Zig switch cannot express guards).
pub fn generateGuardedMatchMir(cg: *CodeGen, idx: MirNodeIndex) anyerror!void {
    const store = cg.mir_store orelse return;
    const rec = mir_typed.MatchStmt.unpack(store, idx);
    const arms_extra = store.extra_data.items[rec.arms_start..rec.arms_end];

    try cg.emitIndent();
    try cg.emit("{\n");
    cg.indent += 1;
    try cg.emitIndent();
    try cg.emit("const _m = ");
    try cg.generateExprMir(rec.value);
    try cg.emit(";\n");

    var first = true;
    var else_body: MirNodeIndex = .none;
    var guard_counter: usize = 0;

    for (arms_extra) |au32| {
        const arm_idx: MirNodeIndex = @enumFromInt(au32);
        const arm = mir_typed.MatchArm.unpack(store, arm_idx);
        const pat = arm.pattern;
        const pat_entry = store.getNode(pat);

        // Collect else arm — emit last
        if (pat_entry.tag == .identifier) {
            const id = mir_typed.Identifier.unpack(store, pat);
            if (std.mem.eql(u8, store.strings.get(id.name), "else")) {
                else_body = arm.body;
                continue;
            }
        }

        try cg.emitIndent();
        if (!first) try cg.emit(" else ");

        if (arm.guard != .none) {
            // Guarded binding: (x if guard_expr) => body
            const pat_name: []const u8 = if (pat_entry.tag == .identifier)
                store.strings.get(mir_typed.Identifier.unpack(store, pat).name)
            else
                "_";
            try cg.emitFmt("if (_g{d}: {{ const {s} = _m; break :_g{d} ", .{ guard_counter, pat_name, guard_counter });
            try cg.generateExprMir(arm.guard);
            try cg.emit("; }) {\n");
            cg.indent += 1;
            try cg.emitIndent();
            const body_uses_var = mirContainsIdentifier(store, arm.body, pat_name);
            if (body_uses_var) {
                try cg.emitFmt("const {s} = _m;\n", .{pat_name});
            } else {
                try cg.emitFmt("const {s} = _m; _ = {s};\n", .{ pat_name, pat_name });
            }
            try cg.generateBodyStatements(arm.body);
            cg.indent -= 1;
            try cg.emitIndent();
            try cg.emit("}");
            guard_counter += 1;
        } else if (pat_entry.tag == .binary) {
            const bin = mir_typed.Binary.unpack(store, pat);
            const op: parser.Operator = @enumFromInt(bin.op);
            if (op == .range) {
                try cg.emit("if (_m >= ");
                try cg.generateExprMir(bin.lhs);
                try cg.emit(" and _m <= ");
                try cg.generateExprMir(bin.rhs);
                try cg.emit(") ");
                try cg.generateBlockMir(arm.body);
            } else {
                try cg.emit("if (_m == ");
                try cg.generateExprMir(pat);
                try cg.emit(") ");
                try cg.generateBlockMir(arm.body);
            }
        } else if (pat_entry.tag == .literal) {
            const lit = mir_typed.Literal.unpack(store, pat);
            if (lit.kind == @intFromEnum(mir.LiteralKind.string)) {
                try cg.emit("if (std.mem.eql(u8, _m, ");
                try cg.generateExprMir(pat);
                try cg.emit(")) ");
                try cg.generateBlockMir(arm.body);
            } else {
                try cg.emit("if (_m == ");
                try cg.generateExprMir(pat);
                try cg.emit(") ");
                try cg.generateBlockMir(arm.body);
            }
        } else {
            try cg.emit("if (_m == ");
            try cg.generateExprMir(pat);
            try cg.emit(") ");
            try cg.generateBlockMir(arm.body);
        }

        first = false;
    }

    if (else_body != .none) {
        if (!first) try cg.emit(" else ");
        try cg.generateBlockMir(else_body);
    }

    try cg.emit("\n");
    cg.indent -= 1;
    try cg.emitIndent();
    try cg.emit("}");
}

/// MIR-path match codegen — dispatches to string, type, or regular switch.
pub fn generateMatchMir(cg: *CodeGen, idx: MirNodeIndex) anyerror!void {
    const store = cg.mir_store orelse return;
    const rec = mir_typed.MatchStmt.unpack(store, idx);
    const arms_extra = store.extra_data.items[rec.arms_start..rec.arms_end];
    const val_entry = store.getNode(rec.value);

    // String match — Zig has no string switch, desugar to if/else chain
    const is_string_match = blk: {
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            if (store.getNode(arm.pattern).tag == .literal) {
                const lit = mir_typed.Literal.unpack(store, arm.pattern);
                if (lit.kind == @intFromEnum(mir.LiteralKind.string)) break :blk true;
            }
        }
        break :blk false;
    };

    // Type match — value is an arbitrary union, or any arm matches Error/null
    const is_type_match = blk: {
        if (val_entry.type_class == .arbitrary_union) break :blk true;
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            const pat = arm.pattern;
            const pat_entry = store.getNode(pat);
            if (pat_entry.tag == .literal) {
                const lit = mir_typed.Literal.unpack(store, pat);
                if (lit.kind == @intFromEnum(mir.LiteralKind.null_lit)) break :blk true;
            }
            if (pat_entry.tag == .identifier) {
                const id = mir_typed.Identifier.unpack(store, pat);
                if (types.Primitive.fromName(store.strings.get(id.name)) == .err) break :blk true;
            }
        }
        break :blk false;
    };

    const is_null_union = blk: {
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            if (store.getNode(arm.pattern).tag == .literal) {
                const lit = mir_typed.Literal.unpack(store, arm.pattern);
                if (lit.kind == @intFromEnum(mir.LiteralKind.null_lit)) break :blk true;
            }
        }
        break :blk false;
    };

    // Check for guarded arms — must use if/else chain (Zig switch cannot express guards)
    const has_guard = blk: {
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            if (arm.guard != .none) break :blk true;
        }
        break :blk false;
    };

    if (has_guard) {
        try cg.generateGuardedMatchMir(idx);
    } else if (is_string_match) {
        try cg.generateStringMatchMir(idx);
    } else if (is_type_match) {
        try cg.generateTypeMatchMir(idx, is_null_union);
    } else {
        // Regular switch
        try cg.emit("switch (");
        if (val_entry.tag == .identifier) {
            const val_rt = if (val_entry.type_id != .none) store.types.get(val_entry.type_id) else .unknown;
            if (val_rt == .ptr) {
                const val_id = mir_typed.Identifier.unpack(store, rec.value);
                try cg.emitFmt("{s}.*", .{store.strings.get(val_id.name)});
            } else {
                try cg.generateExprMir(rec.value);
            }
        } else {
            try cg.generateExprMir(rec.value);
        }
        try cg.emit(") {\n");
        cg.indent += 1;
        var has_wildcard = false;
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            const pat = arm.pattern;
            const pat_entry = store.getNode(pat);
            try cg.emitIndent();
            if (pat_entry.tag == .identifier) {
                const id = mir_typed.Identifier.unpack(store, pat);
                const id_name = store.strings.get(id.name);
                if (std.mem.eql(u8, id_name, "else")) {
                    has_wildcard = true;
                    try cg.emit("else");
                } else {
                    try cg.generateExprMir(pat);
                }
            } else if (pat_entry.tag == .binary) {
                const bin = mir_typed.Binary.unpack(store, pat);
                const op: parser.Operator = @enumFromInt(bin.op);
                if (op == .range) {
                    try cg.generateExprMir(bin.lhs);
                    try cg.emit("...");
                    try cg.generateExprMir(bin.rhs);
                } else {
                    try cg.generateExprMir(pat);
                }
            } else {
                try cg.generateExprMir(pat);
            }
            try cg.emit(" => ");
            try cg.generateBlockMir(arm.body);
            try cg.emit(",\n");
        }
        if (!has_wildcard) {
            var is_enum_switch = false;
            for (arms_extra) |au32| {
                const arm_idx: MirNodeIndex = @enumFromInt(au32);
                const arm = mir_typed.MatchArm.unpack(store, arm_idx);
                if (store.getNode(arm.pattern).tag == .identifier) {
                    const id = mir_typed.Identifier.unpack(store, arm.pattern);
                    if (id.resolved_kind == 1) { // enum_variant
                        is_enum_switch = true;
                        break;
                    }
                }
            }
            if (!is_enum_switch) {
                try cg.emitIndent();
                try cg.emit("else => {},\n");
            }
        }
        cg.indent -= 1;
        try cg.emitIndent();
        try cg.emit("}");
    }
}

/// MIR-path type match (arbitrary/error/null union switch).
pub fn generateTypeMatchMir(cg: *CodeGen, idx: MirNodeIndex, is_null_union: bool) anyerror!void {
    const store = cg.mir_store orelse return;
    const rec = mir_typed.MatchStmt.unpack(store, idx);
    const arms_extra = store.extra_data.items[rec.arms_start..rec.arms_end];
    const val_entry = store.getNode(rec.value);

    const match_var: ?[]const u8 = if (val_entry.tag == .identifier)
        store.strings.get(mir_typed.Identifier.unpack(store, rec.value).name)
    else
        null;

    const is_arbitrary = blk: {
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            const pat = arm.pattern;
            const pat_entry = store.getNode(pat);
            if (pat_entry.tag == .identifier) {
                const id = mir_typed.Identifier.unpack(store, pat);
                if (types.Primitive.fromName(store.strings.get(id.name)) == .err) break :blk false;
            }
            if (pat_entry.tag == .literal) {
                const lit = mir_typed.Literal.unpack(store, pat);
                if (lit.kind == @intFromEnum(mir.LiteralKind.null_lit)) break :blk false;
            }
        }
        break :blk true;
    };

    const is_error_union = blk: {
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            if (store.getNode(arm.pattern).tag == .identifier) {
                const id = mir_typed.Identifier.unpack(store, arm.pattern);
                if (types.Primitive.fromName(store.strings.get(id.name)) == .err) break :blk true;
            }
        }
        break :blk false;
    };

    const val_tc = val_entry.type_class;
    const is_null_error = val_tc == .null_error_union or (is_error_union and is_null_union);

    if (is_null_error) {
        // match on ?anyerror!T → three-way nested if
        var value_body: MirNodeIndex = .none;
        var error_body: MirNodeIndex = .none;
        var null_body: MirNodeIndex = .none;
        var else_body: MirNodeIndex = .none;
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            const pat = arm.pattern;
            const pat_entry = store.getNode(pat);
            if (pat_entry.tag == .identifier) {
                const id = mir_typed.Identifier.unpack(store, pat);
                const n = store.strings.get(id.name);
                if (types.Primitive.fromName(n) == .err) {
                    error_body = arm.body;
                } else if (std.mem.eql(u8, n, "else")) {
                    else_body = arm.body;
                } else {
                    value_body = arm.body;
                }
            } else if (pat_entry.tag == .literal) {
                const lit = mir_typed.Literal.unpack(store, pat);
                if (lit.kind == @intFromEnum(mir.LiteralKind.null_lit)) {
                    null_body = arm.body;
                } else {
                    value_body = arm.body;
                }
            } else {
                value_body = arm.body;
            }
        }
        const active_val_body = if (value_body != .none) value_body else else_body;
        const active_err_body = if (error_body != .none) error_body else else_body;
        const val_uses = if (active_val_body != .none) (if (match_var) |mv| mirContainsIdentifier(store, active_val_body, mv) else false) else false;
        const err_uses = if (active_err_body != .none) (if (match_var) |mv| mirContainsIdentifier(store, active_err_body, mv) else false) else false;
        try cg.emit("if (");
        try cg.generateExprMir(rec.value);
        try cg.emit(") |_eu| ");
        if (val_uses) try cg.emit("if (_eu) |_match_val| ") else try cg.emit("if (_eu) |_| ");
        if (active_val_body != .none) {
            try generateArmBodyWithSubst(cg, active_val_body, match_var, "_match_val");
        } else {
            try cg.emit("{}");
        }
        if (err_uses) try cg.emit(" else |_match_err| ") else try cg.emit(" else |_| ");
        if (active_err_body != .none) {
            try generateArmBodyWithSubst(cg, active_err_body, match_var, "_match_err");
        } else {
            try cg.emit("{}");
        }
        try cg.emit(" else ");
        const active_null_body = if (null_body != .none) null_body else else_body;
        if (active_null_body != .none) {
            try cg.generateBlockMir(active_null_body);
        } else {
            try cg.emit("{}");
        }
        return;
    }

    if (is_error_union) {
        // match on anyerror!T → if (val) |_match_val| { ... } else |_match_err| { ... }
        var value_body: MirNodeIndex = .none;
        var error_body: MirNodeIndex = .none;
        var else_body: MirNodeIndex = .none;
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            const pat = arm.pattern;
            const pat_entry = store.getNode(pat);
            if (pat_entry.tag == .identifier) {
                const id = mir_typed.Identifier.unpack(store, pat);
                const n = store.strings.get(id.name);
                if (types.Primitive.fromName(n) == .err) {
                    error_body = arm.body;
                } else if (std.mem.eql(u8, n, "else")) {
                    else_body = arm.body;
                } else {
                    value_body = arm.body;
                }
            } else {
                value_body = arm.body;
            }
        }
        const active_val_body = if (value_body != .none) value_body else else_body;
        const val_uses = if (active_val_body != .none) (if (match_var) |mv| mirContainsIdentifier(store, active_val_body, mv) else false) else false;
        const err_uses = if (error_body != .none) (if (match_var) |mv| mirContainsIdentifier(store, error_body, mv) else false) else false;
        try cg.emit("if (");
        try cg.generateExprMir(rec.value);
        if (val_uses) try cg.emit(") |_match_val| ") else try cg.emit(") |_| ");
        if (active_val_body != .none) {
            try generateArmBodyWithSubst(cg, active_val_body, match_var, "_match_val");
        } else {
            try cg.emit("{}");
        }
        if (err_uses) try cg.emit(" else |_match_err| ") else try cg.emit(" else |_| ");
        if (error_body != .none) {
            try generateArmBodyWithSubst(cg, error_body, match_var, "_match_err");
        } else {
            try cg.emit("{}");
        }
        return;
    }

    if (is_null_union) {
        // match on ?T → if (val) |_match_val| { ... } else { ... }
        var value_body: MirNodeIndex = .none;
        var null_body: MirNodeIndex = .none;
        var else_body: MirNodeIndex = .none;
        for (arms_extra) |au32| {
            const arm_idx: MirNodeIndex = @enumFromInt(au32);
            const arm = mir_typed.MatchArm.unpack(store, arm_idx);
            const pat = arm.pattern;
            const pat_entry = store.getNode(pat);
            if (pat_entry.tag == .literal) {
                const lit = mir_typed.Literal.unpack(store, pat);
                if (lit.kind == @intFromEnum(mir.LiteralKind.null_lit)) {
                    null_body = arm.body;
                    continue;
                }
            }
            if (pat_entry.tag == .identifier) {
                const id = mir_typed.Identifier.unpack(store, pat);
                if (std.mem.eql(u8, store.strings.get(id.name), "else")) {
                    else_body = arm.body;
                    continue;
                }
            }
            value_body = arm.body;
        }
        const active_val_body = if (value_body != .none) value_body else else_body;
        const val_uses = if (active_val_body != .none) (if (match_var) |mv| mirContainsIdentifier(store, active_val_body, mv) else false) else false;
        try cg.emit("if (");
        try cg.generateExprMir(rec.value);
        if (val_uses) try cg.emit(") |_match_val| ") else try cg.emit(") |_| ");
        if (active_val_body != .none) {
            try generateArmBodyWithSubst(cg, active_val_body, match_var, "_match_val");
        } else {
            try cg.emit("{}");
        }
        try cg.emit(" else ");
        const active_null_body = if (null_body != .none) null_body else else_body;
        if (active_null_body != .none) {
            try cg.generateBlockMir(active_null_body);
        } else {
            try cg.emit("{}");
        }
        return;
    }

    // Arbitrary union — switch with positional tag arms.
    try cg.emit("switch (");
    try cg.generateExprMir(rec.value);
    try cg.emit(") {\n");
    cg.indent += 1;

    const max_arity = 32;
    var sorted_buf: [max_arity][]const u8 = undefined;
    var sorted_len: usize = 0;
    const val_rt = if (val_entry.type_id != .none) store.types.get(val_entry.type_id) else @import("../types.zig").ResolvedType.unknown;
    if (val_rt == .union_type) {
        for (val_rt.union_type.members) |mem| {
            const n = mem.name();
            if (types.Primitive.fromName(n) == .err or types.Primitive.fromName(n) == .null_type) continue;
            if (sorted_len >= max_arity) break;
            sorted_buf[sorted_len] = n;
            sorted_len += 1;
        }
        mir.union_sort.sortMemberNames(sorted_buf[0..sorted_len]);
    }

    for (arms_extra) |au32| {
        const arm_idx: MirNodeIndex = @enumFromInt(au32);
        const arm = mir_typed.MatchArm.unpack(store, arm_idx);
        const pat = arm.pattern;
        const pat_entry = store.getNode(pat);
        try cg.emitIndent();

        if (pat_entry.tag == .identifier) {
            const id = mir_typed.Identifier.unpack(store, pat);
            const pat_name = store.strings.get(id.name);
            if (std.mem.eql(u8, pat_name, "else")) {
                try cg.emit("else");
            } else if (is_arbitrary) {
                if (mir.union_sort.positionalIndex(sorted_buf[0..sorted_len], pat_name)) |pos_idx| {
                    try cg.emitFmt("._{d}", .{pos_idx});
                } else {
                    try cg.emitFmt("._{s}", .{pat_name});
                }
            } else {
                try cg.generateExprMir(pat);
            }
        } else {
            try cg.generateExprMir(pat);
        }

        const arm_uses = if (match_var) |mv| mirContainsIdentifier(store, arm.body, mv) else false;
        if (arm_uses) try cg.emit(" => |_match_val| ") else try cg.emit(" => ");
        try generateArmBodyWithSubst(cg, arm.body, match_var, "_match_val");
        try cg.emit(",\n");
    }

    cg.indent -= 1;
    try cg.emitIndent();
    try cg.emit("}");
}

/// MIR-path string match — desugars to if/else chain.
pub fn generateStringMatchMir(cg: *CodeGen, idx: MirNodeIndex) anyerror!void {
    const store = cg.mir_store orelse return;
    const rec = mir_typed.MatchStmt.unpack(store, idx);
    const arms_extra = store.extra_data.items[rec.arms_start..rec.arms_end];
    const val_entry = store.getNode(rec.value);

    var first = true;
    var wildcard_body: MirNodeIndex = .none;

    for (arms_extra) |au32| {
        const arm_idx: MirNodeIndex = @enumFromInt(au32);
        const arm = mir_typed.MatchArm.unpack(store, arm_idx);
        const pat = arm.pattern;
        const pat_entry = store.getNode(pat);

        if (pat_entry.tag == .identifier) {
            const id = mir_typed.Identifier.unpack(store, pat);
            if (std.mem.eql(u8, store.strings.get(id.name), "else")) {
                wildcard_body = arm.body;
                continue;
            }
        }

        if (first) {
            try cg.emit("if (std.mem.eql(u8, ");
            first = false;
        } else {
            try cg.emit(" else if (std.mem.eql(u8, ");
        }

        if (val_entry.tag == .identifier) {
            const val_rt = if (val_entry.type_id != .none) store.types.get(val_entry.type_id) else .unknown;
            if (val_rt == .ptr) {
                const val_id = mir_typed.Identifier.unpack(store, rec.value);
                try cg.emitFmt("{s}.*", .{store.strings.get(val_id.name)});
            } else {
                try cg.generateExprMir(rec.value);
            }
        } else {
            try cg.generateExprMir(rec.value);
        }
        try cg.emit(", ");
        try cg.generateExprMir(pat);
        try cg.emit(")) ");
        try cg.generateBlockMir(arm.body);
    }

    if (wildcard_body != .none) {
        if (first) {
            try cg.generateBlockMir(wildcard_body);
        } else {
            try cg.emit(" else ");
            try cg.generateBlockMir(wildcard_body);
        }
    } else if (!first) {
        try cg.emit(" else {}");
    }
}

/// MIR-path fill default arguments.
/// Old MirNode tree no longer runs — getOldMirNode always returns null.
pub fn fillDefaultArgsMir(cg: *CodeGen, callee_idx: MirNodeIndex, actual_arg_count: usize) anyerror!void {
    _ = cg;
    _ = callee_idx;
    _ = actual_arg_count;
}

// ============================================================
// FREE FUNCTIONS (file-scope, not methods)
// ============================================================

pub fn opToZig(op: parser.Operator) []const u8 {
    return op.toZig();
}

/// Check if a field name is a type name used for union value access (result.i32, result.User)
pub fn isResultValueField(name: []const u8, decls: ?*declarations.DeclTable) bool {
    // .value — universal unwrap syntax for error/null unions
    if (std.mem.eql(u8, name, "value")) return true;
    // Primitive type names — always valid as union payload access
    if (types.isPrimitiveName(name)) return true;
    // Known user-defined types from the declaration table
    if (decls) |d| {
        if (d.symbols.get(name)) |sym| switch (sym) {
            .@"struct", .@"enum" => return true,
            else => {},
        };
    }
    // Builtin types that can appear in unions
    if (builtins.isBuiltinType(name)) return true;
    return false;
}

// ── Tests ──────────────────────────────────────────────────

test "isResultValueField" {
    try std.testing.expect(isResultValueField("value", null));
    try std.testing.expect(isResultValueField("i32", null));
    try std.testing.expect(isResultValueField("str", null));
    try std.testing.expect(isResultValueField("f64", null));
    try std.testing.expect(!isResultValueField("x", null));
    try std.testing.expect(!isResultValueField("myVar", null));
}

test "isResultValueField with decls" {
    const alloc = std.testing.allocator;
    var decl_table = declarations.DeclTable.init(alloc);
    defer decl_table.deinit();
    try decl_table.symbols.put("Player", .{ .@"struct" = .{ .name = "Player", .fields = &.{}, .is_pub = true } });
    try std.testing.expect(isResultValueField("Player", &decl_table));
    try std.testing.expect(!isResultValueField("Unknown", &decl_table));
}

