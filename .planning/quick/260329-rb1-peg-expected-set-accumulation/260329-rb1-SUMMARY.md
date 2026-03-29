---
phase: quick-260329-rb1
plan: 01
subsystem: peg-engine
tags: [cleanup, peg, error-messages, enum-set]
dependency_graph:
  requires: []
  provides: [EnumSet-based PEG expected-token tracking]
  affects: [src/peg/engine.zig, src/module.zig, src/commands.zig]
tech_stack:
  added: []
  patterns: [std.EnumSet(TokenKind) for automatic deduplication, EnumSet.iterator() for ordered iteration]
key_files:
  modified:
    - src/peg/engine.zig
    - src/module.zig
    - src/commands.zig
decisions:
  - "Use std.EnumSet(TokenKind) for expected token accumulation — automatic dedup, no overflow, ~20 lines fewer than manual approach"
metrics:
  duration: "5m"
  completed: "2026-03-29"
  tasks: 2
  files: 3
---

# Quick Task 260329-rb1: PEG Expected Set Accumulation — SUMMARY

**One-liner:** Replaced manual `[64]TokenKind` buffers with `std.EnumSet(TokenKind)` in PEG engine for automatic deduplication and overflow-free expected-token tracking.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace fixed arrays with EnumSet in engine.zig | dc47eae | src/peg/engine.zig |
| 2 | Update consumers — module.zig and commands.zig | 4646766 | src/module.zig, src/commands.zig |

## What Changed

### engine.zig
- `ParseError.expected_set` field changed from `[]const TokenKind` to `std.EnumSet(TokenKind)`
- Engine struct: removed 4 fields (`furthest_expected_buf[64]`, `furthest_expected_len`, `expected_set_buf[64]`, `expected_set_len`) — replaced by single `furthest_expected: std.EnumSet(TokenKind)`
- `trackFailure`: simplified to EnumSet `insert()` and `initEmpty()` — no manual bounds check needed
- `getError`: dedup loop removed entirely — EnumSet is already deduplicated; returns `self.furthest_expected` directly
- Tests updated: `.len` → `.count()`, slice indexing → `.contains()`, for-loop → EnumSet `.iterator()`

### module.zig
- `formatExpectedSet` signature: `[]const lexer.TokenKind` → `std.EnumSet(lexer.TokenKind)`
- Body uses `.count()` and `.iterator()` instead of slice length and index
- Call site: `.len > 1` → `.count() > 1`

### commands.zig
- Analysis error display loop changed from `for (err.expected_set, 0..) |kind, i|` to EnumSet iterator pattern

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- dc47eae present: confirmed
- 4646766 present: confirmed
- src/peg/engine.zig modified: confirmed (no `[64]TokenKind` buffers remain)
- src/module.zig modified: confirmed
- src/commands.zig modified: confirmed
- All 269 tests pass: confirmed
