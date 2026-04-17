// mir_builder.zig — fused MIR builder hub (Phase B: passthrough skeleton)
// Replaces MirAnnotator + MirLowerer once populated (B5-B8).
// Satellite files (mir_builder_decls.zig, etc.) added per cluster in B5-B8.
// Contract: AstStore must outlive MirBuilder (span back-pointers are AstNodeIndex).

const std = @import("std");
const declarations = @import("declarations.zig");
const errors = @import("errors.zig");
const mir_types = @import("mir/mir_types.zig");
const mir_registry = @import("mir/mir_registry.zig");
const ast_store_mod = @import("ast_store.zig");
const mir_store_mod = @import("mir_store.zig");
const mir_typed = @import("mir_typed.zig");
const type_store_mod = @import("type_store.zig");

const AstNodeIndex = ast_store_mod.AstNodeIndex;
const AstStore = ast_store_mod.AstStore;
const MirStore = mir_store_mod.MirStore;
const MirNodeIndex = mir_store_mod.MirNodeIndex;
const MirKind = mir_store_mod.MirKind;
const RT = mir_types.RT;
const TypeClass = mir_types.TypeClass;
const Coercion = mir_types.Coercion;
const TypeId = type_store_mod.TypeId;
const UnionRegistry = mir_registry.UnionRegistry;

// Internal phase-separation result (BR4).
const ClassifyResult = struct {
    type_class: TypeClass,
    rt: RT,
};

pub const MirBuilder = struct {
    allocator: std.mem.Allocator,
    reporter: *errors.Reporter,
    decls: *declarations.DeclTable,
    /// AstNodeIndex-keyed type map produced by the resolver.
    /// Populated starting at B5; empty at B4 (passthrough-only).
    type_map: *const std.AutoHashMapUnmanaged(AstNodeIndex, RT),
    ast: *const AstStore,
    store: *MirStore,
    union_registry: *UnionRegistry,
    /// Variable name → TypeId fallback — used when a narrowed MirNode type
    /// hides the source union (BR2). Populated in B5+.
    var_types: std.StringHashMapUnmanaged(TypeId),
    /// Current function name — for return-type resolution in B5+.
    current_func_name: ?[]const u8,
    /// Module currently being built — for union-registry attribution in B5+.
    current_module_name: []const u8,
    /// Per-interpolation counter threaded through lowering (BR3).
    interp_counter: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        reporter: *errors.Reporter,
        decls: *declarations.DeclTable,
        type_map: *const std.AutoHashMapUnmanaged(AstNodeIndex, RT),
        ast: *const AstStore,
        store: *MirStore,
        union_registry: *UnionRegistry,
    ) MirBuilder {
        return .{
            .allocator = allocator,
            .reporter = reporter,
            .decls = decls,
            .type_map = type_map,
            .ast = ast,
            .store = store,
            .union_registry = union_registry,
            .var_types = .{},
            .current_func_name = null,
            .current_module_name = "",
            .interp_counter = 0,
        };
    }

    pub fn deinit(self: *MirBuilder) void {
        self.var_types.deinit(self.allocator);
    }

    pub fn build(self: *MirBuilder, root: AstNodeIndex) !MirNodeIndex {
        return self.lowerNode(root);
    }

    // ── Internal phase separation (BR4) ──────────────────────────────────
    // Ordering within lowerNode: classify → infer coercion → emit.
    // Kept as separate private functions even as stubs so the invariant
    // survives incremental population in B5-B8.

    fn classifyNode(self: *MirBuilder, idx: AstNodeIndex) ClassifyResult {
        _ = self;
        _ = idx;
        return .{ .type_class = .plain, .rt = .unknown };
    }

    fn inferCoercion(self: *MirBuilder, idx: AstNodeIndex, ty: TypeId) ?Coercion {
        _ = self;
        _ = idx;
        _ = ty;
        return null;
    }

    fn lowerNode(self: *MirBuilder, idx: AstNodeIndex) anyerror!MirNodeIndex {
        const cls = self.classifyNode(idx);
        _ = self.inferCoercion(idx, .none);
        return mir_typed.Passthrough.pack(
            self.store,
            self.allocator,
            idx,
            .none,
            cls.type_class,
            .{},
        );
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "MirBuilder: build returns passthrough node for root" {
    const allocator = std.testing.allocator;
    var store = MirStore.init();
    defer store.deinit(allocator);
    var ast_store = AstStore.init();
    defer ast_store.deinit(allocator);
    var type_map: std.AutoHashMapUnmanaged(AstNodeIndex, RT) = .{};
    defer type_map.deinit(allocator);
    var union_registry = UnionRegistry.init(allocator);
    defer union_registry.deinit();

    var builder = MirBuilder.init(
        allocator,
        undefined, // reporter — unused at B4
        undefined, // decls — unused at B4
        &type_map,
        &ast_store,
        &store,
        &union_registry,
    );
    defer builder.deinit();

    const root_span: AstNodeIndex = @enumFromInt(42);
    const idx = try builder.build(root_span);
    try std.testing.expect(idx != .none);
    const entry = store.getNode(idx);
    try std.testing.expectEqual(MirKind.passthrough, entry.tag);
    try std.testing.expectEqual(root_span, entry.span);
}

test "MirBuilder: two build calls produce distinct indices" {
    const allocator = std.testing.allocator;
    var store = MirStore.init();
    defer store.deinit(allocator);
    var ast_store = AstStore.init();
    defer ast_store.deinit(allocator);
    var type_map: std.AutoHashMapUnmanaged(AstNodeIndex, RT) = .{};
    defer type_map.deinit(allocator);
    var union_registry = UnionRegistry.init(allocator);
    defer union_registry.deinit();

    var builder = MirBuilder.init(
        allocator,
        undefined,
        undefined,
        &type_map,
        &ast_store,
        &store,
        &union_registry,
    );
    defer builder.deinit();

    const a = try builder.build(@enumFromInt(1));
    const b = try builder.build(@enumFromInt(2));
    try std.testing.expect(a != b);
}
