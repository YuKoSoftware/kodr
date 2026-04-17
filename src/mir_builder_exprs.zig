// mir_builder_exprs.zig — expressions cluster for MirBuilder (Phase B7)
// Satellite of mir_builder.zig — all functions take *MirBuilder as first parameter.
// Covers: int_literal, float_literal, string_literal, bool_literal, null_literal,
//         error_literal, identifier, binary_expr, range_expr, unary_expr, call_expr,
//         field_expr, index_expr, slice_expr, mut_borrow_expr, const_borrow_expr,
//         interpolated_string, compiler_func, array_literal, tuple_literal, version_literal.

const std = @import("std");
const mir_builder_mod = @import("mir_builder.zig");
const ast_typed = @import("ast_typed.zig");
const mir_typed = @import("mir_typed.zig");
const mir_types = @import("mir/mir_types.zig");
const string_pool = @import("string_pool.zig");
const type_store_mod = @import("type_store.zig");

const MirBuilder = mir_builder_mod.MirBuilder;
const AstNodeIndex = @import("ast_store.zig").AstNodeIndex;
const MirNodeIndex = @import("mir_store.zig").MirNodeIndex;
const StringIndex = string_pool.StringIndex;
const RT = mir_types.RT;
const TypeId = type_store_mod.TypeId;

// ── Helpers (same two-liners as mir_builder_decls.zig) ───────────────────────

fn internRT(b: *MirBuilder, rt: RT) !TypeId {
    if (rt == .unknown or rt == .inferred) return .none;
    return b.store.types.intern(b.allocator, rt);
}

fn internStr(b: *MirBuilder, ast_si: StringIndex) !StringIndex {
    return b.store.strings.intern(b.allocator, b.ast.strings.get(ast_si));
}

// ── Public dispatch ──────────────────────────────────────────────────────────

/// Called by MirBuilder.lowerNode for all expression-kind AstNodes.
pub fn lowerExpr(b: *MirBuilder, idx: AstNodeIndex) anyerror!MirNodeIndex {
    return switch (b.ast.getNode(idx).tag) {
        else => mir_typed.Passthrough.pack(b.store, b.allocator, idx, .none, .plain, .{}),
    };
}
