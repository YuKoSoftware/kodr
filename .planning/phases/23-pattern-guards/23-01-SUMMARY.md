---
phase: 23-pattern-guards
plan: 01
subsystem: compiler
tags: [peg-grammar, ast, mir, codegen, resolver, match, pattern-guards]

# Dependency graph
requires:
  - phase: 22-throw-statement
    provides: throw statement pipeline and token_map.zig LITERAL_MAP patterns
provides:
  - parenthesized_pattern PEG grammar rule with guarded and plain alternatives
  - MatchArm.guard field in AST (parser.zig)
  - Guard resolution in child scope in resolver.zig
  - Else-arm enforcement for matches with guards
  - generateGuardedMatchMir codegen path desugaring to if/else chains
  - Runtime tests: match_guard and match_guard_scope
  - Negative test: fail_match_guard.orh
affects: 23-02, codegen, resolver, mir, example-module

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Guarded match arms desugar to labeled Zig blocks: if (_g0: { const x = _m; break :_g0 x > 0; }) { ... }"
    - "Bound variable availability in body detected via mirContainsIdentifier to suppress unused-local-constant errors"
    - "Token scanning (findTokenInRange) used to distinguish guarded vs plain parenthesized_pattern captures, since IDENTIFIER is a terminal and not a sub-rule child"

key-files:
  created:
    - test/fixtures/fail_match_guard.orh
  modified:
    - src/orhon.peg
    - src/parser.zig
    - src/peg/builder.zig
    - src/mir.zig
    - src/resolver.zig
    - src/codegen.zig
    - test/fixtures/tester.orh
    - test/fixtures/tester_main.orh
    - src/templates/example/control_flow.orh
    - test/10_runtime.sh
    - test/11_errors.sh

key-decisions:
  - "Token scanning (findTokenInRange) chosen over findChild(IDENTIFIER) because IDENTIFIER is a terminal token in the PEG grammar, not a named sub-rule that appears as a capture child"
  - "Labeled Zig block chosen for guard desugaring: if (_g0: { const x = _m; break :_g0 guard; }) { ... } — this correctly chains with else-if without leaking scope"
  - "mirContainsIdentifier used at codegen time to conditionally emit '_ = x' suppressor only when body does not reference the bound variable, avoiding both unused-local-constant and pointless-discard errors"
  - "Parenthesized ranges (1..3) required; bare 1..3 syntax migrated in 2 files (4 lines total)"

patterns-established:
  - "Guard resolution: create child Scope with bound variable defined as match_type, resolve guard expr, defer deinit — same pattern as for/while scopes"
  - "Guarded codegen: wrap entire match in { const _m = val; }, then if/else chain per arm"

requirements-completed: [GUARD-01, GUARD-02]

# Metrics
duration: 25min
completed: 2026-03-27
---

# Phase 23 Plan 01: Pattern Guards Summary

**Guard syntax `(x if x > 0) => { ... }` implemented across all six compiler passes: PEG grammar, AST builder, resolver (child scope + else enforcement), MIR annotator/lowerer, and codegen (if/else chain desugaring); existing bare range patterns migrated to parenthesized form.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-27T15:48:12Z
- **Completed:** 2026-03-27T16:07:41Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Pattern guard syntax `(x if guard_expr) => { body }` fully implemented end-to-end
- Guard expression can reference both the bound variable and enclosing scope variables (match_guard_scope test)
- Compiler enforces else arm when any guarded arm is present, with clear error message
- Parenthesized ranges `(1..3) =>` work correctly; bare `1..3 =>` syntax retired
- 259 tests pass (3 new: match_guard, match_guard_scope runtime + 1 negative test)

## Task Commits

1. **Task 1: Grammar, AST, and Builder** - `6f23ef3` (feat)
2. **Task 2: Resolver enforcement and codegen desugaring** - `20289ae` (feat)

## Files Created/Modified

- `src/orhon.peg` - Added parenthesized_pattern rule with guarded and plain alternatives
- `src/parser.zig` - Added guard: ?*Node field to MatchArm struct
- `src/peg/builder.zig` - Updated buildMatchArm to detect guarded patterns via token scanning
- `src/mir.zig` - Added guard() accessor, updated MirAnnotator and MirLowerer
- `src/resolver.zig` - Guard resolution in child scope, else enforcement
- `src/codegen.zig` - generateGuardedMatchMir, hasGuardedArm, mirContainsIdentifier
- `test/fixtures/tester.orh` - Range migration + match_guard/match_guard_scope test functions
- `test/fixtures/tester_main.orh` - Guard test calls with PASS/FAIL output
- `src/templates/example/control_flow.orh` - Range migration + guard example
- `test/10_runtime.sh` - Added match_guard and match_guard_scope test names
- `test/11_errors.sh` - Added fail_match_guard.orh negative test
- `test/fixtures/fail_match_guard.orh` - Negative fixture: guarded match without else

## Decisions Made

- Token scanning with `findTokenInRange` used instead of `findChild("IDENTIFIER")` because IDENTIFIER is a terminal token, not a named sub-rule. Using findChild returned null, causing guards to silently fall through to the plain expr path.
- Labeled Zig block for guard desugaring: `if (_g0: { const x = _m; break :_g0 guard; })` rather than `if (true) { const x = _m; if (guard) body }` — the latter breaks the else-if chain when the inner guard is false.
- `mirContainsIdentifier` used to conditionally suppress unused variable binding in guard body — Zig rejects both "unused local constant" and "pointless discard of local constant" so detection is required.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] findChild("IDENTIFIER") does not work for terminal tokens**
- **Found during:** Task 2 (testing codegen)
- **Issue:** The plan specified `pp.findChild("IDENTIFIER")` to detect guarded patterns. Terminal tokens are not added as named rule children in the capture tree — only named rule_ref matches are. This caused all guarded patterns to fall through to the plain expr path, generating `switch(n) { (x > 0) => ... }` instead of the guarded if/else chain.
- **Fix:** Replaced findChild approach with `findTokenInRange(ctx, pp.start_pos, pp.end_pos, .kw_if)` to detect whether the parenthesized_pattern contains an `if` keyword token. Then scan tokens to extract the bound identifier text.
- **Files modified:** src/peg/builder.zig
- **Verification:** Guard codegen emits labeled block if/else chain; all 259 tests pass

**2. [Rule 1 - Bug] `if (true)` wrapper breaks multi-arm guard else-if chaining**
- **Found during:** Task 2 (correctness testing with x=0 case)
- **Issue:** The plan's proposed `if (true) { const x = _m; if (guard) body }` approach enters the outer `if (true)` block unconditionally. When the inner guard fails, we exit the outer block without reaching the `else if` for the next arm.
- **Fix:** Changed to labeled Zig block: `if (_g0: { const x = _m; break :_g0 guard; }) { ... }`. This produces a bool condition for the outer if, so the else-if chain short-circuits correctly.
- **Files modified:** src/codegen.zig
- **Verification:** match_guard(0) correctly returns 0 (reaches else arm); runtime tests pass

**3. [Rule 1 - Bug] Zig rejects both "unused local constant" and "pointless discard" for bound variable**
- **Found during:** Task 2 (building tester module)
- **Issue:** Always emitting `const x = _m; _ = x;` fails when the body uses `x` (Zig: "pointless discard of local constant"). Not emitting `_ = x;` fails when body doesn't use `x` (Zig: "unused local constant").
- **Fix:** Added `mirContainsIdentifier` helper that walks the body MIR tree to check if the bound variable name appears. Emit `const x = _m;` alone when used, `const x = _m; _ = x;` when unused.
- **Files modified:** src/codegen.zig
- **Verification:** match_guard (body doesn't use x) and match_guard_body_use (body uses x) both compile and run correctly

---

**Total deviations:** 3 auto-fixed (3 x Rule 1 - Bug)
**Impact on plan:** All auto-fixes were necessary for correctness. The plan's proposed implementation details for builder and codegen needed adjustment but the architecture (guard field, child scope, if/else desugaring) was correct.

## Issues Encountered

None beyond the bugs documented above.

## Next Phase Readiness

- Pattern guards fully implemented and tested
- Ready for Phase 23 Plan 02 (if any) or phase transition
- The `#cimport` unified directive is next in the v0.15 milestone

## Self-Check: PASSED

- 23-01-SUMMARY.md: FOUND
- fail_match_guard.orh: FOUND
- commit 6f23ef3: FOUND
- commit 20289ae: FOUND

---
*Phase: 23-pattern-guards*
*Completed: 2026-03-27*
