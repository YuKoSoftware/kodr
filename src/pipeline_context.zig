// pipeline_context.zig — Build-wide and per-module compilation contexts.
//
// Two roles:
//   * `BuildContext` — bundle of build-wide shared state (cache, registries,
//     reporter, cli, output sinks). Lives for one `runPipeline` invocation.
//   * `ModuleCompile` — per-module lifetime container with an arena allocator.
//     One per module being compiled this build. Owned by an
//     `ArrayList(ModuleCompile)` in `runPipeline`; all arenas freed at end
//     of build.
//
// Spec: docs/superpowers/specs/2026-04-26-p1-module-compile-design.md

const std = @import("std");
const cache = @import("cache.zig");
const declarations = @import("declarations.zig");
const errors = @import("errors.zig");
const mir = @import("mir/mir.zig");
const module = @import("module.zig");
const _cli = @import("cli.zig");

/// Build-wide shared state. One instance per `runPipeline` invocation,
/// constructed on the stack in `runPipeline` and passed by pointer into
/// `compileOne`.
pub const BuildContext = struct {
    gpa: std.mem.Allocator,

    // Cross-module compilation state
    comp_cache: *cache.Cache,
    union_registry: *mir.UnionRegistry,
    all_module_decls: *std.StringHashMap(*declarations.DeclTable),
    prev_iface_hashes: *std.StringHashMap(u64),
    module_builds: *std.StringHashMapUnmanaged(module.BuildType),
    /// Transitive dep closure for each module: module_name → all reachable dep names.
    /// Computed once in `runPipeline` after `validateAndOrder`; used by `compileOne`
    /// to check whether any transitive dep's interface changed since last build.
    /// Keys and dep-name slices are borrowed from `module.Resolver` (which outlives
    /// `runPipeline`). The outer `[]const []const u8` slice is owned (must be freed).
    /// ORDERING: `mod_resolver` must be declared before `transitive_deps` in
    /// `runPipeline` so that defers run in reverse order (transitive_deps freed first).
    transitive_deps: *const std.StringHashMapUnmanaged([]const []const u8),

    // I/O
    reporter: *errors.Reporter,
    cli: *_cli.CliArgs,

    // Cache writeback sinks. `compileOne` appends to these; `runPipeline`
    // flushes them to disk after the loop.
    all_warnings: *std.ArrayListUnmanaged(cache.CachedWarning),
    all_union_entries: *std.ArrayListUnmanaged(cache.CachedUnionEntry),

    // Read-only during compileOne. Populated at start of runPipeline from
    // cache.loadWarnings/loadUnions; modules iterate to replay their entries.
    cached_warnings: *const std.ArrayListUnmanaged(cache.CachedWarning),
    cached_unions: *const std.ArrayListUnmanaged(cache.CachedUnionEntry),
};

/// Per-module lifetime container with a two-arena design:
///
///   * `iface_arena` — whole-build lifetime. Holds the `decl_collector` and
///     its `DeclTable`, which is referenced across modules via
///     `BuildContext.all_module_decls`. Never freed until all modules are
///     compiled. Also holds `source_map` (needed after the module is done).
///
///   * `body_arena` — per-module scratch. Holds AST conversion, type resolver,
///     ownership/borrow/propagation checker state, MIR builder, and codegen
///     scratch. Freed at the end of `compileOne` so peak memory is bounded to
///     the largest single module rather than the whole build.
///
/// Lifetime contract:
///   * `body_arena` is deinitialized first (body never references iface).
///   * `iface_arena` outlives every other module's body_arena because
///     `BuildContext.all_module_decls` holds pointers into it.
///   * `mod_name` and `mod_ptr` are borrowed from `module.Resolver` (which
///     outlives `ModuleCompile`).
///
/// Goes in `runPipeline`'s outer `ArrayList(ModuleCompile)` from
/// initialization until end of build.
pub const ModuleCompile = struct {
    iface_arena: std.heap.ArenaAllocator, // whole-build — decl table, symbols, type_arena
    body_arena: std.heap.ArenaAllocator, // per-module — AST, resolver, MIR, codegen scratch
    mod_name: []const u8,
    mod_ptr: *module.Module,
    decl_collector: *declarations.DeclCollector,
    /// Source map produced by codegen: zig_line → orh_file:orh_line.
    /// Slice is iface-arena-owned; populated by pipeline_passes after cg.generate().
    source_map: []const module.SourceMapEntry = &.{},

    /// Whole-build interface allocator — for data that must survive across
    /// modules (decl tables, source maps).
    pub fn ifaceAllocator(self: *ModuleCompile) std.mem.Allocator {
        return self.iface_arena.allocator();
    }

    /// Per-module body allocator — for scratch data freed at end of
    /// `compileOne` (AST conversion, resolver state, MIR, codegen).
    pub fn bodyAllocator(self: *ModuleCompile) std.mem.Allocator {
        return self.body_arena.allocator();
    }

    /// Initialize a ModuleCompile in place. The caller must provide a pointer
    /// to stable storage (e.g. an ArrayList slot whose capacity has been
    /// reserved); the returned `decl_collector` and arena allocators both
    /// capture the address of `self`, so moving the struct after
    /// initialization would invalidate them.
    pub fn init(
        self: *ModuleCompile,
        gpa: std.mem.Allocator,
        reporter: *errors.Reporter,
        mod_name: []const u8,
        mod_ptr: *module.Module,
    ) !void {
        self.* = .{
            .iface_arena = std.heap.ArenaAllocator.init(gpa),
            .body_arena = std.heap.ArenaAllocator.init(gpa),
            .mod_name = mod_name,
            .mod_ptr = mod_ptr,
            .decl_collector = undefined,
        };
        errdefer {
            self.body_arena.deinit();
            self.iface_arena.deinit();
        }

        const iface_alloc = self.iface_arena.allocator();
        const dc = try iface_alloc.create(declarations.DeclCollector);
        dc.* = declarations.DeclCollector.init(iface_alloc, reporter);
        self.decl_collector = dc;
    }

    pub fn deinit(self: *ModuleCompile) void {
        // Body first (never references iface), then iface.
        // decl_collector is iface-arena-allocated; iface_arena.deinit()
        // reclaims it along with all of its internal structures.
        self.body_arena.deinit();
        self.iface_arena.deinit();
    }
};

// ---------- tests ----------

test "ModuleCompile.init creates arenas and decl collector" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    var fake_mod: module.Module = undefined;
    var mc: ModuleCompile = undefined;
    try mc.init(std.testing.allocator, &reporter, "test_mod", &fake_mod);
    defer mc.deinit();

    try std.testing.expectEqualStrings("test_mod", mc.mod_name);
    try std.testing.expect(@intFromPtr(mc.decl_collector) != 0);

    // Verify both allocators work
    const iface_buf = try mc.ifaceAllocator().alloc(u8, 4);
    @memset(iface_buf, 0x11);
    const body_buf = try mc.bodyAllocator().alloc(u8, 4);
    @memset(body_buf, 0x22);
    try std.testing.expectEqual(@as(u8, 0x11), iface_buf[0]);
    try std.testing.expectEqual(@as(u8, 0x22), body_buf[0]);
}

test "ModuleCompile.deinit frees arenas (no leaks)" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    var fake_mod: module.Module = undefined;
    var mc: ModuleCompile = undefined;
    try mc.init(std.testing.allocator, &reporter, "m", &fake_mod);

    // Allocate inside both arenas to verify both are freed by deinit.
    _ = try mc.ifaceAllocator().alloc(u8, 4096);
    _ = try mc.bodyAllocator().alloc(u8, 4096);

    mc.deinit();
    // If either arena leaked, std.testing.allocator would catch it at test end.
}

test "two ModuleCompiles have independent arenas" {
    var reporter = errors.Reporter.init(std.testing.allocator, .debug);
    defer reporter.deinit();

    var fake_mod: module.Module = undefined;
    var a: ModuleCompile = undefined;
    try a.init(std.testing.allocator, &reporter, "a", &fake_mod);
    var b: ModuleCompile = undefined;
    try b.init(std.testing.allocator, &reporter, "b", &fake_mod);

    // Test body arena independence
    {
        const a_buf = try a.bodyAllocator().alloc(u8, 8);
        @memset(a_buf, 0xAA);
        const b_buf = try b.bodyAllocator().alloc(u8, 8);
        @memset(b_buf, 0xBB);
        a.deinit();

        // b's body allocation must still be valid after a is freed.
        try std.testing.expectEqual(@as(u8, 0xBB), b_buf[0]);
        // b's iface allocation must also still be valid.
        const b_iface = try b.ifaceAllocator().alloc(u8, 8);
        @memset(b_iface, 0xCC);
    }
    b.deinit();
}
