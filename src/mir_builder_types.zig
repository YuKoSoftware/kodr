// mir_builder_types.zig — types + injected cluster for MirBuilder (Phase B8)
// Satellite of mir_builder.zig — all functions take *MirBuilder as first parameter.
// Covers:
//   type_expr  — all structural type AST nodes (codegen reads back via typeToZig())
//   temp_var   — synthetic interpolation temporary (no AST counterpart)
//   injected_defer — synthetic cleanup defer (no AST counterpart)

const std = @import("std");
const mir_builder_mod = @import("mir_builder.zig");
const mir_typed = @import("mir_typed.zig");
const mir_types = @import("mir/mir_types.zig");
const type_store_mod = @import("type_store.zig");

const MirBuilder = mir_builder_mod.MirBuilder;
const AstNodeIndex = @import("ast_store.zig").AstNodeIndex;
const MirNodeIndex = @import("mir_store.zig").MirNodeIndex;
const RT = mir_types.RT;
const TypeId = type_store_mod.TypeId;

fn internRT(b: *MirBuilder, rt: RT) !TypeId {
    if (rt == .unknown or rt == .inferred) return .none;
    return b.store.types.intern(b.allocator, rt);
}

// ── Type expression ───────────────────────────────────────────────────────────

/// All structural type AST nodes → type_expr.
/// No children are lowered: codegen reads back through span via typeToZig().
pub fn lowerTypeExpr(b: *MirBuilder, idx: AstNodeIndex) anyerror!MirNodeIndex {
    const rt = b.type_map.get(idx) orelse .unknown;
    const tid = try internRT(b, rt);
    return mir_typed.TypeExpr.pack(b.store, b.allocator, idx, tid, mir_types.classifyType(rt), .{});
}

// ── Injected node helpers ─────────────────────────────────────────────────────

/// Create a synthetic temp_var node (no AST counterpart).
/// Called by statement lowering when hoisting interpolation temporaries (BR3).
/// type_class = .string because codegen emits these as std.ArrayList(u8) locals.
pub fn createTempVar(b: *MirBuilder, name: []const u8) !MirNodeIndex {
    const si = try b.store.strings.intern(b.allocator, name);
    return mir_typed.TempVar.pack(b.store, b.allocator, .none, .none, .string, .{ .name = si });
}

/// Create a synthetic injected_defer node (no AST counterpart).
/// Called alongside createTempVar for interpolation cleanup (BR3).
/// type_class = .plain because the defer body has no runtime value.
pub fn createInjectedDefer(b: *MirBuilder, body: MirNodeIndex) !MirNodeIndex {
    return mir_typed.InjectedDefer.pack(b.store, b.allocator, .none, .none, .plain, .{ .body = body });
}
