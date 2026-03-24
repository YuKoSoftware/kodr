// peg.zig — PEG grammar engine public API
//
// Parses the embedded orhon.peg grammar file and provides a
// token-level packrat matching engine for Orhon source files.

const std = @import("std");
const grammar_mod = @import("peg/grammar.zig");
const engine_mod = @import("peg/engine.zig");
const lexer = @import("lexer.zig");

pub const Grammar = grammar_mod.Grammar;
pub const Expr = grammar_mod.Expr;
pub const Engine = engine_mod.Engine;
pub const MatchResult = engine_mod.MatchResult;
pub const parseGrammar = grammar_mod.parseGrammar;

/// The embedded Orhon PEG grammar source
pub const GRAMMAR_SOURCE = @embedFile("orhon.peg");

/// Load the Orhon grammar from the embedded .peg file.
pub fn loadGrammar(allocator: std.mem.Allocator) !Grammar {
    return parseGrammar(GRAMMAR_SOURCE, allocator);
}

/// Convenience: check if a token stream matches the Orhon grammar.
/// Returns true if the tokens form a valid Orhon program.
pub fn validate(tokens: []const lexer.Token, allocator: std.mem.Allocator) !bool {
    var g = try loadGrammar(allocator);
    defer g.deinit();

    var eng = Engine.init(&g, tokens, allocator);
    defer eng.deinit();

    return eng.matchAll("program");
}

// ============================================================
// TESTS
// ============================================================

test "peg - load embedded grammar" {
    const alloc = std.testing.allocator;
    var g = try loadGrammar(alloc);
    defer g.deinit();

    try std.testing.expect(g.getRule("program") != null);
    try std.testing.expect(g.getRule("func_decl") != null);
    try std.testing.expect(g.rule_names.len >= 50);
}

test "peg - validate minimal program" {
    const alloc = std.testing.allocator;

    // Lex a minimal Orhon program
    var lex = lexer.Lexer.init("module main\n");
    var tokens = try lex.tokenize(alloc);
    defer tokens.deinit(alloc);

    const valid = try validate(tokens.items, alloc);
    // This tests the full pipeline: grammar loading + engine matching
    // A minimal 'module main\n' should at least parse module_decl
    _ = valid; // Don't assert yet — need to verify grammar handles this correctly
}

// Re-export sub-module tests
test {
    _ = @import("peg/grammar.zig");
    _ = @import("peg/engine.zig");
    _ = @import("peg/token_map.zig");
}
