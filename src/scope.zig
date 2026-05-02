// scope.zig — Generic scope with flat ArrayList + frame start-index stack
// Used by resolver (pass 5), ownership (pass 6), and propagation (pass 8).

const std = @import("std");

/// Generic scope: a single flat list of bindings with a frame stack that
/// tracks where each scope frame begins. Pushing/poping frames truncates
/// the binding list, so inner-frame bindings are automatically removed.
pub fn ScopeBase(comptime V: type) type {
    return struct {
        const Self = @This();

        const Binding = struct {
            name: []const u8,
            value: V,
        };

        const FrameInfo = struct {
            /// Index into vars where this frame begins
            start: usize,
            /// Whether this frame is a function boundary (shadowing check stops here)
            is_func_root: bool,
        };

        vars: std.ArrayListUnmanaged(Binding) = .{},
        frames: std.ArrayListUnmanaged(FrameInfo) = .{},
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .vars = .{},
                .frames = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.vars.deinit(self.allocator);
            self.frames.deinit(self.allocator);
        }

        /// Append a binding to the flat vars list. Caller manages frames.
        pub fn define(self: *Self, name: []const u8, value: V) !void {
            try self.vars.append(self.allocator, .{ .name = name, .value = value });
        }

        /// Scan vars backwards — inner-frame bindings are found first (shadowing).
        pub fn lookup(self: *const Self, name: []const u8) ?V {
            var i: usize = self.vars.items.len;
            while (i > 0) {
                i -= 1;
                if (std.mem.eql(u8, self.vars.items[i].name, name)) {
                    return self.vars.items[i].value;
                }
            }
            return null;
        }

        /// Scan vars backwards, return pointer to value.
        pub fn lookupPtr(self: *Self, name: []const u8) ?*V {
            var i: usize = self.vars.items.len;
            while (i > 0) {
                i -= 1;
                if (std.mem.eql(u8, self.vars.items[i].name, name)) {
                    return &self.vars.items[i].value;
                }
            }
            return null;
        }

        /// Push a regular frame boundary.
        pub fn pushFrame(self: *Self) !void {
            try self.frames.append(self.allocator, .{
                .start = self.vars.items.len,
                .is_func_root = false,
            });
        }

        /// Push a function frame boundary (shadowing check stops here).
        pub fn pushFuncFrame(self: *Self) !void {
            try self.frames.append(self.allocator, .{
                .start = self.vars.items.len,
                .is_func_root = true,
            });
        }

    /// Pop the last frame and truncate vars to its start index.
    pub fn popFrame(self: *Self) void {
        std.debug.assert(self.frames.items.len > 0);
        const frame = self.frames.pop().?;
        self.vars.shrinkRetainingCapacity(frame.start);
    }

        /// Check if a name exists in the current frame only.
        pub fn containsInCurrentFrame(self: *const Self, name: []const u8) bool {
            const start = if (self.frames.items.len > 0)
                self.frames.items[self.frames.items.len - 1].start
            else
                0;
            var i: usize = self.vars.items.len;
            while (i > start) {
                i -= 1;
                if (std.mem.eql(u8, self.vars.items[i].name, name)) {
                    return true;
                }
            }
            return false;
        }

        /// Check if a name exists in enclosing frames (NOT the current frame),
        /// stopping after the first func_root frame boundary. func_root frame
        /// bindings ARE checked (catches function parameter shadowing).
        pub fn containsInEnclosingFrames(self: *const Self, name: []const u8) bool {
            if (self.frames.items.len < 2) return false;

            // Upper bound of the scan region (exclusive) = start of current frame
            var upper: usize = self.frames.items[self.frames.items.len - 1].start;

            // Walk frames from just below current to the bottom
            var fi: usize = self.frames.items.len - 1;
            while (fi > 0) {
                fi -= 1;
                const frame = self.frames.items[fi];
                // Check this frame's bindings (including func_root frames)
                var i: usize = upper;
                while (i > frame.start) {
                    i -= 1;
                    if (std.mem.eql(u8, self.vars.items[i].name, name)) return true;
                }
                if (frame.is_func_root) {
                    return false; // All enclosing frames up to func boundary checked, nothing found
                }
                upper = frame.start;
            }
            return false;
        }

    /// Returns a slice of bindings in the current frame.
    /// WARNING: The returned slice is invalidated by any subsequent call to
    /// `define`, `pushFrame`, `pushFuncFrame`, or `popFrame` (which may
    /// reallocate or resize the underlying ArrayList). Copy if needed.
    pub fn currentFrameBindings(self: *const Self) []Binding {
            const start = if (self.frames.items.len > 0)
                self.frames.items[self.frames.items.len - 1].start
            else
                0;
            return self.vars.items[start..];
        }

        /// Returns true if any frame has is_func_root = true.
        pub fn isInsideFunction(self: *const Self) bool {
            for (self.frames.items) |frame| {
                if (frame.is_func_root) return true;
            }
            return false;
        }
    };
}

// --- tests ---

const testing = std.testing;

test "ScopeBase — define and lookup" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFrame();
    try scope.define("x", 42);
    try testing.expectEqual(@as(i32, 42), scope.lookup("x").?);
    try testing.expect(scope.lookup("y") == null);
    scope.popFrame();
}

test "ScopeBase — shadowing in nested scope" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFrame();
    try scope.define("x", 1);
    try testing.expectEqual(@as(i32, 1), scope.lookup("x").?);

    try scope.pushFrame();
    try scope.define("x", 2);
    try testing.expectEqual(@as(i32, 2), scope.lookup("x").?);
    scope.popFrame();

    try testing.expectEqual(@as(i32, 1), scope.lookup("x").?);
    scope.popFrame();
}

test "ScopeBase — pop removes frame bindings" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFrame();
    try scope.define("a", 1);
    try scope.pushFrame();
    try scope.define("b", 2);
    try testing.expect(scope.lookup("a") != null);
    try testing.expect(scope.lookup("b") != null);

    scope.popFrame();
    try testing.expect(scope.lookup("b") == null);
    try testing.expect(scope.lookup("a") != null);

    scope.popFrame();
    try testing.expect(scope.lookup("a") == null);
}

test "ScopeBase — pointer stability across frames" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFrame();
    try scope.define("x", 42);
    try scope.vars.ensureTotalCapacity(testing.allocator, 10);
    const ptr = scope.lookupPtr("x").?;
    try testing.expectEqual(@as(i32, 42), ptr.*);

    // Push/pop inner frame — outer bindings are unaffected
    try scope.pushFrame();
    try scope.define("y", 99);
    try testing.expectEqual(@as(i32, 42), ptr.*);
    scope.popFrame();

    try testing.expectEqual(@as(i32, 42), ptr.*);
    scope.popFrame();
}

test "ScopeBase — func_root bindings checked for shadowing" {
    // Simulate: func foo(x: i32) { if cond { const x: ... } }
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFuncFrame();
    try scope.define("x", 1);        // function parameter
    try scope.pushFrame();           // inner block
    // containsInEnclosingFrames should find func_root binding "x"
    try testing.expect(scope.containsInEnclosingFrames("x"));
    try testing.expect(!scope.containsInEnclosingFrames("y"));
    scope.popFrame();
    scope.popFrame();
}

test "ScopeBase — does not cross func_root into parent function" {
    // Simulate: func foo() { func bar() { const x: i32; } } — bar's "x" does NOT shadow foo's
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFuncFrame();       // outer function frame
    try scope.pushFrame();
    try scope.define("x", 1);        // outer function's local (but inside inner frame for demo)
    try scope.pushFuncFrame();       // inner function frame
    try scope.pushFrame();           // inner function body block
    try scope.define("y", 2);
    // From inner function's body, "x" should NOT be found (it's in the outer function)
    try testing.expect(!scope.containsInEnclosingFrames("x"));
    scope.popFrame();
    scope.popFrame();
    scope.popFrame();
    scope.popFrame();
}

test "ScopeBase — containsInCurrentFrame" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFrame();
    try scope.define("x", 1);
    try testing.expect(scope.containsInCurrentFrame("x"));
    try testing.expect(!scope.containsInCurrentFrame("y"));
    scope.popFrame();
}

test "ScopeBase — containsInEnclosingFrames without func_root" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFrame();
    try scope.define("x", 1);
    try scope.pushFrame();
    try scope.define("y", 2);
    try testing.expect(scope.containsInEnclosingFrames("x"));
    try testing.expect(!scope.containsInEnclosingFrames("y"));
    try testing.expect(!scope.containsInEnclosingFrames("z"));
    scope.popFrame();
    scope.popFrame();
}

test "ScopeBase — isInsideFunction" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try testing.expect(!scope.isInsideFunction());
    try scope.pushFrame();
    try testing.expect(!scope.isInsideFunction());
    try scope.pushFuncFrame();
    try testing.expect(scope.isInsideFunction());
    scope.popFrame();
    scope.popFrame();
}

test "ScopeBase — currentFrameBindings" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.pushFrame();
    try scope.define("a", 1);
    try scope.define("b", 2);

    const bindings = scope.currentFrameBindings();
    try testing.expect(bindings.len == 2);
    try testing.expect(std.mem.eql(u8, bindings[0].name, "a"));
    try testing.expectEqual(@as(i32, 1), bindings[0].value);
    try testing.expect(std.mem.eql(u8, bindings[1].name, "b"));
    try testing.expectEqual(@as(i32, 2), bindings[1].value);
    scope.popFrame();
}

test "ScopeBase — lookupPtr returns null for missing" {
    var scope = ScopeBase(i32).init(testing.allocator);
    defer scope.deinit();

    try testing.expect(scope.lookupPtr("x") == null);
}
