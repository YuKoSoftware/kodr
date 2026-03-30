# Phase 2: Memory & Error Safety — Research

**Researched:** 2026-03-24
**Domain:** Zig error propagation, allocator strategy, stdlib bridge files, codegen patterns
**Confidence:** HIGH

---

## Summary

Phase 2 addresses four categories of memory and error-safety problems in the Orhon
compiler and its stdlib bridge files. Three of the four requirements (MEM-01, MEM-02,
MEM-04) are surgical changes confined to `src/codegen.zig`, `src/mir.zig`, and
`test/fixtures/tester.orh`. MEM-03 is a broader but mechanical sweep of 15 stdlib
`.zig` files.

The interpolation temp buffer strategy (MEM-01) is already 90% implemented: the MIR
lowerer injects `temp_var` + `injected_defer` nodes that emit `defer page_allocator.free(...)`.
The only remaining gap is the `catch unreachable` at the end of both
`generateInterpolatedString` and `generateInterpolatedStringMir` — these need to become
`catch |err| return err` so OOM propagates instead of panicking. This also directly
satisfies MEM-02 for the interpolation-related sites.

For MEM-02 (broader `catch unreachable` in codegen), there are two additional
independent problem areas: the thread handle codegen paths (lines 700/726 and 950/983)
and the error-union `.value` unwrap emissions (lines 1838, 1855, 1861, 2257, 2270,
2277). The thread sites emit `catch unreachable` into the *generated Zig* and should
be left as-is — they reflect the user's explicit thread allocation which should panic
on OOM the same as any Zig app. The `.value` unwrap emissions that emit literal
`catch unreachable` text into generated code are correct by design — they express
"error has been narrowed out, this is safe to unwrap". Only the allocator-driven
`catch unreachable` calls (interpolation sites) are the actual compiler bug.

For MEM-03, the 103 `catch {}` instances split into two semantically distinct
categories that need different treatment strategies.

For MEM-04, the three bare `Ptr(T, &x)` constructor calls in `tester.orh` need to
become `.cast()` style. Collections already use `.new()` — no changes needed there.

**Primary recommendation:** Fix in this order: MEM-02 (interpolation allocPrint
catch sites) — this fixes both MEM-01 and part of MEM-02. Then MEM-03 (stdlib
catch {} sweep). Then MEM-04 (tester.orh Ptr constructor syntax).

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MEM-01 | String interpolation `@{variable}` temp buffers — establish cleanup strategy | MIR lowerer already injects `defer free()`. Gap: allocPrint uses `catch unreachable` instead of propagating. Strategy: document as "injected_defer arena strategy", change `catch unreachable` → `catch |err| return err` in both interpolation codegen functions. |
| MEM-02 | `catch unreachable` in codegen crashes on OOM | Only the allocPrint `catch unreachable` calls (lines 2584, 2983) are compiler-internal OOM bugs. Thread and `.value` sites emit into *generated* Zig intentionally. Fix: propagate error at the two allocPrint sites. |
| MEM-03 | 103 `catch {}` across 15 stdlib bridge files — propagate or document strategy | Two categories: (A) I/O-in-void-return functions where `catch {}` is the correct Zig idiom for fire-and-forget, (B) data-builder functions where silent truncation on OOM corrupts output. Category A: add `// fire-and-forget: I/O in void fn` comment. Category B: propagate with `catch return error.out_of_memory` or `catch return ""`. |
| MEM-04 | Tester module pointer constructors need `.new()`/`.cast()` style | 3 bare `Ptr(T, &x)` calls in `tester.orh`. Collections already use `.new()`. Need to add `.cast()` as a method-style constructor on `Ptr(T)` in codegen and update tester.orh. |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

- All compiler code is Zig 0.15.2+ — use Codeberg/ziglang.org for references, not GitHub
- Recursive codegen functions must use `anyerror!` not inferred `!`
- `SCREAMING_SNAKE_CASE` for module-level constants, `camelCase` for methods
- No hacky workarounds — clean fixes only
- Run `./testall.sh` after all changes (11 test stages)
- No new language features in this milestone — stabilization only
- Changes must not break existing `.orh` programs or the example module
- `Reporter` owns message strings — `defer allocator.free(msg)` before `reporter.report()`
- Template substitution — split-write pattern, not `allocPrint` with `{s}` in templates

---

## Standard Stack

No new libraries. All fixes use existing Zig stdlib patterns already present in the codebase.

### Zig Error Propagation Patterns (existing in codebase)

```zig
// Pattern 1: propagate from allocator failure in void-return context
// BEFORE: self.inner.append(self.alloc, item) catch {};
// AFTER (for data-builder functions):
self.inner.append(self.alloc, item) catch return;
// or for functions returning a value on failure:
self.inner.append(self.alloc, item) catch return "";

// Pattern 2: propagate from allocator failure in error-union-return context
// BEFORE: std.fmt.allocPrint(...) catch unreachable
// AFTER:
const result = try std.fmt.allocPrint(...);
// or at emit site:
try self.emit("}) catch |err| return err");
```

### Zig Fire-and-Forget I/O Pattern (correct idiom for void I/O)

```zig
// This is the correct Zig idiom for I/O in a void-returning function.
// The caller cannot handle I/O errors, so silent discard is correct.
// Applies to: console.print(), console.println(), console.flush(), tui render
w.interface.writeAll(msg) catch {};  // correct — fire-and-forget
```

---

## Architecture Patterns

### MEM-01: Interpolation Cleanup Strategy (ALREADY IMPLEMENTED)

The full pipeline for `@{expr}` interpolation already exists:

1. `MirLowerer.lowerBlock()` detects `interpolated_string` nodes in statements
2. Hoists them: injects `temp_var` node (`const _orhon_interp_N = allocPrint(...)`)
3. Injects `injected_defer` node (`defer page_allocator.free(_orhon_interp_N)`)
4. Replaces original interpolation reference with the temp var name
5. `CodeGen` emits `temp_var` → assignment, `injected_defer` → defer statement

The strategy is documented in `src/mir.zig` around line 1117. The only gap: both
codegen emission functions end with `catch unreachable` which panics on OOM.

**Fix:** Change the emitted text from `catch unreachable` to `catch |err| return err`
in `generateInterpolatedString` (line 2584) and `generateInterpolatedStringMir` (line
2983). This makes the allocPrint failure propagate to the Orhon function's caller
in the generated Zig code, which is the correct behavior.

### MEM-02: Codegen catch unreachable Audit

Full inventory of `catch unreachable` in `codegen.zig`:

| Line(s) | Context | Category | Action |
|---------|---------|----------|--------|
| 2584 | `generateInterpolatedString` — allocPrint | Compiler OOM bug | Change emitted text to `catch \|err\| return err` |
| 2983 | `generateInterpolatedStringMir` — allocPrint | Compiler OOM bug | Same fix |
| 700, 726 | Thread handle codegen — `page_allocator.create` + `Thread.spawn` | Emitted into generated Zig — intentional | Leave as-is |
| 950, 983 | Thread handle codegen (MIR path) — same | Emitted into generated Zig — intentional | Leave as-is |
| 1838, 1855, 1861 | `.value` unwrap — error union narrowed, emitting ` catch unreachable` into Zig | Emitted into generated Zig — semantically correct | Leave as-is |
| 2257, 2270, 2277 | `.value` unwrap (MIR path) — same | Emitted into generated Zig — semantically correct | Leave as-is |

The REQUIREMENTS.md mentions "lines 655, 688, 2123" — these line numbers do not match
the current file (codegen.zig is 3738 lines). The actual OOM-risk sites are lines 2584
and 2983. The requirement text is correct in spirit; only the line numbers are stale.

### MEM-03: stdlib catch {} Classification

**Category A — Fire-and-Forget I/O (leave `catch {}`, add comment):**

These are void-returning functions writing to stdout/stderr/terminal. The caller has
no mechanism to handle a write failure. `catch {}` is the standard Zig idiom here.

| File | Lines | Functions |
|------|-------|-----------|
| console.zig | 15, 19-21, 25, 29 | `print`, `println`, `flush`, `debugPrint` |
| tui.zig | 402, 441-443, 445, 451, 550, 555 | Render loop, cursor/style writes |

**Action:** Add a brief comment on the first occurrence in each function:
`// fire-and-forget: I/O failure in void fn — caller cannot handle`

**Category B — Data Builder Functions (fix silently-truncated output):**

These functions build strings/arrays by appending. A `catch {}` mid-build silently
produces truncated output rather than signaling failure. The function return type
must be checked to determine whether `catch return error.X` or `catch return ""`
is appropriate.

| File | Count | Return Type | Fix Strategy |
|------|-------|-------------|--------------|
| toml.zig | 8 | various — some `[]const u8`, some void | `catch return ""` for string returns; `catch continue` for loop appends |
| json.zig | 11 | `[]const u8` for builders | `catch return "{}"` or `catch return ""` |
| csv.zig | 12 | `[][]const u8` / `[][][]const u8` | `catch return &.{}` or `catch continue` |
| yaml.zig | 14 | `[]const u8` / structs | `catch continue` for list appends |
| str.zig | 2 | `[]const u8` | `catch return ""` (already returns empty str on OOM in most fns) |
| stream.zig | 2 | void methods | `catch {}` is correct — leave, add comment |
| system.zig | 7 | mixed | per-function: `catch {}` for signal handlers, `catch return ""` for string builders |
| regex.zig | 7 | `[]const u8` | `catch return ""` for string result builders |
| ini.zig | 7 | `[]const u8` | `catch return ""` for string builders |
| xml.zig | 6 | `[]const u8` | `catch return ""` for string builders |
| http.zig | 3 | `[]const u8` | `catch return ""` for URL builders |
| fs.zig | 3 | `anyerror!void` / bool | `catch {}` for `seekTo` (best-effort seek); `catch {}` for cleanup `deleteDir` |
| collections.zig | 6 | void methods on data types | `catch {}` is correct — OOM in `add()` is fire-and-forget by design |

**Key insight:** `collections.zig` `catch {}` in `add()`, `put()`, `insert()` is
intentional — Orhon collections are designed to silently drop items on OOM (the same
as many embedded-systems approaches). These stay. `str.zig` already uses `catch return s`
for most operations — the 2 remaining `catch {}` in `splitBy` need attention.

### MEM-04: Ptr Constructor Migration

**Current state in tester.orh:**
```orhon
const raw: RawPtr(i32) = RawPtr(i32, &x)     // line 692
const raw: RawPtr(i32) = RawPtr(i32, &arr)   // line 699
const p: Ptr(i32) = Ptr(i32, &x)             // line 705
```

**Target state (method-style constructors):**
```orhon
const raw: RawPtr(i32) = RawPtr(i32).cast(&x)
const raw: RawPtr(i32) = RawPtr(i32).cast(&arr)
const p: Ptr(i32) = Ptr(i32).cast(&x)
```

**What needs to change:**

1. The Orhon language already supports method-call syntax on types (`List(i32).new()`
   compiles correctly). The codegen emits `Ptr(T, &x)` as `&x` (for `Ptr`) or
   `@as([*]T, @ptrCast(&x))` (for `RawPtr`). The `.cast()` method form needs to be
   recognized by codegen as an equivalent constructor call.

2. Two codegen paths handle `Ptr` construction:
   - `generatePtrExpr` (AST path, ~line 3400) — handles `ptr_expr` nodes
   - `generatePtrExprMir` (MIR path, ~line 2993) — handles `MirNode` of kind `.ptr_expr`

3. The MIR annotator creates `ptr_expr` MirNodes with `name = "Ptr"` or `name = "RawPtr"`.
   The `.cast()` method call would parse as a method call on a generic type, not a
   `ptr_expr` node. So either:
   - Option A: Teach the MIR annotator to recognize `Type(T).cast(addr)` as a
     `ptr_expr` node (preferred — keeps codegen clean)
   - Option B: Teach codegen to handle the method call pattern and emit the right Zig

   Option A is cleaner. Check `src/mir.zig` `MirAnnotator` for the `ptr_expr`
   construction logic (~line 1517) to understand where to intercept.

4. The example module `src/templates/example/data_types.orh` line 85 also uses
   `Ptr(i32, &x)` — it should be migrated to `.cast()` as part of this requirement.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Error propagation from void functions | Custom error-log mechanism | `catch {}` with comment (Category A) or change return type | Zig convention — void I/O is fire-and-forget |
| OOM tracking in collections | Custom OOM flag field | Leave `catch {}` on append | Collections are by design best-effort |
| Interpolation cleanup | New arena-per-interpolation system | Existing `injected_defer` MIR node | Already implemented and correct |

---

## Common Pitfalls

### Pitfall 1: Changing Emitted `catch unreachable` (Generated Code)
**What goes wrong:** The 8 `catch unreachable` sites in codegen that emit into
*generated Zig* (thread handles, `.value` unwraps) look like bugs but are semantically
intentional. Changing them would break generated code semantics.
**Why it happens:** All `catch unreachable` grep hits look identical at first glance.
**How to avoid:** Distinguish "compiler-internal" (allocator call fails in codegen
itself) from "emitting a string that contains `catch unreachable`" (goes into
generated file). Only fix the two `try self.emit("}) catch unreachable")` at lines
2584 and 2983 — these emit OOM-unsafe Zig into the user's program.
**Warning signs:** If you change lines 700/726/950/983/1838/1855/1861, the thread
handle and error-union features will break in generated output.

### Pitfall 2: Over-propagating in stdlib void I/O
**What goes wrong:** Changing `w.interface.writeAll(msg) catch {}` to
`try w.interface.writeAll(msg)` in `console.zig` forces the function return type to
`!void`, which requires all Orhon `console.print()` call sites to handle errors —
a breaking change for all user code.
**Why it happens:** Mechanical "fix all catch {}" approach without considering caller
contract.
**How to avoid:** Category A I/O functions must stay void. Add comment, leave `catch {}`.

### Pitfall 3: Breaking the Example Module
**What goes wrong:** Changing Ptr constructor syntax in `tester.orh` without updating
`src/templates/example/data_types.orh` leaves the shipped language manual out of date.
**How to avoid:** Search for all `Ptr(` usage in templates when migrating tester.orh.

### Pitfall 4: Ptr `.cast()` Without Codegen Support
**What goes wrong:** Updating tester.orh to use `Ptr(i32).cast(&x)` before the MIR
annotator recognizes the new syntax causes a compile error.
**How to avoid:** Implement codegen support first (in a separate task), verify it with
a minimal fixture, then migrate tester.orh and the example module.

### Pitfall 5: `catch return ""` in Functions with Non-String Return Types
**What goes wrong:** Using `catch return ""` in a function that returns `?[]const u8`
or a struct type causes a type mismatch.
**How to avoid:** Read each function's return type before choosing the fallback value.
For slice-of-slice builders, use `catch return &.{}`. For structs, use `catch continue`
inside loops to skip the failed item.

---

## Code Examples

### MEM-01/02: Fixing allocPrint catch unreachable in emitted code

```zig
// BEFORE (src/codegen.zig ~line 2584):
try self.emit("}) catch unreachable");

// AFTER:
try self.emit("}) catch |err| return err");
```

```zig
// BEFORE (src/codegen.zig ~line 2983):
try self.emit("}) catch unreachable");

// AFTER:
try self.emit("}) catch |err| return err");
```

This makes the generated Zig propagate OOM from interpolation to the calling function
(which already returns `anyerror!` or similar in generated code).

### MEM-03: Category A — Fire-and-Forget comment

```zig
// console.zig
pub fn print(msg: []const u8) void {
    // fire-and-forget: I/O in void fn — caller cannot handle write failure
    w.interface.writeAll(msg) catch {};
}
```

### MEM-03: Category B — Data builder propagation

```zig
// json.zig — object builder (return type is []const u8)
// BEFORE:
buf.append(alloc, '{') catch return "{}";
buf.append(alloc, ',') catch {};

// AFTER (consistent):
buf.append(alloc, '{') catch return "{}";
buf.append(alloc, ',') catch return "{}";
```

```zig
// yaml.zig / csv.zig — loop append
// BEFORE:
lines.append(alloc, .{ ... }) catch {};

// AFTER (skip item on OOM, continue building):
lines.append(alloc, .{ ... }) catch continue;
```

### MEM-04: Ptr .cast() constructor

```orhon
// BEFORE (tester.orh):
const p: Ptr(i32) = Ptr(i32, &x)

// AFTER:
const p: Ptr(i32) = Ptr(i32).cast(&x)
```

The codegen path for this needs to recognize a method call `.cast(addr)` on a
generic type name as a `ptr_expr` node. In `MirAnnotator`, look for where
`ptr_expr` MirNodes are created (mir.zig ~line 1517) and add handling for
`Type(T).cast(addr)` call patterns.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig `test` blocks + shell integration tests |
| Config file | none (Zig built-in test runner) |
| Quick run command | `zig build test` |
| Full suite command | `./testall.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MEM-01 | Interpolation temp buffers freed via defer | integration | `./testall.sh` (test/10_runtime.sh runs tester binary with interpolation tests) | Yes |
| MEM-01 | Generated Zig uses `catch \|err\| return err` not `catch unreachable` | codegen check | `test/08_codegen.sh` (can grep generated file) | Yes — but no specific check yet |
| MEM-02 | Codegen allocPrint sites propagate error | integration | `./testall.sh` | Indirectly |
| MEM-03 | stdlib bridge files compile without issues | build | `zig build test` | Yes |
| MEM-04 | Ptr `.cast()` constructor works in tester | runtime | `./testall.sh` (test/10_runtime.sh) | Yes |

### Sampling Rate
- **Per task commit:** `zig build test`
- **Per wave merge:** `./testall.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/08_codegen.sh` — add check that generated interpolation Zig does NOT contain `catch unreachable` (add grep for `catch |err| return err`)

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — all fixes are code changes to existing Zig source files)

---

## Open Questions

1. **Ptr `.cast()` — MIR annotator change scope**
   - What we know: `Ptr(T, &x)` is parsed as a `ptr_expr` AST node. `Ptr(T).cast(&x)` would parse as a method call on a generic type expression.
   - What's unclear: Whether the PEG grammar produces a `method_call` or `func_call` node for `Ptr(T).cast(&x)`. The MIR annotator would need to intercept this before it reaches generic call codegen.
   - Recommendation: The planner should include an investigation task first — build `Ptr(T).cast(&x)` in a minimal fixture and trace what AST node is produced, then implement accordingly.

2. **MEM-03 — `collections.zig` catch {} in `add()`/`put()`**
   - What we know: 6 `catch {}` in collections are intentional (best-effort append).
   - What's unclear: Whether this "silent drop on OOM" policy is documented anywhere.
   - Recommendation: Add a block comment at the top of collections.zig explaining the policy: "Collection methods are best-effort — OOM silently drops items. Use allocator-aware Zig collections directly for hard guarantees."

3. **MEM-02 — line numbers in REQUIREMENTS.md**
   - What we know: REQUIREMENTS.md says "lines 655, 688, 2123" but those lines do not contain `catch unreachable` in the current file. The actual sites are 2584 and 2983.
   - What's unclear: Whether the requirement author was tracking a different revision.
   - Recommendation: Treat the requirement description ("allocator-driven catch unreachable in codegen that panics on OOM") as authoritative, not the specific line numbers. The two interpolation allocPrint sites are the correct targets.

---

## Sources

### Primary (HIGH confidence)
- Direct source inspection: `src/codegen.zig` — full audit of all `catch unreachable` sites
- Direct source inspection: `src/mir.zig` — `MirLowerer.lowerBlock()` interpolation hoisting strategy
- Direct source inspection: `src/std/*.zig` — all 103 `catch {}` instances categorized
- Direct source inspection: `test/fixtures/tester.orh` — Ptr constructor usage
- Direct source inspection: `src/templates/example/data_types.orh` — Ptr constructor in example module

### Secondary (MEDIUM confidence)
- Zig documentation: `catch {}` as idiom for fire-and-forget I/O in void-returning functions — standard Zig community pattern

---

## Metadata

**Confidence breakdown:**
- MEM-01 (interpolation cleanup): HIGH — MIR lowerer inspected, strategy confirmed implemented, gap is 2 lines
- MEM-02 (catch unreachable): HIGH — all 12 sites in codegen audited and categorized
- MEM-03 (stdlib catch {}): HIGH — all 103 instances found, categorized into A/B
- MEM-04 (Ptr constructor): MEDIUM — syntax change is clear, but the MIR annotator change path has a known uncertainty (how `Ptr(T).cast(addr)` parses)

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (stable codebase, no fast-moving external deps)
