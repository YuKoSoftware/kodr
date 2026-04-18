// mir_builder_members.zig — members cluster for MirBuilder (Phase B8)
// Satellite of mir_builder.zig — all functions take *MirBuilder as first parameter.
// Covers: field_def, param_def, enum_variant_def.

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

// ── Helpers ───────────────────────────────────────────────────────────────────

fn internRT(b: *MirBuilder, rt: RT) !TypeId {
    if (rt == .unknown or rt == .inferred) return .none;
    return b.store.types.intern(b.allocator, rt);
}

fn internStr(b: *MirBuilder, ast_si: StringIndex) !StringIndex {
    return b.store.strings.intern(b.allocator, b.ast.strings.get(ast_si));
}

// ── Public dispatch ───────────────────────────────────────────────────────────

/// Called by MirBuilder.lowerNode for all member-kind AstNodes.
pub fn lowerMember(b: *MirBuilder, idx: AstNodeIndex) anyerror!MirNodeIndex {
    return switch (b.ast.getNode(idx).tag) {
        .field_decl   => lowerFieldDef(b, idx),
        .param        => lowerParamDef(b, idx),
        .enum_variant => lowerEnumVariantDef(b, idx),
        else          => unreachable,
    };
}

// ── Member lowerers ───────────────────────────────────────────────────────────

fn lowerFieldDef(b: *MirBuilder, idx: AstNodeIndex) anyerror!MirNodeIndex {
    const ast_rec = ast_typed.FieldDecl.unpack(b.ast, idx);
    const name = try internStr(b, ast_rec.name);
    const default: MirNodeIndex = if (ast_rec.default_value != .none)
        try b.lowerNode(ast_rec.default_value)
    else
        .none;
    const rt = b.type_map.get(idx) orelse .unknown;
    const tid = try internRT(b, rt);
    return mir_typed.FieldDef.pack(b.store, b.allocator, idx, tid, mir_types.classifyType(rt), .{
        .name            = name,
        .type_annotation = ast_rec.type_annotation,
        .default         = default,
        .flags           = ast_rec.flags,
    });
}

fn lowerParamDef(b: *MirBuilder, idx: AstNodeIndex) anyerror!MirNodeIndex {
    const ast_rec = ast_typed.Param.unpack(b.ast, idx);
    const name = try internStr(b, ast_rec.name);
    const default: MirNodeIndex = if (ast_rec.default_value != .none)
        try b.lowerNode(ast_rec.default_value)
    else
        .none;
    const rt = b.type_map.get(idx) orelse .unknown;
    const tid = try internRT(b, rt);
    return mir_typed.ParamDef.pack(b.store, b.allocator, idx, tid, mir_types.classifyType(rt), .{
        .name            = name,
        .type_annotation = ast_rec.type_annotation,
        .default         = default,
    });
}

fn lowerEnumVariantDef(b: *MirBuilder, idx: AstNodeIndex) anyerror!MirNodeIndex {
    const ast_rec = ast_typed.EnumVariant.unpack(b.ast, idx);
    const name = try internStr(b, ast_rec.name);
    const value: MirNodeIndex = if (ast_rec.value != .none)
        try b.lowerNode(ast_rec.value)
    else
        .none;
    const rt = b.type_map.get(idx) orelse .unknown;
    const tid = try internRT(b, rt);
    return mir_typed.EnumVariantDef.pack(b.store, b.allocator, idx, tid, mir_types.classifyType(rt), .{
        .name  = name,
        .value = value,
    });
}
