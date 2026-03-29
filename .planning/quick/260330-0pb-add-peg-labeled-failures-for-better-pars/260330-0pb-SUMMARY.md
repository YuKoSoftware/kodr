---
phase: quick-260330-0pb
plan: 01
subsystem: peg-parser
tags: [peg, error-messages, grammar, developer-experience]
dependency_graph:
  requires: []
  provides: [labeled-grammar-rules, human-readable-parse-errors]
  affects: [src/peg/grammar.zig, src/peg/engine.zig, src/peg/orhon.peg, src/module.zig]
tech_stack:
  added: []
  patterns: [grammar-annotation, label-propagation]
key_files:
  created: []
  modified:
    - src/peg/grammar.zig
    - src/peg/engine.zig
    - src/peg/orhon.peg
    - src/module.zig
decisions:
  - Label syntax uses {label: "text"} after rule body — no conflicts with PEG atoms since { is not a valid PEG expression start
  - Labels inserted between kw_var special case and expected_set multi-token fallback for natural priority
  - Only unlabeled positions fall through to existing token-set formatting (backward compatible)
metrics:
  duration: ~10 minutes
  completed: "2026-03-29T21:38:25Z"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 4
---

# Phase quick-260330-0pb Plan 01: PEG Labeled Failures Summary

**One-liner:** Human-readable parse error labels via {label: "..."} grammar annotations propagated through Engine.ParseError to module.zig error formatting.

## What Was Built

Parse errors for labeled grammar rules now display messages like `expected function declaration, found 'foo'` instead of raw rule names or generic "unexpected" messages.

Three layers were implemented:

1. **Grammar layer** (`src/peg/grammar.zig`): Added `labels: std.StringHashMapUnmanaged(?[]const u8)` field to `Grammar` and `GrammarParser`. Added `getLabel()` method. Added `tryParseLabel()` method that parses `{label: "text"}` annotations appearing after rule bodies. Labels are arena-allocated alongside all other grammar data.

2. **Engine layer** (`src/peg/engine.zig`): Added `furthest_label: ?[]const u8` field to `Engine`. When `matchRule()` tracks the furthest failure, it now also calls `grammar.getLabel(rule_name)` and stores the result. Added `label` field to `ParseError` struct, included in `getError()`.

3. **Grammar rules** (`src/peg/orhon.peg`): Added `{label: "..."}` annotations to 14 key rules: `module_decl`, `import_decl`, `func_decl`, `struct_decl`, `enum_decl`, `const_decl`, `var_decl`, `block`, `return_stmt`, `if_stmt`, `while_stmt`, `for_stmt`, `match_stmt`, `type`.

4. **Error formatting** (`src/module.zig`): Added label branch in parse error formatting — when `err_info.label` is non-null, formats as `"expected {label}, found '{found}'"`. Inserted after the `kw_var` special case and before the `expected_set.count() > 1` fallback.

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add label storage to Grammar | 3f2e2ca | src/peg/grammar.zig |
| 2 | Propagate labels through Engine | 720ac7c | src/peg/engine.zig, src/module.zig |
| 3 | Add labels to grammar rules | 3e9d27f | src/peg/orhon.peg |

## Verification

- `zig build test` passes (unit tests including 2 new label tests)
- `./testall.sh` passes all 11 stages — all 269 tests pass
- Existing "parse full orhon grammar" test continues passing (label syntax does not break grammar parsing)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- src/peg/grammar.zig exists and contains `labels` field
- src/peg/engine.zig exists and contains `furthest_label` field
- src/peg/orhon.peg exists and contains `{label:` annotations
- src/module.zig exists and contains `furthest_label` usage
- Commits 3f2e2ca, 720ac7c, 3e9d27f all exist in git log
