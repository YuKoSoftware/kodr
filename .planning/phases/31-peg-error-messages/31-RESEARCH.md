# Phase 31: PEG Error Messages - Research

**Researched:** 2026-03-28
**Domain:** PEG packrat engine — error tracking and message formatting
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Multiple expected tokens formatted as comma-separated list with "or" before last: `expected 'func', 'struct', or 'enum'`
- **D-02:** Single expected token keeps current format: `unexpected 'foo'` (no regression)
- **D-03:** Use a bounded array of `TokenKind` values in the Engine struct (no heap allocation needed — `TokenKind` enum is finite and small)
- **D-04:** Reset the expected set when `furthest_pos` advances (new position = new set)
- **D-05:** Append to the expected set when `furthest_pos` matches current failure position (same position = accumulate alternatives)
- **D-06:** Deduplicate at reporting time in `getError()`, not during accumulation — keeps `trackFailure` hot path simple

### Claude's Discretion
- Exact bounded array size (can be generous — 32 or 64 entries covers all practical cases)
- Whether to expose the expected set as a slice in `ParseError` or format it directly in `getError()`
- Token display names (use `@tagName` or a human-readable mapping if one exists)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PEG-01 | PEG expected-set accumulation — when alternatives fail at the same position, show all expected tokens instead of just one | Engine struct extension (D-03 through D-06), message formatting in consumers (module.zig line 455, main.zig line 772) |
</phase_requirements>

---

## Summary

Phase 31 is a targeted extension to `src/peg/engine.zig`. The engine currently tracks a single `furthest_expected: TokenKind` field that gets overwritten whenever `trackFailure` is called at the same or further position. The fix replaces this single value with a bounded array that accumulates all expected tokens at the furthest failure position, then formats them as a comma-separated list with "or" before the last element.

The change touches four things: (1) the `Engine` struct fields, (2) `trackFailure()` accumulation logic, (3) `ParseError` struct to carry the set, and (4) the two consumer call sites in `module.zig` and `main.zig` that format the message for the user. The existing error format in `module.zig` already has a special case for `kw_var` that must remain untouched — only the generic `unexpected 'foo'` branch needs upgrading.

All existing parse error tests in `test/11_errors.sh` test for specific strings like `"module-level.*var.*not allowed"`, `"var &T.*not valid"`, or `"unexpected"` — none of them assert that only one token name appears, so improved messages are backward compatible with all current checks.

**Primary recommendation:** Extend `Engine` with a 64-entry bounded `TokenKind` array; accumulate in `trackFailure`; deduplicate and format in a new helper `formatExpectedSet` called from `getError()` consumers.

---

## Standard Stack

This phase uses no new libraries. All implementation is in existing Zig standard library primitives.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Zig stdlib | 0.15.2 | Bounded arrays, string formatting, deduplication | Project-wide constraint — no external deps |

### Supporting
| Construct | Purpose | When to Use |
|-----------|---------|-------------|
| `std.BoundedArray(TokenKind, 64)` | Fixed-capacity accumulator for expected token kinds | D-03 — no heap, fits in Engine struct, covers all grammar alternatives |
| `std.fmt.allocPrint` | Format the final message string | Existing pattern in both consumer call sites |
| `@tagName(TokenKind)` | Get token display name string | Already used at `main.zig:773` — consistent with codebase |

**Installation:** No packages to install.

---

## Architecture Patterns

### Engine Struct Extension

The `Engine` struct currently has three error-tracking fields:

```zig
// Current (engine.zig lines 75-77)
furthest_pos: usize = 0,
furthest_rule: []const u8 = "",
furthest_expected: TokenKind = .eof,
```

Replace `furthest_expected` with a `BoundedArray`:

```zig
// New shape
furthest_pos: usize = 0,
furthest_rule: []const u8 = "",
furthest_expected: std.BoundedArray(TokenKind, 64) = .{},
```

`std.BoundedArray` is a stack-allocated array with a runtime length field. It requires no allocator. Zero-initialization is `.{}`.

### trackFailure Extension

Current `trackFailure` (engine.zig lines 182-187):

```zig
fn trackFailure(self: *Engine, pos: usize, expected: TokenKind) void {
    if (pos >= self.furthest_pos) {
        self.furthest_pos = pos;
        self.furthest_expected = expected;
    }
}
```

New shape applying D-04 and D-05:

```zig
fn trackFailure(self: *Engine, pos: usize, expected: TokenKind) void {
    if (pos > self.furthest_pos) {
        // New furthest position — reset set (D-04)
        self.furthest_pos = pos;
        self.furthest_expected = .{};
        self.furthest_expected.append(expected) catch {};
    } else if (pos == self.furthest_pos) {
        // Same position — accumulate (D-05)
        self.furthest_expected.append(expected) catch {};
    }
    // pos < self.furthest_pos: ignore — already have a better position
}
```

Note: the original used `pos >= furthest_pos` which also updated `furthest_rule` on tie. The new version keeps tie semantics for `furthest_rule` (update on `>`) but accumulates tokens on `==`. The `furthest_rule` update can be left on `>=` to keep the same behavior.

### ParseError Extension

Current `ParseError` (engine.zig lines 60-67):

```zig
pub const ParseError = struct {
    pos: usize,
    line: usize,
    col: usize,
    found: []const u8,
    found_kind: TokenKind,
    expected_rule: []const u8,
};
```

Two implementation options for Claude's discretion:

**Option A (Recommended):** Add a `expected_set` slice field — lets consumers format it however they need:

```zig
pub const ParseError = struct {
    pos: usize,
    line: usize,
    col: usize,
    found: []const u8,
    found_kind: TokenKind,
    expected_rule: []const u8,
    expected_set: []const TokenKind, // deduplicated set, points into Engine-owned storage
};
```

`getError()` deduplicates into a small local array, stores it in the Engine struct (or returns a slice into a locally-owned buffer), and returns. Since `getError()` is called once after a failed parse and `Engine` outlives `ParseError`, pointing into a field on Engine is safe.

**Option B:** Format directly in `getError()` using an allocator — inconsistent with the existing no-allocation `getError()` signature; avoid.

**Recommended:** Option A. Add `expected_set_buf: [64]TokenKind` to `Engine` (parallel to `furthest_expected`) for `getError()` to write deduplicated results into. `ParseError.expected_set` is a slice into that buffer.

### Deduplication in getError()

Applying D-06 — deduplicate at reporting time:

```zig
// Inside getError(), before constructing ParseError
var deduped: [64]TokenKind = undefined;
var count: usize = 0;
for (self.furthest_expected.slice()) |kind| {
    var found = false;
    for (deduped[0..count]) |existing| {
        if (existing == kind) { found = true; break; }
    }
    if (!found) {
        deduped[count] = kind;
        count += 1;
    }
}
// Store into engine field so the slice remains valid
@memcpy(self.expected_set_buf[0..count], deduped[0..count]);
```

### Consumer Message Formatting

Two call sites need updating:

**`src/module.zig` lines 448-455** — current:

```zig
const msg = if (err_info.found_kind == .kw_var) blk: {
    // special case for var &T
    ...
} else try std.fmt.allocPrint(alloc, "unexpected '{s}'", .{err_info.found});
```

New (only the `else` branch changes):

```zig
} else if (err_info.expected_set.len > 1) blk: {
    // format: expected 'func', 'struct', or 'enum' (D-01)
    break :blk try formatExpectedSet(alloc, err_info.expected_set);
} else try std.fmt.allocPrint(alloc, "unexpected '{s}'", .{err_info.found});
```

`formatExpectedSet` is a small free function (can live in `peg.zig` or inline in the consumer):

```zig
fn formatExpectedSet(alloc: std.mem.Allocator, set: []const TokenKind) ![]u8 {
    // Single item: falls through to caller (not called for len==1)
    // Two items: "expected 'A' or 'B'"
    // Three+: "expected 'A', 'B', or 'C'"
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    try buf.appendSlice("expected ");
    for (set, 0..) |kind, i| {
        if (i > 0 and set.len > 2) try buf.appendSlice(", ");
        if (i > 0 and i == set.len - 1) try buf.appendSlice(" or ");
        try buf.writer().print("'{s}'", .{@tagName(kind)});
    }
    return buf.toOwnedSlice();
}
```

Wait — this helper uses heap allocation. It should be called with `alloc` and the result stored then `defer free`'d exactly like the existing `msg` pattern. This is consistent with codebase conventions.

**`src/main.zig` lines 771-774** — the `orhon analysis` command:

```zig
// Current
std.debug.print("error at line {d}:{d} — unexpected '{s}' ({s})\n", .{
    err.line, err.col, err.found, @tagName(err.found_kind),
});

// New (when set.len > 1)
// Either: inline the expected set, or call the same helper
```

This call site uses `std.debug.print` with no allocator available in scope. Options:
1. Pass the existing `allocator` from the function scope (it's in scope at line 772 — read `main.zig` to confirm).
2. Format the expected set separately before printing.

**Important:** Check whether `allocator` is in scope at line 772. If yes, use the same helper. If not, fall back to printing `@tagName` of the first token only (this path is only for `orhon analysis` debugging, not production error output).

### Anti-Patterns to Avoid
- **Deduplicating in `trackFailure`:** Hot path — linear scan on every token failure. D-06 explicitly rejects this.
- **Heap allocation in `trackFailure` or `getError` without an allocator:** Engine has no allocator field; `getError` takes no allocator. Use bounded arrays throughout.
- **Printing raw `TokenKind` tag names without stripping `kw_` prefix:** `@tagName(.kw_func)` returns `"kw_func"`, not `"func"`. For display, either write a `kindDisplayName` helper that strips the `kw_` prefix, or use the `.text` from the token (but `.text` is the found token, not expected). Consider: `"expected 'func'"` is cleaner than `"expected 'kw_func'"`. This is a discretion item — add a display name helper or map.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fixed-size accumulator | Custom array struct with length counter | `std.BoundedArray(TokenKind, N)` | Already in Zig stdlib, exactly right fit |
| String building for the list | Manual buffer arithmetic | `std.ArrayList(u8)` + `writer()` | Standard Zig pattern for dynamic string building |

---

## Common Pitfalls

### Pitfall 1: `furthest_expected` reset condition
**What goes wrong:** Using `pos >= furthest_pos` for both the reset and the `furthest_rule` update, but only resetting the array on `>` and accumulating on `==`. If you accidentally reset on `==`, you lose all previously accumulated alternatives at the same position.
**Why it happens:** The original code used `>=` for everything. Splitting into `>` vs `==` is the new invariant.
**How to avoid:** Be explicit — two separate branches in `trackFailure`. Test with a two-alternative choice that fails at position 0.
**Warning signs:** Error message shows only one token even for a multi-alternative choice.

### Pitfall 2: `kw_` prefix in token display names
**What goes wrong:** `@tagName(.kw_func)` returns `"kw_func"`, producing `"expected 'kw_func'"` which is confusing to users.
**Why it happens:** `@tagName` returns the Zig enum variant name verbatim.
**How to avoid:** Write a `kindDisplayName(kind: TokenKind) []const u8` helper that strips `kw_` prefix and maps special cases (`.identifier` → `"identifier"`, `.newline` → `"newline"`, `.eof` → `"end of file"`).
**Warning signs:** Error messages contain `kw_`, `int_literal` instead of readable token names.

### Pitfall 3: ParseError.expected_set pointing into freed memory
**What goes wrong:** If `expected_set` is a slice into a local buffer inside `getError()`, the slice is invalid as soon as `getError()` returns.
**Why it happens:** Returning a slice of a stack-local array.
**How to avoid:** Store the deduplicated buffer as a field on `Engine` (e.g. `expected_set_buf: [64]TokenKind` and `expected_set_len: u8`). `getError()` writes into it before returning a slice.
**Warning signs:** Segfault or garbage data when consumers read `err.expected_set`.

### Pitfall 4: test/11_errors.sh "module-level var" test
**What goes wrong:** The `neg_syntax` test runs `fail_syntax.orh` which triggers a parse error, and checks for `"module-level.*var.*not allowed"`. This message is produced by a _semantic_ check, not the PEG parser. However, some tests check for `"unexpected"` generically (e.g. `fail_ptr_cast.orh` line 467). If the new multi-token message no longer contains `"unexpected"`, those tests fail.
**Why it happens:** The generic fallback was `"unexpected 'foo'"`. After the change, the fallback is `"expected 'X', 'Y', or 'Z'"` (no longer contains "unexpected").
**How to avoid:** D-02 says single-token case keeps `"unexpected 'foo'"`. The multi-token case changes the wording. Check each test that matches `"unexpected\|parse\|error"` — these are OR patterns and will still match `"error"`. The `fail_ptr_cast.orh` test matches `"error\|unexpected\|parse"` — will still pass via `"error"` if that's in the output.
**Warning signs:** `test/11_errors.sh` failures on `neg_ptr_cast` or `neg_linkc` tests.

### Pitfall 5: `matchTokenText` does not call `trackFailure`
**What goes wrong:** Contextual identifier matches (e.g. `'Error'`, `'Ptr'`, `'dep'`) use `matchTokenText` which currently does not call `trackFailure` (line 173-179). These alternatives never appear in the expected set.
**Why it happens:** `matchTokenText` was intentionally left simpler. For contextual tokens, the kind is always `.identifier`, so adding them to the set would just add `.identifier` (already tracked by `matchToken` for the identifier rule).
**How to avoid:** No action needed — `matchTokenText` failing at position X means an `.identifier` token was present but wrong text; the useful information is "expected identifier" not "expected the identifier 'Error'". Leave `matchTokenText` as-is.

---

## Code Examples

### Pattern: BoundedArray initialization in a struct

```zig
// Source: Zig stdlib BoundedArray
// Zero-init in struct default
furthest_expected: std.BoundedArray(TokenKind, 64) = .{},
```

### Pattern: append ignoring overflow

```zig
// Source: Zig stdlib BoundedArray.append
self.furthest_expected.append(expected) catch {};
// overflow means we already have 64 entries — safe to drop
```

### Pattern: slice access

```zig
// Source: Zig stdlib BoundedArray.slice
for (self.furthest_expected.slice()) |kind| { ... }
```

### Pattern: existing message formatting (unchanged)

```zig
// Source: src/module.zig lines 448-456 — keep kw_var special case intact
const msg = if (err_info.found_kind == .kw_var) blk: {
    const next_pos = err_info.pos + 1;
    if (next_pos < tokens.items.len and tokens.items[next_pos].kind == .ampersand)
        break :blk try std.fmt.allocPrint(alloc, "var &T is not valid — use &T for mutable references", .{})
    else
        break :blk try std.fmt.allocPrint(alloc, "unexpected '{s}'", .{err_info.found});
} else if (err_info.expected_set.len > 1) blk: {
    break :blk try formatExpectedSet(alloc, err_info.expected_set);
} else try std.fmt.allocPrint(alloc, "unexpected '{s}'", .{err_info.found});
defer alloc.free(msg);
```

### Pattern: kindDisplayName helper

```zig
fn kindDisplayName(kind: TokenKind) []const u8 {
    const raw = @tagName(kind);
    // Strip kw_ prefix for keywords
    if (std.mem.startsWith(u8, raw, "kw_")) return raw[3..];
    // Special cases
    return switch (kind) {
        .eof => "end of file",
        .newline => "newline",
        .identifier => "identifier",
        .int_literal => "integer literal",
        .float_literal => "float literal",
        .string_literal => "string literal",
        else => raw,
    };
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single `furthest_expected: TokenKind` | BoundedArray of expected tokens | Phase 31 | Error shows all alternatives at failure point |
| `"unexpected 'X'"` always | `"expected 'A', 'B', or 'C'"` when multiple | Phase 31 | Actionable parse errors |

---

## Open Questions

1. **Should `furthest_rule` update on `>` or `>=` in the new `trackFailure`?**
   - What we know: Current code updates on `>=` (tie goes to last). The new code splits into `>` (reset) and `==` (accumulate).
   - What's unclear: Which rule name is most useful when multiple alternatives fail at the same position.
   - Recommendation: Keep `furthest_rule` updating on `>=` — the last rule attempted is usually the most specific context.

2. **Does `main.zig` line 772 have `allocator` in scope?**
   - What we know: `runAnalysis` function signature likely takes an allocator.
   - What's unclear: Confirmed from reading lines 765-779 — `main.zig:770` calls `engine.getError()` inside a function; allocator availability depends on the surrounding context (not visible in the excerpt).
   - Recommendation: Read `main.zig` lines 740-780 before implementing. If `allocator` is in scope, use `formatExpectedSet`. If not, format the expected set with a stack buffer or skip the improvement for the analysis path.

3. **`matchRule` also calls `trackFailure` indirectly via `furthest_rule` update — does the rule update need to respect the token accumulation?**
   - What we know: `matchRule` at line 130-131 updates `furthest_rule` when `pos >= furthest_pos`. This is separate from `trackFailure`.
   - What's unclear: Whether updating `furthest_rule` on `>=` causes inconsistency (rule from a different alternative than the accumulated tokens).
   - Recommendation: Leave `matchRule`'s `furthest_rule` update as-is. Rule name is context info, not part of the expected set.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is a pure code change to `src/peg/engine.zig` and `src/module.zig` with no external dependencies.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig built-in `test` blocks + shell integration tests |
| Config file | `build.zig` — `zig build test` runs all test blocks |
| Quick run command | `zig build test 2>&1 | grep -E "PASS|FAIL|error"` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PEG-01 | Multi-token expected set at choice failure | unit | `zig build test 2>&1 \| grep engine` | ✅ (engine.zig has existing test blocks) |
| PEG-01 | Deduplication of repeated token kinds | unit | `zig build test` | ❌ Wave 0 — new test needed |
| PEG-01 | Single token keeps "unexpected" format | unit | `zig build test` | ❌ Wave 0 — new test needed |
| PEG-01 | Multi-token format renders correctly | unit | `zig build test` | ❌ Wave 0 — new test needed |
| PEG-01 | Existing error tests still pass | integration | `bash test/11_errors.sh` | ✅ |

### Sampling Rate
- **Per task commit:** `zig build test`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New unit test in `engine.zig` — multi-token expected set via choice: verify `getError().expected_set` contains all alternatives (covers PEG-01 accumulation)
- [ ] New unit test in `engine.zig` — deduplication: choice with repeated token kind yields set of size 1 (covers D-06)
- [ ] New unit test in `engine.zig` — single-token failure: verify `expected_set.len == 1` and `getError()` produces "unexpected" message (covers D-02)
- No new test files needed — all tests go into existing `engine.zig` `test` blocks

---

## Sources

### Primary (HIGH confidence)
- Direct code reading: `src/peg/engine.zig` — full source of Engine, trackFailure, getError, ParseError
- Direct code reading: `src/peg/grammar.zig` — Expr union, Grammar, choice variant
- Direct code reading: `src/module.zig` lines 430-465 — consumer call site and message formatting
- Direct code reading: `src/main.zig` lines 765-779 — analysis command error output
- Direct code reading: `src/lexer.zig` lines 8-112 — TokenKind enum (approximately 78 variants total)
- Direct code reading: `test/11_errors.sh` — all existing parse error test patterns and assertions
- Direct code reading: `src/peg.zig` lines 1-33 — ParseError re-export path

### Secondary (MEDIUM confidence)
- Zig stdlib `std.BoundedArray` documentation — fixed-capacity array without heap allocation; API verified from CLAUDE.md Zig version constraint (0.15.2)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; all Zig stdlib primitives
- Architecture: HIGH — full source read of all four touch points; change is self-contained
- Pitfalls: HIGH — derived from direct code analysis and test file review

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain — compiler internals, no external dependencies)
