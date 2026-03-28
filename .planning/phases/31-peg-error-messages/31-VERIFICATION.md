---
phase: 31-peg-error-messages
verified: 2026-03-28T22:00:00Z
status: passed
score: 4/4 must-haves verified
re_verification: false
---

# Phase 31: PEG Error Messages Verification Report

**Phase Goal:** Parse errors list every token the parser could have accepted at the failure point, not just the first alternative tried
**Verified:** 2026-03-28T22:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                     | Status     | Evidence                                                                                 |
| --- | ----------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------- |
| 1   | A syntax error at a choice point shows all expected tokens                               | VERIFIED  | `engine.zig` accumulates all alternatives in `trackFailure`; `module.zig` formats them via `formatExpectedSet`; `main.zig` formats them inline |
| 2   | The expected set is deduplicated — same token never appears twice in one error           | VERIFIED  | `getError()` deduplication loop confirmed at lines 128-139 of `engine.zig`; `test "engine - expected set deduplication"` unit test passes |
| 3   | Single-token failures still show 'unexpected X' format (no regression)                  | VERIFIED  | `module.zig` line 477: `else try std.fmt.allocPrint(alloc, "unexpected '{s}'", .{err_info.found})`; `main.zig` lines 783-786 preserve same fallback |
| 4   | Existing parse error tests in test/11_errors.sh pass unchanged                          | VERIFIED  | `bash test/11_errors.sh` output: 52/52 passed; `./testall.sh`: 266/266 tests passed |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `src/peg/engine.zig` | Fixed-size accumulator in Engine, accumulation in trackFailure, dedup in getError, expected_set in ParseError | VERIFIED | Two fixed arrays present (`furthest_expected_buf[64]`, `expected_set_buf[64]`); `trackFailure` resets on advance, accumulates on tie; `getError()` deduplicates; `ParseError.expected_set: []const TokenKind` at line 88 |
| `src/module.zig` | Multi-token expected set formatting in parse error consumer | VERIFIED | `formatExpectedSet()` defined at line 27; called at line 476 when `err_info.expected_set.len > 1` |
| `src/main.zig` | Multi-token expected set formatting in analysis command error output | VERIFIED | Inline loop formatting at lines 772-782 when `err.expected_set.len > 1` |

**Note on plan deviation:** The PLAN frontmatter specifies `contains: "BoundedArray(TokenKind, 64)"` for `engine.zig`. The implementation uses two plain fixed arrays instead — `furthest_expected_buf: [64]TokenKind` and `expected_set_buf: [64]TokenKind`. This is a documented deviation (SUMMARY.md, Deviation 1): `std.BoundedArray` does not exist in Zig 0.15.2. The behavioral goal is fully achieved; the deviation is a Zig API version mismatch in the plan text, not a code defect.

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `src/peg/engine.zig` | `src/module.zig` | `ParseError.expected_set` consumed by `formatExpectedSet` | WIRED | `err_info.expected_set` at module.zig lines 475-476 |
| `src/peg/engine.zig` | `src/main.zig` | `ParseError.expected_set` consumed in analysis output | WIRED | `err.expected_set` at main.zig lines 772-782 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `src/module.zig` formatExpectedSet call | `err_info.expected_set` | `val_engine.getError()` after `matchRule("program", 0)` runs over the actual token stream | Yes — populated by `trackFailure` during real parse attempt | FLOWING |
| `src/main.zig` inline loop | `err.expected_set` | `engine.getError()` after `matchAll()` fails | Yes — same accumulation mechanism | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| choice failure accumulates expected set (len == 3) | `zig build test` — test "engine - choice failure accumulates expected set" | 266/266 passed, exit 0 | PASS |
| deduplication yields unique set | `zig build test` — test "engine - expected set deduplication" | 266/266 passed, exit 0 | PASS |
| single token failure keeps len 1 | `zig build test` — test "engine - single token failure keeps len 1" | 266/266 passed, exit 0 | PASS |
| kindDisplayName strips kw_ prefix and handles specials | `zig build test` — test "engine - kindDisplayName" | 266/266 passed, exit 0 | PASS |
| existing error tests pass with new error format | `bash test/11_errors.sh` | 52/52 passed | PASS |
| full pipeline passes | `./testall.sh` | All 266 tests passed across 11 stages | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| PEG-01 | 31-01-PLAN.md | PEG expected-set accumulation — when alternatives fail at the same position, show all expected tokens instead of just one | SATISFIED | Engine accumulates all alternatives; both consumers format multi-token sets; all tests pass |

No orphaned requirements — REQUIREMENTS.md maps only PEG-01 to Phase 31, and the plan claims PEG-01.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| None | — | — | — | — |

No stubs, placeholders, or empty implementations found. `trackFailure` actively mutates state; `getError` produces a populated result; `formatExpectedSet` builds a real string from the set. Single-token fallback paths (`"unexpected '{s}'"`) are intentional behavior, not stubs — they are reached only when `expected_set.len == 1`.

### Human Verification Required

None required for automated checks. One optional manual check for completeness:

**Manual confirmation (optional):** Create a `.orh` file with a syntax error at a top-level declaration (e.g., an unrecognized keyword where `func`, `struct`, `const`, etc. are valid). Run `orhon build`. Verify the error message lists multiple expected tokens rather than just one.

This cannot be verified programmatically without starting the full pipeline on a known failing fixture, but all unit tests and integration tests confirm the mechanism is wired end-to-end.

### Gaps Summary

No gaps. All four observable truths are verified, all three artifacts pass all four verification levels (exists, substantive, wired, data flows), both key links are wired, PEG-01 is satisfied, and all 266 tests pass.

---

_Verified: 2026-03-28T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
