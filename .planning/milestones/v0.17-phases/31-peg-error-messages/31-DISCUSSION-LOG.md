# Phase 31: PEG Error Messages - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 31-peg-error-messages
**Areas discussed:** Error message format, Expected set representation, Deduplication strategy
**Mode:** auto (all decisions auto-selected)

---

## Error Message Format

| Option | Description | Selected |
|--------|-------------|----------|
| Comma-separated with 'or' | `expected 'func', 'struct', or 'enum'` — standard compiler convention | yes |
| Space-separated | `expected func struct enum` — terse | |
| Bullet list | Multi-line listing — verbose | |

**User's choice:** [auto] Comma-separated with 'or' before last (recommended default)
**Notes:** Matches GCC, Clang, Rust compiler error conventions

---

## Expected Set Representation

| Option | Description | Selected |
|--------|-------------|----------|
| Bounded array of TokenKind | Stack-allocated, no heap needed, finite enum | yes |
| ArrayList of TokenKind | Heap-allocated, unlimited | |
| Bitset over TokenKind | Compact but harder to iterate for display | |

**User's choice:** [auto] Bounded array of TokenKind (recommended default)
**Notes:** Engine currently uses no heap allocation for error tracking — bounded array maintains this pattern

---

## Deduplication Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| At reporting time | Deduplicate in getError() — keeps trackFailure fast | yes |
| During accumulation | Check before appending — slower hot path | |
| Bitset (implicit dedup) | No duplicates possible but different data structure | |

**User's choice:** [auto] At reporting time in getError() (recommended default)
**Notes:** trackFailure is called frequently during parsing; keeping it minimal is preferred

---

## Claude's Discretion

- Bounded array size, token display names, ParseError struct design details

## Deferred Ideas

None
