// LSP test wrapper — collects test blocks from all LSP modules.
// Zig runs @import inside a `test { ... }` block as part of the test suite.

test {
    _ = @import("lsp/lsp.zig");
    _ = @import("lsp/lsp_analysis.zig");
    _ = @import("lsp/lsp_edit.zig");
    _ = @import("lsp/lsp_json.zig");
    _ = @import("lsp/lsp_nav.zig");
    _ = @import("lsp/lsp_semantic.zig");
    _ = @import("lsp/lsp_types.zig");
    _ = @import("lsp/lsp_utils.zig");
    _ = @import("lsp/lsp_view.zig");
}
