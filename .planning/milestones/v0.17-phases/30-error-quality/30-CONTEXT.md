# Phase 30: Error Quality - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Enhance compiler error messages across all passes with actionable guidance: typo suggestions via Levenshtein distance, standardized type mismatch display, and ownership/borrow/thread fix hints. No new language features — only better error output.

</domain>

<decisions>
## Implementation Decisions

### Suggestion Algorithm
- **D-01:** Use Levenshtein edit distance for "did you mean?" candidate ranking. Threshold of 2-3 edits covers most typos.
- **D-02:** Show 1 best match only — "did you mean 'count'?" Single suggestion, no alternatives list.
- **D-03:** Search current scope only — local vars, function params, and module-level declarations. No cross-module search.
- **D-04:** Cover all identifier types — variables, functions, types, enum variants. Anything in the declaration table gets suggestions.

### Error Message Format
- **D-05:** Suggestions appear inline in the error message — "unknown identifier 'coutn' — did you mean 'count'?" Single line, compact. Do not use the `notes` field.
- **D-06:** Standardize "expected X, got Y" pattern across all passes for type mismatches. Consistent developer experience.
- **D-07:** Use short type names by default — "expected i32, got f64" not "expected core.i32, got core.f64". Only qualify when ambiguous.

### Ownership/Borrow Hints
- **D-08:** Move-after-use errors suggest: "consider using copy()" — direct, actionable, points to Orhon's copy mechanism.
- **D-09:** Borrow violations suggest: "consider borrowing with const &" — when the usage is read-only and a const borrow would resolve it.
- **D-10:** Thread safety violations use generic hint: "shared mutable state requires synchronization" — points to the problem without prescribing a specific solution.

### Scope of Coverage
- **D-11:** Enhance all passes: resolver (26 sites), declarations (10), propagation (5), borrow (4), ownership (3), thread_safety (3). Complete coverage.
- **D-12:** Levenshtein function lives in errors.zig — all passes already import it, minimizes change surface.
- **D-13:** Add integration tests in test/11_errors.sh verifying "did you mean" and enhanced messages appear in compiler output. Also unit tests for Levenshtein in errors.zig.

### Claude's Discretion
- Exact Levenshtein distance threshold (2 vs 3 edits) — tune based on typical Orhon identifier lengths
- Which specific error sites get suggestions vs which stay as-is (not all errors have reasonable suggestions)
- Exact wording of hints beyond the patterns decided above

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Error Infrastructure
- `src/errors.zig` — Reporter struct, OrhonError, SourceLoc, flush() formatting. Levenshtein goes here.
- `src/sema.zig` — SemanticContext shared by passes 6-9, provides nodeLoc() for error locations.

### Error Report Sites (by pass)
- `src/resolver.zig` — 26 report sites. Already has "expected '{s}', got '{s}'" pattern (lines 376, 1002).
- `src/declarations.zig` — 10 report sites. Declaration collection errors.
- `src/propagation.zig` — 5 report sites. Error propagation checking.
- `src/borrow.zig` — 4 report sites. Borrow violation errors.
- `src/ownership.zig` — 3 report sites. Move-after-use errors.
- `src/thread_safety.zig` — 3 report sites. Thread safety violations.

### Testing
- `test/11_errors.sh` — Negative tests (expected compilation failures). New test cases go here.
- `test/fixtures/` — Test fixture .orh files.

### Requirements
- `.planning/REQUIREMENTS.md` — ERR-01 (did you mean), ERR-02 (type mismatch display), ERR-03 (ownership/borrow hints)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `OrhonError.notes` field exists but won't be used — suggestions go inline in message (D-05)
- `DeclTable` in declarations.zig already stores all identifiers by name — natural candidate pool for Levenshtein search
- resolver.zig already implements "expected '{s}', got '{s}'" — can be used as the template for standardization

### Established Patterns
- All error reporting goes through `reporter.report(.{ .message = msg, .loc = loc })` with caller-allocated strings
- `defer self.allocator.free(msg)` after every `allocPrint` for error messages
- Error messages are plain strings — no structured formatting beyond what allocPrint provides

### Integration Points
- errors.zig is imported by every pass — adding Levenshtein there requires no new imports
- Each pass has access to declarations/DeclTable for identifier lookups
- SemanticContext (sema.zig) provides nodeLoc() for resolving source locations

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard approaches per decisions above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 30-error-quality*
*Context gathered: 2026-03-28*
