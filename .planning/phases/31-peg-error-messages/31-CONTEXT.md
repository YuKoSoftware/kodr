# Phase 31: PEG Error Messages - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Improve PEG parse error messages so that when alternatives fail at the same token position, the error shows ALL expected tokens (e.g., "expected `func`, `struct`, or `enum`") instead of just the last one tried. Pure engine-level change — no new syntax, no new language features.

</domain>

<decisions>
## Implementation Decisions

### Error Message Format
- **D-01:** Multiple expected tokens formatted as comma-separated list with "or" before last: `expected 'func', 'struct', or 'enum'`
- **D-02:** Single expected token keeps current format: `unexpected 'foo'` (no regression)

### Expected Set Representation
- **D-03:** Use a bounded array of `TokenKind` values in the Engine struct (no heap allocation needed — `TokenKind` enum is finite and small)
- **D-04:** Reset the expected set when `furthest_pos` advances (new position = new set)
- **D-05:** Append to the expected set when `furthest_pos` matches current failure position (same position = accumulate alternatives)

### Deduplication Strategy
- **D-06:** Deduplicate at reporting time in `getError()`, not during accumulation — keeps `trackFailure` hot path simple

### Claude's Discretion
- Exact bounded array size (can be generous — 32 or 64 entries covers all practical cases)
- Whether to expose the expected set as a slice in `ParseError` or format it directly in `getError()`
- Token display names (use `@tagName` or a human-readable mapping if one exists)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PEG Engine
- `src/peg/engine.zig` — Current engine with `trackFailure()`, `getError()`, `evalChoice()`, `furthest_pos/expected/rule` fields
- `src/peg/grammar.zig` — Grammar types, `Expr` union (`.choice` variant is where alternatives are defined)

### Error Consumers
- `src/module.zig` lines ~440-464 — Where parse errors are reported via `getError()` and formatted for the user
- `src/main.zig` lines ~770-778 — `orhon analysis` command error output using `getError()`

### Tests
- `test/11_errors.sh` — Existing parse error tests that must continue passing

### Requirements
- `.planning/REQUIREMENTS.md` — PEG-01 requirement definition

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Engine.trackFailure()` — Already tracks furthest failure position; needs extension to accumulate a set instead of overwriting a single value
- `Engine.getError()` — Already constructs `ParseError` struct; extend to include expected set
- `ParseError` struct — Already has `expected_rule` field; add expected token set

### Established Patterns
- Engine uses no heap allocation for error tracking (all stack/struct fields) — expected set should follow this pattern
- `@tagName(TokenKind)` used throughout for token display (e.g., `src/main.zig:773`)
- Error messages caller-allocated with `allocPrint`, then `defer free` — this pattern applies to formatting the expected set in consumers

### Integration Points
- `Engine.getError()` is the sole interface — two call sites: `module.zig` and `main.zig`
- `ParseError` struct is re-exported via `src/peg.zig:18`
- `evalChoice()` already iterates alternatives — no change needed there (trackFailure inside matchToken handles accumulation)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 31-peg-error-messages*
*Context gathered: 2026-03-28*
