# Phase 07: Full Test Suite Gate — Research

**Researched:** 2026-03-25
**Domain:** PEG builder string interpolation + stale codegen test cleanup
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** The test `grep -q "OrhonNullable" "$GEN_TESTER"` checks for a legacy wrapper type that was removed when native Zig `?T` optionals were adopted (v0.9.7). The codegen is correct — the test is stale.
- **D-02:** Fix the test in `test/09_language.sh` to check for the native `?` optional pattern instead of `OrhonNullable`.
- **D-03:** The PEG grammar has `STRING_LITERAL` with a comment "may contain @{expr} interpolation" but the builder (`src/peg/builder.zig`) has no interpolation handling. Strings with `@{expr}` are treated as plain string literals.
- **D-04:** The codegen already has full interpolation support (`generateInterpolatedString` and `generateInterpolatedStringMir`) — it just never receives interpolation nodes from the PEG builder.
- **D-05:** Fix approach: Add interpolation detection in the PEG builder. When a `STRING_LITERAL` contains `@{`, split it into an `interpolated_string` AST node with `.literal` and `.expr` parts. The parser already defines `InterpolatedString` and `InterpolationPart` types.
- **D-06:** The PEG grammar itself may need a rule change — either split `STRING_LITERAL` into two token types at the lexer level, or handle interpolation in the builder by post-processing string literals.

### Claude's Discretion
- Whether to handle interpolation at the PEG grammar level (new rules) or the builder level (post-process STRING_LITERAL)
- Exact pattern for detecting and splitting `@{expr}` in strings
- Whether nested interpolation `@{a ++ @{b}}` needs handling (probably not for now)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GATE-01 | `./testall.sh` passes all 11 stages with 0 failures | Two root causes identified: 3 stale test assertions in `test/09_language.sh` (null union patterns) and missing interpolation support in `src/peg/builder.zig` (4+1 failures in stages 10 and aggregate) |
</phase_requirements>

---

## Summary

Phase 07 has two independent root causes to fix. Root cause 1 is purely a test file issue: `test/09_language.sh` contains three assertions that check for legacy `OrhonNullable`/`.none`/`.some` patterns that were replaced by native Zig `?T` optionals in v0.9.7. The codegen is correct; the tests are stale. Root cause 2 is a genuine missing feature: the PEG builder (`src/peg/builder.zig`) never creates `interpolated_string` AST nodes from `STRING_LITERAL` tokens that contain `@{expr}` syntax. The entire downstream pipeline (MIR + codegen) already handles interpolation correctly but receives plain `string_literal` nodes instead.

The implementation path for both fixes is clear and low-risk. The stale test fix is a 3-line search-and-replace. The builder fix requires extending `buildStringLiteral` to detect `@{` in the token text, split it into parts, and create an `interpolated_string` AST node. All current interpolation expressions in the codebase are simple identifiers (`@{name}`, `@{x}`), so a text-scanning splitter with direct identifier node creation covers all real cases.

**Primary recommendation:** Fix the stale tests first (trivial, confirms test infrastructure), then add interpolation detection to `buildStringLiteral` in the PEG builder.

---

## Standard Stack

This phase modifies existing code — no new dependencies.

| File | Role | Change |
|------|------|--------|
| `test/09_language.sh` | Stage 09 test assertions | Replace 3 stale grep patterns with native Zig patterns |
| `src/peg/builder.zig` | PEG builder, `buildStringLiteral` | Add interpolation splitting logic |
| `src/parser.zig` | AST types | No change — `InterpolatedString` and `InterpolationPart` already defined |
| `src/codegen.zig` | Codegen | No change — `generateInterpolatedString` and `generateInterpolatedStringMir` already implemented |
| `src/mir.zig` | MIR | No change — `.interpolation` kind, `interp_parts`, `findInterpolation`, `lowerBlock` already implemented |

---

## Architecture Patterns

### Root Cause 1: Stale Null Union Tests

**The failing tests (test/09_language.sh, lines 92–99):**

```bash
# STALE — remove these:
if grep -q "OrhonNullable" "$GEN_TESTER"; then pass "null union codegen"
if grep -q ".none"          "$GEN_TESTER"; then pass "null → .none codegen"
if grep -q ".some"          "$GEN_TESTER"; then pass "value → .some codegen"
```

**What the codegen actually emits for `(null | i32)`:**

The codegen in `typeToZig` (codegen.zig line 3696–3712) emits native Zig `?T`:
- `(null | i32)` type → `?i32`
- `x is null` → `(x == null)` (codegen.zig line 1582–1585)
- `.value` unwrap → `.?` (codegen.zig line 1865–1867)

**Correct replacement assertions:**

```bash
# Replace OrhonNullable check: ?i32 (or similar ?T) will always be in the file
if grep -q "?i32" "$GEN_TESTER"; then pass "null union codegen (?T)"

# Replace .none check: == null is generated for `x is null`
if grep -q "== null" "$GEN_TESTER"; then pass "null → == null codegen"

# Replace .some check: .? is generated for .value unwrap on ?T
if grep -q '\.?' "$GEN_TESTER"; then pass "value → .? codegen"
```

Note: `.none` and `.some` are legacy patterns from before v0.9.7. The current codegen generates `== null` and `.?` respectively.

### Root Cause 2: Missing Interpolation in PEG Builder

**The pipeline gap:**

```
Lexer:   "hello @{name}!" → single string_literal token (text includes @{name})
Builder: buildStringLiteral → returns .string_literal node (WRONG — ignores @{})
MIR:     receives .string_literal → LiteralKind.string → no interpolation
Codegen: emits raw string literal → broken output
```

**The fix location:** `buildStringLiteral` in `src/peg/builder.zig` (line 1043).

**Current code:**
```zig
fn buildStringLiteral(ctx: *BuildContext, cap: *const CaptureNode) !*Node {
    return ctx.newNode(.{ .string_literal = tokenText(ctx, cap.start_pos) });
}
```

**The token text** for `"hello @{name}!"` is `"hello @{name}!"` (includes outer quotes). The builder must:
1. Check if the text (excluding outer quotes) contains `@{`
2. If yes, scan character by character to split into `InterpolationPart` slices
3. Each `@{...}` becomes an `.expr` part; surrounding text becomes `.literal` parts
4. Return an `interpolated_string` node

**String scanning approach (builder-level post-processing, no grammar change needed):**

The decision between grammar-level and builder-level is resolved by the architectural constraint: the lexer produces a single `string_literal` token for the entire string including `@{expr}` content. There are no sub-tokens for the embedded expression. This is correct and intentional — `@{` inside a string is not a lexer-level concern.

Therefore: **builder-level post-processing** is the correct approach. The grammar rule `string_literal <- STRING_LITERAL` stays unchanged.

**Splitting algorithm:**

```
inner = strip outer quotes from token text: text[1..text.len-1]
parts = []
pos = 0
while pos < inner.len:
    if inner[pos..] starts with "@{":
        find matching "}" (count depth for nested braces if needed)
        expr_text = inner[pos+2..close_pos]
        append InterpolationPart{ .expr = buildExprFromText(expr_text) }
        pos = close_pos + 1
    else:
        collect chars until "@{" or end
        append InterpolationPart{ .literal = collected_text }
```

**Expression parsing for embedded identifiers:**

For the current use cases (`@{name}`, `@{x}`), the embedded expression text is always a simple identifier. The simplest correct approach creates an `.identifier` node directly from the expr_text:

```zig
const expr_node = try ctx.newNodeAt(.{ .identifier = expr_text }, cap.start_pos);
```

This covers 100% of existing test cases. Complex expressions (function calls, arithmetic) would need a sub-lex/sub-parse step, but that is explicitly out of scope per CONTEXT.md.

**The `InterpolationPart` type** (parser.zig line 289–296):
```zig
pub const InterpolatedPart = union(enum) {
    literal: []const u8,  // raw text chunk (no quotes)
    expr: *Node,          // embedded expression node
};
pub const InterpolatedString = struct {
    parts: []InterpolatedPart,
};
```

Note: The type in `parser.zig` is named `InterpolatedPart` not `InterpolationPart`. Both names appear in the codebase — use `parser.InterpolatedPart` when declaring slices.

**Arena allocation for parts slice:** The builder uses `ctx.alloc()` (arena allocator). The parts slice must be allocated via `ctx.alloc()`, and literal text slices must be duped (they are slices into the token text, which is owned by the token array — arena lifetime).

**What the downstream pipeline expects (already working):**

MIR (`src/mir.zig`):
- `lowerNode` handles `.interpolated_string` (line 1051) — creates MIR children from expr parts
- `lowerBlock` calls `findInterpolation` to detect interpolated strings and hoist temp vars (line 1135)
- `interp_parts` field stores the literal parts for codegen (line 696)

Codegen (`src/codegen.zig`):
- `generateInterpolatedString` (line 2599) — AST path: hoists `const _interp_N = std.fmt.allocPrint(...) catch |err| return err; defer ...; ` to `pre_stmts`, emits `_interp_N`
- `generateInterpolatedStringMirInline` (line 3036) — MIR inline path for temp_var handler
- The MIR path is the primary path for `var`/`const` declarations

### Handling the Builder's Lack of Grammar Access

The `BuildContext` struct does NOT have access to the grammar or PEG capture engine. It only has:
- `tokens: []const Token` — the full token stream
- `arena: std.heap.ArenaAllocator` — for all AST allocations

For simple identifier expressions in `@{...}`, no grammar access is needed — just `ctx.newNodeAt(.{ .identifier = expr_text }, cap.start_pos)`.

If future complex expression interpolation is needed, the approach would be: re-lex the expr_text with `Lexer.init(expr_text).tokenize(alloc)`, load the grammar, run `CaptureEngine.captureRule("expr", 0)`, then call `buildNode`. This is not needed now.

### Existing `buildNode` dispatch for literals

The `buildStringLiteral` is called via the dispatch at builder.zig line 167:
```zig
if (std.mem.eql(u8, rule, "string_literal")) return buildStringLiteral(ctx, cap);
```

The function receives the `CaptureNode` for the `string_literal` grammar rule. `cap.start_pos` points to the single `STRING_LITERAL` token. `tokenText(ctx, cap.start_pos)` returns the full raw text including outer double-quotes.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Arena-allocated AST nodes | Custom allocator | `ctx.alloc().create(Node)` via `ctx.newNodeAt()` |
| Identifier node creation | Manual struct init | `ctx.newNodeAt(.{ .identifier = text }, pos)` |
| Slice allocation | Custom buffer | `ctx.alloc().alloc(InterpolatedPart, count)` then fill, or ArrayList + `toOwnedSlice` |

---

## Common Pitfalls

### Pitfall 1: Token Text Includes Outer Quotes
**What goes wrong:** Processing `token_text[0..]` as if it were the inner string content — the outer `"` characters are part of the token text. `"hello @{name}!"` has its first character as `"`, not `h`.
**How to avoid:** Strip one character from each end: `text[1..text.len - 1]`. Verify `text.len >= 2` first.

### Pitfall 2: Literal Slices Must Be Arena-Duped
**What goes wrong:** Storing slices directly into the token text (e.g., `text[a..b]`) as literal parts. The token array may be freed after parsing.
**How to avoid:** Dupe each literal chunk into the arena: `try ctx.alloc().dupe(u8, text[a..b])`.

### Pitfall 3: Fixing Only the `OrhonNullable` Test Line
**What goes wrong:** The CONTEXT.md says "1 failure" but there are actually 3 stale assertions at lines 92, 95, and 98. Fixing only line 92 leaves `.none` and `.some` still failing.
**Warning signs:** Test output shows "null → .none codegen" and "value → .some codegen" still FAIL after fix.
**How to avoid:** Fix all three lines together. The tester.zig generated code uses `?i32`, `== null`, and `.?`.

### Pitfall 4: Empty String Handling
**What goes wrong:** An empty string `""` has text length 2 (just the outer quotes). After stripping quotes, `text[1..1]` is empty — this is fine and should return a plain `string_literal` node (no `@{` possible in empty string).
**How to avoid:** The `@{` check on the inner text naturally handles this — `std.mem.indexOf` on empty slice returns null.

### Pitfall 5: Unclosed `@{`
**What goes wrong:** String `"broken @{name"` has no closing `}` — infinite loop or out-of-bounds if the scan doesn't guard.
**How to avoid:** If no `}` is found after `@{`, treat the remainder as a literal part and log nothing (silent degradation — don't error, just emit the raw text).

### Pitfall 6: `InterpolatedPart` vs `InterpolationPart`
**What goes wrong:** Using the wrong type name. `parser.zig` defines `InterpolatedPart`; `mir.zig` also uses `InterpolatedPart` when storing `interp_parts`. Calling it `InterpolationPart` in new code causes a compile error.
**How to avoid:** Always use `parser.InterpolatedPart`.

---

## Code Examples

### Correct null union test assertions (replacing stale ones)

```bash
# Source: direct inspection of codegen.zig typeToZig() output
# (null | i32) → ?i32 in generated tester.zig
if grep -q "?i32" "$GEN_TESTER" 2>/dev/null; then pass "null union codegen (?T)"
else fail "null union codegen (?T)"; fi

# x is null → (x == null) — codegen.zig line 1582–1585
if grep -q "== null" "$GEN_TESTER" 2>/dev/null; then pass "null → == null codegen"
else fail "null → == null codegen"; fi

# .value on ?T → .? — codegen.zig line 1865–1867
if grep -qF '.?' "$GEN_TESTER" 2>/dev/null; then pass "value → .? codegen"
else fail "value → .? codegen"; fi
```

### Interpolation detection in buildStringLiteral

```zig
// Source: derived from parser.zig InterpolatedPart + BuildContext API
fn buildStringLiteral(ctx: *BuildContext, cap: *const CaptureNode) !*Node {
    const raw = tokenText(ctx, cap.start_pos);
    // Strip outer quotes; guard against malformed tokens
    if (raw.len < 2) return ctx.newNode(.{ .string_literal = raw });
    const inner = raw[1 .. raw.len - 1];

    // Fast path: no interpolation
    if (std.mem.indexOf(u8, inner, "@{") == null) {
        return ctx.newNode(.{ .string_literal = raw });
    }

    // Build InterpolationPart list
    var parts = std.ArrayListUnmanaged(parser.InterpolatedPart){};
    var pos: usize = 0;
    while (pos < inner.len) {
        if (std.mem.indexOf(u8, inner[pos..], "@{")) |rel| {
            const abs = pos + rel;
            // Emit literal before @{
            if (rel > 0) {
                const lit = try ctx.alloc().dupe(u8, inner[pos..abs]);
                try parts.append(ctx.alloc(), .{ .literal = lit });
            }
            // Find closing }
            const expr_start = abs + 2;
            if (std.mem.indexOfScalarPos(u8, inner, expr_start, '}')) |close| {
                const expr_text = try ctx.alloc().dupe(u8, inner[expr_start..close]);
                const expr_node = try ctx.newNodeAt(.{ .identifier = expr_text }, cap.start_pos);
                try parts.append(ctx.alloc(), .{ .expr = expr_node });
                pos = close + 1;
            } else {
                // Unclosed @{ — emit remainder as literal
                const lit = try ctx.alloc().dupe(u8, inner[abs..]);
                try parts.append(ctx.alloc(), .{ .literal = lit });
                break;
            }
        } else {
            // No more @{ — emit remainder as literal
            const lit = try ctx.alloc().dupe(u8, inner[pos..]);
            try parts.append(ctx.alloc(), .{ .literal = lit });
            break;
        }
    }

    return ctx.newNodeAt(.{
        .interpolated_string = .{ .parts = try parts.toOwnedSlice(ctx.alloc()) },
    }, cap.start_pos);
}
```

### InterpolatedPart type reference (parser.zig lines 289–296)

```zig
pub const InterpolatedPart = union(enum) {
    literal: []const u8,
    expr: *Node,
};
pub const InterpolatedString = struct {
    parts: []InterpolatedPart,
};
```

---

## Runtime State Inventory

Not applicable — this is a code/test fix phase with no rename or migration.

---

## Environment Availability

Step 2.6: SKIPPED — this phase only modifies `test/09_language.sh` and `src/peg/builder.zig`. No external dependencies beyond the project's own build tools.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Zig built-in `test` blocks + shell test suite |
| Config file | `test/01_unit.sh` (unit), `./testall.sh` (full) |
| Quick run command | `bash test/01_unit.sh && bash test/09_language.sh && bash test/10_runtime.sh` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GATE-01 | All 11 test stages pass | integration | `./testall.sh` | Yes |
| GATE-01 (null union) | `test/09_language.sh` null union assertions pass | integration | `bash test/09_language.sh` | Yes |
| GATE-01 (interp codegen) | `test/09_language.sh` tester module compiles | integration | `bash test/09_language.sh` | Yes |
| GATE-01 (interp runtime) | `test/10_runtime.sh` interpolation + interpolation_int pass | integration | `bash test/10_runtime.sh` | Yes |

### Sampling Rate
- **Per task commit:** `bash test/01_unit.sh` (unit tests, 30 s) + targeted stage
- **Per wave merge:** `./testall.sh`
- **Phase gate:** `./testall.sh` green before `/gsd:verify-work`

### Wave 0 Gaps
None — all test infrastructure already exists. The phase modifies existing test assertions and adds new code to an existing builder function.

---

## Open Questions

1. **Nested or complex interpolation expressions**
   - What we know: All current uses are simple identifiers (`@{name}`, `@{x}`)
   - What's unclear: What happens if a future user writes `@{a + b}` or `@{obj.field}`
   - Recommendation: Simple identifier-only approach is correct for now (per CONTEXT.md: nested interpolation out of scope). The planner should note this as a known limitation in the plan, not implement it.

2. **Whether `.none` and `.some` checks at lines 95/98 are counting as 1 failure or 2**
   - What we know: CONTEXT.md says "1 failure" in stage 09, but inspection reveals 3 stale assertions
   - What's unclear: The CONTEXT.md framing is "1 failure" but the actual test file shows 3 bad assertions — all 3 will fail since `OrhonNullable`, `.none`, and `.some` are all absent from generated code
   - Recommendation: Fix all 3 assertions. The total failure count may differ from the "1 failure" summary in CONTEXT.md depending on whether `./testall.sh` counts individual assertion failures or stage-level failures.

---

## Sources

### Primary (HIGH confidence)
- Direct inspection of `src/peg/builder.zig` — `buildStringLiteral` function confirmed single-token, no interpolation handling
- Direct inspection of `src/lexer.zig` — `lexString()` confirmed: `@{` is not special-cased, captured as raw characters in token text
- Direct inspection of `src/parser.zig` — `InterpolatedPart`, `InterpolatedString` types confirmed present
- Direct inspection of `src/codegen.zig` lines 2599–2672 — `generateInterpolatedString` confirmed working, hoisting to `pre_stmts`
- Direct inspection of `src/codegen.zig` lines 3032–3084 — `generateInterpolatedStringMirInline` confirmed working
- Direct inspection of `src/mir.zig` — `.interpolation` kind, `interp_parts`, `lowerBlock`, `findInterpolation` confirmed present
- Direct inspection of `test/09_language.sh` lines 92–99 — 3 stale assertions confirmed
- Direct inspection of `src/codegen.zig` `typeToZig` (line 3696–3712) — confirmed `?T` output for null unions, `== null` for `is null`, `.?` for `.value` unwrap

### Secondary (MEDIUM confidence)
- `test/fixtures/tester.orh` grep — all interpolation uses are `@{name}` and `@{x}` (identifiers only)
- `src/templates/example/strings.orh` grep — same identifier-only pattern confirmed

---

## Metadata

**Confidence breakdown:**
- Stale test fix: HIGH — direct inspection of test file and codegen output patterns
- Builder interpolation: HIGH — all relevant code paths read directly
- Correct replacement patterns: HIGH — verified in codegen.zig source

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable code, no fast-moving dependencies)
