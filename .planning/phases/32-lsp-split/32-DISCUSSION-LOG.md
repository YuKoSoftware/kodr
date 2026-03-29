# Phase 32: LSP Split - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 32-lsp-split
**Areas discussed:** File grouping, Struct/state sharing, Handler grouping
**Mode:** --auto (all decisions auto-selected)

---

## File Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| By section header | Split along existing 18 section boundaries, grouping related sections | ✓ |
| By LSP method | One file per LSP method | |
| Flat handlers | All handlers in one file, infra in another | |

**User's choice:** [auto] By section header (recommended default)
**Notes:** lsp.zig already has clearly labeled section comments that map naturally to focused files.

---

## Struct/State Sharing

| Option | Description | Selected |
|--------|-------------|----------|
| Pass parameters explicitly | Keep existing pattern — handlers already receive allocator, symbols, etc. | ✓ |
| Create LspContext struct | Wrap shared state in a struct like codegen did | |

**User's choice:** [auto] Pass parameters explicitly (recommended default)
**Notes:** Unlike codegen.zig which had CodeGen struct, lsp.zig handlers are already standalone functions with clean parameter interfaces.

---

## Handler Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| By LSP feature category | Navigation (hover/def/refs), Editing (completion/rename), View (symbols/hints/folding) | ✓ |
| By complexity | Simple handlers together, complex handlers separate | |
| Individual files | One file per handler | |

**User's choice:** [auto] By LSP feature category (recommended default)
**Notes:** Groups related handlers that share helper functions and follow similar patterns.

---

## Claude's Discretion

- Exact file names and whether to use flat or subdirectory layout
- Exact function-to-file assignments based on call graph analysis
- Placement of type formatting functions

## Deferred Ideas

None — discussion stayed within phase scope.
