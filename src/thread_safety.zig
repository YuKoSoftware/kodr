// thread_safety.zig — Thread Safety Analysis pass (pass 8)
// Ensures values moved into threads are not used after spawn.
// Ensures all threads are joined (.value or .wait()) before scope exit.

const std = @import("std");
const parser = @import("parser.zig");
const errors = @import("errors.zig");

/// Tracks which variables have been moved into threads
pub const ThreadSafetyChecker = struct {
    moved_to_thread: std.StringHashMap([]const u8), // var_name → thread_name
    declared_threads: std.StringHashMap(void), // thread names declared in current scope
    joined_threads: std.StringHashMap(void), // thread names that had .value or .wait()
    reporter: *errors.Reporter,
    allocator: std.mem.Allocator,
    locs: ?*const parser.LocMap,
    source_file: []const u8,

    pub fn init(allocator: std.mem.Allocator, reporter: *errors.Reporter) ThreadSafetyChecker {
        return .{
            .moved_to_thread = std.StringHashMap([]const u8).init(allocator),
            .declared_threads = std.StringHashMap(void).init(allocator),
            .joined_threads = std.StringHashMap(void).init(allocator),
            .reporter = reporter,
            .allocator = allocator,
            .locs = null,
            .source_file = "",
        };
    }

    pub fn deinit(self: *ThreadSafetyChecker) void {
        self.moved_to_thread.deinit();
        self.declared_threads.deinit();
        self.joined_threads.deinit();
    }

    fn nodeLoc(self: *const ThreadSafetyChecker, node: *parser.Node) ?errors.SourceLoc {
        if (self.locs) |l| {
            if (l.get(node)) |loc| {
                return .{ .file = self.source_file, .line = loc.line, .col = loc.col };
            }
        }
        return null;
    }

    pub fn check(self: *ThreadSafetyChecker, ast: *parser.Node) !void {
        if (ast.* != .program) return;
        for (ast.program.top_level) |node| {
            try self.checkNode(node);
        }
    }

    fn checkNode(self: *ThreadSafetyChecker, node: *parser.Node) anyerror!void {
        switch (node.*) {
            .func_decl => |f| {
                // Save/restore thread tracking per function
                const prev_declared = self.declared_threads;
                const prev_joined = self.joined_threads;
                const prev_moved = self.moved_to_thread;
                self.declared_threads = std.StringHashMap(void).init(self.allocator);
                self.joined_threads = std.StringHashMap(void).init(self.allocator);
                self.moved_to_thread = std.StringHashMap([]const u8).init(self.allocator);
                defer {
                    self.declared_threads.deinit();
                    self.joined_threads.deinit();
                    self.moved_to_thread.deinit();
                    self.declared_threads = prev_declared;
                    self.joined_threads = prev_joined;
                    self.moved_to_thread = prev_moved;
                }
                try self.checkNode(f.body);
                // Check for unjoined threads at function exit
                try self.checkUnjoinedThreads();
            },
            .block => |b| {
                for (b.statements) |stmt| {
                    try self.checkStatement(stmt);
                }
            },
            .struct_decl => |s| {
                for (s.members) |member| {
                    if (member.* == .func_decl) try self.checkNode(member);
                }
            },
            else => {},
        }
    }

    fn checkStatement(self: *ThreadSafetyChecker, node: *parser.Node) anyerror!void {
        switch (node.*) {
            .thread_block => |t| {
                // Register this thread
                try self.declared_threads.put(t.name, {});

                // Collect all identifiers used in thread body
                // then remove locally declared ones — those aren't captures
                var used_vars: std.StringHashMap(void) = std.StringHashMap(void).init(self.allocator);
                defer used_vars.deinit();
                try self.collectUsedVars(t.body, &used_vars);
                var local_decls: std.StringHashMap(void) = std.StringHashMap(void).init(self.allocator);
                defer local_decls.deinit();
                try collectLocalDecls(t.body, &local_decls);
                var dl = local_decls.iterator();
                while (dl.next()) |le| _ = used_vars.remove(le.key_ptr.*);

                // Mark them as moved into this thread
                var it = used_vars.iterator();
                while (it.next()) |entry| {
                    const var_name = entry.key_ptr.*;

                    // Check if already moved into another thread
                    if (self.moved_to_thread.get(var_name)) |thread_name| {
                        const msg = try std.fmt.allocPrint(self.allocator,
                            "value '{s}' already moved into thread '{s}'",
                            .{ var_name, thread_name });
                        defer self.allocator.free(msg);
                        try self.reporter.report(.{ .message = msg, .loc = self.nodeLoc(node) });
                        continue;
                    }

                    try self.moved_to_thread.put(var_name, t.name);
                }
            },

            .var_decl => |v| {
                // Check if using a value that was moved into a thread
                try self.checkExprForThreadMoves(v.value);
                // Check for .value join via: var x = thread_name.value
                self.checkJoinExpr(v.value);
            },

            .const_decl => |v| {
                try self.checkExprForThreadMoves(v.value);
                // Check for .value join via: const x = thread_name.value
                self.checkJoinExpr(v.value);
            },

            .assignment => |a| {
                try self.checkExprForThreadMoves(a.right);
                // Check for .value join via: x = thread_name.value
                self.checkJoinExpr(a.right);
            },

            .call_expr => |c| {
                // Check for thread_name.wait() call
                if (c.callee.* == .field_expr) {
                    const fe = c.callee.field_expr;
                    if (fe.object.* == .identifier and std.mem.eql(u8, fe.field, "wait")) {
                        if (self.declared_threads.contains(fe.object.identifier)) {
                            try self.joined_threads.put(fe.object.identifier, {});
                        }
                    }
                    if (fe.object.* == .identifier and std.mem.eql(u8, fe.field, "cancel")) {
                        // cancel doesn't count as join — thread still needs .wait() or .value
                    }
                }
                try self.checkExprForThreadMoves(node);
            },

            .return_stmt => |r| {
                if (r.value) |v| {
                    self.checkJoinExpr(v);
                    try self.checkExprForThreadMoves(v);
                }
            },

            .if_stmt => |i| {
                try self.checkExprForThreadMoves(i.condition);
                try self.checkNode(i.then_block);
                if (i.else_block) |e| try self.checkNode(e);
            },

            .while_stmt => |w| {
                try self.checkExprForThreadMoves(w.condition);
                try self.checkNode(w.body);
            },

            .for_stmt => |f| {
                try self.checkExprForThreadMoves(f.iterable);
                try self.checkNode(f.body);
            },

            .block => try self.checkNode(node),

            else => try self.checkExprForThreadMoves(node),
        }
    }

    /// Recursively check if an expression contains thread joins (thread_name.value)
    fn checkJoinExpr(self: *ThreadSafetyChecker, expr: *parser.Node) void {
        switch (expr.*) {
            .field_expr => |fe| {
                if (fe.object.* == .identifier and std.mem.eql(u8, fe.field, "value")) {
                    const name = fe.object.identifier;
                    if (self.declared_threads.contains(name)) {
                        self.joined_threads.put(name, {}) catch {};
                        _ = self.moved_to_thread.remove(name);
                    }
                }
            },
            .binary_expr => |b| {
                self.checkJoinExpr(b.left);
                self.checkJoinExpr(b.right);
            },
            .call_expr => |c| {
                self.checkJoinExpr(c.callee);
                for (c.args) |arg| self.checkJoinExpr(arg);
            },
            else => {},
        }
    }

    /// Error on any threads not joined before scope exit
    fn checkUnjoinedThreads(self: *ThreadSafetyChecker) anyerror!void {
        var it = self.declared_threads.iterator();
        while (it.next()) |entry| {
            const thread_name = entry.key_ptr.*;
            if (!self.joined_threads.contains(thread_name)) {
                const msg = try std.fmt.allocPrint(self.allocator,
                    "thread '{s}' must be joined before scope exit — use .value or .wait()",
                    .{thread_name});
                defer self.allocator.free(msg);
                try self.reporter.report(.{ .message = msg });
            }
        }
    }

    fn checkExprForThreadMoves(self: *ThreadSafetyChecker, node: *parser.Node) anyerror!void {
        switch (node.*) {
            .identifier => |name| {
                if (self.moved_to_thread.get(name)) |thread_name| {
                    const msg = try std.fmt.allocPrint(self.allocator,
                        "use of '{s}' after it was moved into thread '{s}'",
                        .{ name, thread_name });
                    defer self.allocator.free(msg);
                    try self.reporter.report(.{ .message = msg, .loc = self.nodeLoc(node) });
                }
            },
            .binary_expr => |b| {
                try self.checkExprForThreadMoves(b.left);
                try self.checkExprForThreadMoves(b.right);
            },
            .call_expr => |c| {
                try self.checkExprForThreadMoves(c.callee);
                for (c.args) |arg| try self.checkExprForThreadMoves(arg);
            },
            .field_expr => |f| try self.checkExprForThreadMoves(f.object),
            .index_expr => |i| {
                try self.checkExprForThreadMoves(i.object);
                try self.checkExprForThreadMoves(i.index);
            },
            .slice_expr => |s| {
                try self.checkExprForThreadMoves(s.object);
                try self.checkExprForThreadMoves(s.low);
                try self.checkExprForThreadMoves(s.high);
            },
            else => {},
        }
    }

    fn collectUsedVars(self: *ThreadSafetyChecker, node: *parser.Node, vars: *std.StringHashMap(void)) anyerror!void {
        switch (node.*) {
            .identifier => |name| try vars.put(name, {}),
            .block => |b| {
                for (b.statements) |stmt| try self.collectUsedVars(stmt, vars);
            },
            .binary_expr => |b| {
                try self.collectUsedVars(b.left, vars);
                try self.collectUsedVars(b.right, vars);
            },
            .call_expr => |c| {
                // Only capture callee if method call (field_expr), not plain function name
                if (c.callee.* == .field_expr) try self.collectUsedVars(c.callee, vars);
                for (c.args) |arg| try self.collectUsedVars(arg, vars);
            },
            .return_stmt => |r| {
                if (r.value) |v| try self.collectUsedVars(v, vars);
            },
            .var_decl => |v| try self.collectUsedVars(v.value, vars),
            .field_expr => |f| try self.collectUsedVars(f.object, vars),
            else => {},
        }
    }

    /// Collect locally declared variable names in a body
    fn collectLocalDecls(node: *parser.Node, decls: *std.StringHashMap(void)) anyerror!void {
        switch (node.*) {
            .block => |b| {
                for (b.statements) |stmt| try collectLocalDecls(stmt, decls);
            },
            .var_decl => |v| try decls.put(v.name, {}),
            .const_decl => |v| try decls.put(v.name, {}),
            .if_stmt => |i| {
                try collectLocalDecls(i.then_block, decls);
                if (i.else_block) |e| try collectLocalDecls(e, decls);
            },
            .while_stmt => |w| try collectLocalDecls(w.body, decls),
            .for_stmt => |f| {
                for (f.captures) |cap| try decls.put(cap, {});
                if (f.index_var) |idx| try decls.put(idx, {});
                try collectLocalDecls(f.body, decls);
            },
            else => {},
        }
    }
};

test "thread safety - use after move into thread" {
    const alloc = std.testing.allocator;
    var reporter = errors.Reporter.init(alloc, .debug);
    defer reporter.deinit();

    var checker = ThreadSafetyChecker.init(alloc, &reporter);
    defer checker.deinit();

    // Simulate: data moved into thread, then used after
    try checker.moved_to_thread.put("data", "my_thread");

    var id = parser.Node{ .identifier = "data" };
    try checker.checkExprForThreadMoves(&id);
    try std.testing.expect(reporter.hasErrors());
}

test "thread safety - clean state" {
    const alloc = std.testing.allocator;
    var reporter = errors.Reporter.init(alloc, .debug);
    defer reporter.deinit();

    var checker = ThreadSafetyChecker.init(alloc, &reporter);
    defer checker.deinit();

    var id = parser.Node{ .identifier = "x" };
    try checker.checkExprForThreadMoves(&id);
    try std.testing.expect(!reporter.hasErrors());
}

test "thread safety - unjoined thread is error" {
    const alloc = std.testing.allocator;
    var reporter = errors.Reporter.init(alloc, .debug);
    defer reporter.deinit();

    var checker = ThreadSafetyChecker.init(alloc, &reporter);
    defer checker.deinit();

    // Simulate: thread declared but not joined
    try checker.declared_threads.put("worker", {});
    try checker.checkUnjoinedThreads();
    try std.testing.expect(reporter.hasErrors());
}

test "thread safety - joined thread is ok" {
    const alloc = std.testing.allocator;
    var reporter = errors.Reporter.init(alloc, .debug);
    defer reporter.deinit();

    var checker = ThreadSafetyChecker.init(alloc, &reporter);
    defer checker.deinit();

    // Simulate: thread declared and joined
    try checker.declared_threads.put("worker", {});
    try checker.joined_threads.put("worker", {});
    try checker.checkUnjoinedThreads();
    try std.testing.expect(!reporter.hasErrors());
}
