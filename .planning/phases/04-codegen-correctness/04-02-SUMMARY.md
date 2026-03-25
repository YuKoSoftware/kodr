---
phase: 04-codegen-correctness
plan: 02
subsystem: mir
tags: [codegen, cross-module, coercion, mir, validation]
dependency_graph:
  requires: []
  provides: [CGEN-02, CGEN-03]
  affects: [src/mir.zig]
tech_stack:
  added: []
  patterns: [type-guided module lookup, struct-ownership module search]
key_files:
  created: []
  modified:
    - src/mir.zig
decisions:
  - "Instance method cross-module lookup uses struct name from resolved type to find owning module — avoids blind all-module scan, no false positives when struct names are unique per module"
  - "CGEN-03 confirmed already working — resolver.zig lines 854-858 correctly report error when module found but type missing; two existing unit tests provide coverage; no code change needed"
  - "Instance method fallback restricted to .named types only — generic types (List, Map) don't have struct-level method dispatch through this path"
metrics:
  duration_minutes: 12
  completed_date: "2026-03-25"
  tasks_completed: 2
  files_modified: 1
requirements:
  - CGEN-02
  - CGEN-03
---

# Phase 04 Plan 02: Cross-Module Ref-Passing and Qualified Generic Validation Summary

**One-liner:** Type-guided instance method resolution in MIR enables `value_to_const_ref` coercion annotation for cross-module struct method calls with `const &` parameters.

## What Was Built

### CGEN-02: Cross-Module Instance Method Call Coercion (src/mir.zig)

Added a type-guided fallback in `resolveCallSig` for `obj.method(args)` patterns where `obj` is a variable holding a cross-module struct instance.

**Problem:** When `counter.increment()` is called and `counter` is a `Counter` struct from another module, the existing code paths in `resolveCallSig` would fail to find `increment`'s signature. The object (`counter`) is an identifier, not a module name, so `ad.get(object.identifier)` returns null (it looks for a module named "counter", not a struct field lookup). This caused `annotateCallCoercions` to get no signature back and skip coercion annotation — so `const &` parameters never got `value_to_const_ref` annotated, and codegen emitted `arg` instead of `&arg`.

**Fix:** Added a final fallback block in `resolveCallSig` (after the existing cross-module paths) that:
1. Resolves the object node's type via `self.lookupType(c.callee.field_expr.object)`
2. Extracts the struct name if the type is `.named`
3. Iterates `all_decls` to find the module whose `DeclTable.structs` contains that struct name
4. Returns the method signature from that module's `funcs` map

This is precise — it searches by struct ownership rather than blindly scanning all method names. No false positives from same-name methods in different modules (the struct type disambiguates).

### CGEN-03: Qualified Generic Validation (src/resolver.zig)

No code change required. The existing code at resolver.zig lines 854-858 already correctly handles the "module found, type not found" case: `is_known` stays `false` and the error is reported. Two unit tests at lines 1574-1643 confirm this works:
- "resolver - validateType catches unknown qualified generic" — module found, type NOT found
- "resolver - validateType accepts known qualified generic" — module found, type IS found

The two `is_known = true` fallbacks (module not in `all_decls`, or `all_decls` is null) are intentionally kept to avoid false positives from module processing order.

## Deviations from Plan

### Auto-adjusted: Instance method lookup approach

The plan proposed checking for a "." in the struct name to identify qualified names (e.g., `"math.Counter"`). However, reading `src/types.zig` and `src/resolver.zig` showed that the resolver stores struct types as `.named = "Counter"` (without module prefix). So the qualified-name path would never trigger. The implementation instead uses struct ownership lookup: find which module's `DeclTable.structs` contains the struct name. This is more correct than the plan's description while achieving the same goal.

**No Rule 4 needed** — this is an implementation detail adjustment within the same approach (type-guided lookup), not an architectural change.

## Task Summary

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix cross-module call coercion annotation (CGEN-02) and confirm CGEN-03 | 93c9f0d | src/mir.zig (+18 lines) |
| 2 | Run full test suite — verify no regressions | (no code change) | — |

## Test Results

- `zig build test` — PASS (all unit tests including resolver qualified generic tests)
- `./testall.sh` — 136 passed, 100 failed (stages 09 and 10 only)
  - The 100 failures are pre-existing ("tester module codegen" — separate issue tracked in PROJECT.md)
  - No new failures introduced by this plan's changes
  - All 9 other stages pass

## Known Stubs

None.

## Self-Check: PASSED

- `src/mir.zig` modified: FOUND
- Commit 93c9f0d: FOUND (`git log --oneline | grep 93c9f0d`)
- "Instance method" comment in src/mir.zig: FOUND (grep returns 1)
- Unit tests pass: CONFIRMED (exit 0)
