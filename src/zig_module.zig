// zig_module.zig — Zig-to-Orhon automatic module converter
// Maps Zig types from std.zig.Ast nodes to Orhon type strings.
// Self-contained: depends only on std.zig.Ast, no Orhon compiler modules.

const std = @import("std");
const Ast = std.zig.Ast;
const Node = Ast.Node;
const Allocator = std.mem.Allocator;

/// Primitives that pass through unchanged from Zig to Orhon.
const PASSTHROUGH_PRIMITIVES = [_][]const u8{
    "u8",    "i8",   "i16",  "i32",  "i64",
    "u16",   "u32",  "u64",  "f32",  "f64",
    "bool",  "void", "usize",
};

/// Output buffer for type mapping. Wraps an unmanaged ArrayList(u8).
pub const TypeBuf = struct {
    buf: std.ArrayList(u8) = .{},

    pub fn append(self: *TypeBuf, allocator: Allocator, data: []const u8) Allocator.Error!void {
        try self.buf.appendSlice(allocator, data);
    }

    pub fn deinit(self: *TypeBuf, allocator: Allocator) void {
        self.buf.deinit(allocator);
    }

    pub fn items(self: *const TypeBuf) []const u8 {
        return self.buf.items;
    }
};

/// Writes the Orhon type string for the given Zig AST type node into `out`.
/// Returns `true` if the type was successfully mapped, `false` if unmappable.
pub fn mapType(tree: *const Ast, node: Node.Index, allocator: Allocator, out: *TypeBuf) anyerror!bool {
    const tag = tree.nodeTag(node);

    switch (tag) {
        // --- identifier: primitive passthrough or user-defined type ---
        .identifier => {
            const token = tree.nodeMainToken(node);
            const name = tree.tokenSlice(token);

            // anytype → any
            if (std.mem.eql(u8, name, "anytype")) {
                try out.append(allocator, "any");
                return true;
            }

            // Check primitives
            for (PASSTHROUGH_PRIMITIVES) |prim| {
                if (std.mem.eql(u8, name, prim)) {
                    try out.append(allocator, name);
                    return true;
                }
            }

            // A bare identifier that isn't a primitive is a user-defined type.
            // Qualified names (std.mem.Allocator) are caught by field_access.
            try out.append(allocator, name);
            return true;
        },

        // --- ?T → NullUnion(T) ---
        .optional_type => {
            const child = tree.nodeData(node).node;
            try out.append(allocator, "NullUnion(");
            const ok = try mapType(tree, child, allocator, out);
            if (!ok) return false;
            try out.append(allocator, ")");
            return true;
        },

        // --- lhs!rhs → ErrorUnion(rhs) ---
        // For `anyerror!T`, lhs is the error set, rhs is the payload type.
        .error_union => {
            const rhs = tree.nodeData(node).node_and_node[1];
            try out.append(allocator, "ErrorUnion(");
            const ok = try mapType(tree, rhs, allocator, out);
            if (!ok) return false;
            try out.append(allocator, ")");
            return true;
        },

        // --- pointer types: *T, *const T, []const u8, []T ---
        .ptr_type_aligned,
        .ptr_type_sentinel,
        .ptr_type,
        .ptr_type_bit_range,
        => {
            const ptr_info = tree.fullPtrType(node) orelse return false;

            switch (ptr_info.size) {
                // []T or []const T — slice types
                .slice => {
                    const is_const = ptr_info.const_token != null;
                    // Check for []const u8 → String
                    if (is_const) {
                        if (tree.nodeTag(ptr_info.ast.child_type) == .identifier) {
                            const child_name = tree.tokenSlice(tree.nodeMainToken(ptr_info.ast.child_type));
                            if (std.mem.eql(u8, child_name, "u8")) {
                                try out.append(allocator, "String");
                                return true;
                            }
                        }
                    }
                    // Other slices are unmappable for now
                    return false;
                },

                // *T or *const T — single-item pointer
                .one => {
                    const is_const = ptr_info.const_token != null;
                    if (is_const) {
                        try out.append(allocator, "const& ");
                    } else {
                        try out.append(allocator, "mut& ");
                    }
                    return try mapType(tree, ptr_info.ast.child_type, allocator, out);
                },

                // [*]T, [*c]T — many-item and c pointers are unmappable
                .many, .c => return false,
            }
        },

        // --- field_access: lhs.rhs — qualified names like std.mem.Allocator ---
        .field_access => {
            // Qualified names are unmappable (std.mem.Allocator, etc.)
            return false;
        },

        else => return false,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Parse a Zig type expression wrapped in a variable declaration,
/// extract the type node, and run mapType on it.
fn testMapType(source: [:0]const u8) !?[]const u8 {
    const allocator = std.testing.allocator;
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);

    // The source is `const _: TYPE = undefined;`
    const root_decls = tree.rootDecls();
    if (root_decls.len == 0) return null;

    const decl_node = root_decls[0];
    const var_decl = tree.fullVarDecl(decl_node) orelse return null;
    const type_node = var_decl.ast.type_node.unwrap() orelse return null;

    var out: TypeBuf = .{};
    defer out.deinit(allocator);

    const ok = try mapType(&tree, type_node, allocator, &out);
    if (!ok) return null;

    return try allocator.dupe(u8, out.items());
}

fn expectMapping(source: [:0]const u8, expected: []const u8) !void {
    const result = try testMapType(source);
    if (result) |actual| {
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    } else {
        std.debug.print("Expected '{s}' but got null (unmappable)\n", .{expected});
        return error.TestUnexpectedResult;
    }
}

fn expectUnmappable(source: [:0]const u8) !void {
    const result = try testMapType(source);
    if (result) |actual| {
        defer std.testing.allocator.free(actual);
        std.debug.print("Expected unmappable but got '{s}'\n", .{actual});
        return error.TestUnexpectedResult;
    }
}

test "primitive passthrough" {
    try expectMapping("const _: i32 = undefined;", "i32");
    try expectMapping("const _: u8 = undefined;", "u8");
    try expectMapping("const _: i8 = undefined;", "i8");
    try expectMapping("const _: i16 = undefined;", "i16");
    try expectMapping("const _: i64 = undefined;", "i64");
    try expectMapping("const _: u16 = undefined;", "u16");
    try expectMapping("const _: u32 = undefined;", "u32");
    try expectMapping("const _: u64 = undefined;", "u64");
    try expectMapping("const _: f32 = undefined;", "f32");
    try expectMapping("const _: f64 = undefined;", "f64");
    try expectMapping("const _: bool = undefined;", "bool");
    try expectMapping("const _: void = undefined;", "void");
    try expectMapping("const _: usize = undefined;", "usize");
}

test "[]const u8 maps to String" {
    try expectMapping("const _: []const u8 = undefined;", "String");
}

test "?T maps to NullUnion(T)" {
    try expectMapping("const _: ?i32 = undefined;", "NullUnion(i32)");
    try expectMapping("const _: ?bool = undefined;", "NullUnion(bool)");
}

test "anyerror!T maps to ErrorUnion(T)" {
    try expectMapping("const _: anyerror!i32 = undefined;", "ErrorUnion(i32)");
    try expectMapping("const _: anyerror!void = undefined;", "ErrorUnion(void)");
}

test "*T maps to mut& T" {
    try expectMapping("const _: *i32 = undefined;", "mut& i32");
}

test "*const T maps to const& T" {
    try expectMapping("const _: *const i32 = undefined;", "const& i32");
}

test "user-defined types pass through" {
    try expectMapping("const _: MyStruct = undefined;", "MyStruct");
    try expectMapping("const _: SomeEnum = undefined;", "SomeEnum");
}

test "qualified names are unmappable" {
    try expectUnmappable("const _: std.mem.Allocator = undefined;");
}

test "non-u8 slices are unmappable" {
    try expectUnmappable("const _: []const i32 = undefined;");
    try expectUnmappable("const _: []u8 = undefined;");
}

test "nested types" {
    try expectMapping("const _: ?[]const u8 = undefined;", "NullUnion(String)");
    try expectMapping("const _: anyerror![]const u8 = undefined;", "ErrorUnion(String)");
    try expectMapping("const _: *const []const u8 = undefined;", "const& String");
}
