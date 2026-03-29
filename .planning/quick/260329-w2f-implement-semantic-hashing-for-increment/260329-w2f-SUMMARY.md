---
phase: quick
plan: 260329-w2f
subsystem: cache
tags: [incremental-compilation, hashing, lexer, performance]
dependency_graph:
  requires: []
  provides: [incremental-semantic-hashing]
  affects: [src/cache.zig, src/pipeline.zig]
tech_stack:
  added: []
  patterns: [seed-chaining XxHash3, allocation-free token iteration]
key_files:
  created: []
  modified:
    - src/cache.zig
    - docs/TODO.md
decisions:
  - Use XxHash3 seed-chaining for allocation-free incremental hashing
  - Skip newline and doc_comment tokens only (regular // comments already stripped by lexer)
  - Hash token kind as u16 little-endian bytes plus literal text for value-bearing tokens
metrics:
  duration: ~15 minutes
  completed: 2026-03-29
  tasks: 2
  files: 2
---

# Quick Task 260329-w2f: Semantic Hashing for Incremental Compilation Summary

**One-liner:** XxHash3 seed-chaining on the token stream (newlines + doc comments excluded) replaces raw byte hashing so formatting-only file touches no longer invalidate the incremental cache.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Add hashSemanticContent and update hasChanged/updateHash | d186f12 | src/cache.zig |
| 2 | Full test suite validation + TODO update | aba02c4 | docs/TODO.md |

## What Was Built

### hashSemanticContent (src/cache.zig)

A new public function `hashSemanticContent(source: []const u8) u64` that:

1. Initializes a `lexer.Lexer` directly from the source slice — no allocation.
2. Iterates tokens via `lex.next()` until `.eof`.
3. Skips `.newline` and `.doc_comment` tokens (regular `//` comments are already consumed by `skipWhitespaceAndComments` inside the lexer — they never appear as tokens).
4. For each remaining token, hashes its kind as a `u16` little-endian byte pair using `XxHash3.hash(seed, &kind_bytes)`, using the previous hash as the seed (seed-chaining).
5. For `.identifier`, `.int_literal`, `.float_literal`, `.string_literal` tokens, also hashes the token text to capture value differences.
6. Returns the final accumulated seed.

### Updated hasChanged and updateHash

Both methods now call `hashSemanticContent(content)` instead of `XxHash3.hash(0, content)`.

### Unit Tests Added (4 new tests)

- `semantic hash ignores whitespace` — two sources differing only in blank lines produce equal hashes.
- `semantic hash ignores comments` — source with and without a doc comment produce equal hashes.
- `semantic hash detects code changes` — renaming a function identifier produces a different hash.
- `cache hasChanged with formatting` — write file, `updateHash`, rewrite with extra blank lines and extra spaces, `hasChanged` returns `false`.

## Decisions Made

**XxHash3 seed-chaining over buffer accumulation:** The plan specified this pattern. XxHash3 is one-shot only (`hash(seed, input)`), so chaining via seed avoids a heap-allocated accumulation buffer. No allocation occurs in the hash hot path.

**u16 for kind encoding:** `TokenKind` has enough variants to exceed `u8` range, so the kind is cast to `u16` before splitting into two bytes. This avoids truncation bugs.

**Regular comments already invisible:** `skipWhitespaceAndComments` inside the lexer consumes `//` line comments and `/* */` block comments before producing any token. Only `///` doc comments surface as `.doc_comment` tokens — those are explicitly skipped in `hashSemanticContent`.

## Deviations from Plan

None — plan executed exactly as written.

## Verification

- `zig build test` — all unit tests pass including 4 new semantic hash tests.
- `./testall.sh` — all 269 tests pass across all 11 stages.
- No regressions in incremental compilation or any other pipeline stage.

## Self-Check: PASSED

- `src/cache.zig` exists and contains `hashSemanticContent` — FOUND
- Commit d186f12 exists — FOUND
- Commit aba02c4 exists — FOUND
- All 269 tests pass — VERIFIED
