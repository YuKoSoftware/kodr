---
phase: quick
plan: 260328-lsa
subsystem: codegen
tags: [mir, const-auto-borrow, bridge, error-union, struct-params]

requires: []
provides:
  - Unit tests confirming is_bridge guard prevents const auto-borrow for bridge struct
    method calls and direct bridge function calls, including error-union-returning variants
  - Expanded comment documenting guard scope in annotateCallCoercions
affects: [tamga_framework]

tech-stack:
  added: []
  patterns:
    - "is_bridge guard: covers direct bridge calls, struct method calls, and error-union
      return types — all excluded from const auto-borrow via !sig.is_bridge"

key-files:
  created: []
  modified:
    - src/mir.zig

key-decisions:
  - "Bug already fixed by Phase 25 is_bridge addition — the Tamga workaround (const &Texture)
    was written against pre-Phase-25 behavior; no new code change needed in core logic"
  - "Two tests added to prevent regression: bridge struct method call and direct bridge
    function call both confirm no promotion regardless of return type"

patterns-established:
  - "Bridge guard scope: is_direct_call AND !sig.is_bridge together exclude all bridge
    call forms from const auto-borrow (method calls excluded by is_direct_call, direct
    bridge calls excluded by !sig.is_bridge)"

requirements-completed: []

duration: 15min
completed: 2026-03-28
---

# Quick Task 260328-lsa: Bridge Struct Value Param Const Promotion Summary

**Confirmed is_bridge guard already covers error-union bridge calls — Tamga workaround removal unblocked, two regression tests added**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-28T12:55:00Z
- **Completed:** 2026-03-28T13:05:26Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Traced the full const auto-borrow code path for bridge struct method calls: `is_direct_call = false` for field_expr callees excludes method calls from the auto-borrow block; `!sig.is_bridge` excludes direct bridge calls
- Confirmed the compiler generates correct by-value call sites for `texture: Texture` bridge params — the Tamga `const &Texture` workaround was written against pre-Phase-25 behavior
- Added two unit tests in `src/mir.zig` covering the exact edge cases: bridge struct method with error-union return and direct bridge function with error-union return
- Expanded the comment on the `is_bridge` guard to explicitly document all covered scenarios

## Task Commits

1. **Task 1 + 2: Diagnose, test, and document bridge const auto-borrow guard** - `7f7ad65` (fix)

## Files Created/Modified
- `src/mir.zig` - Two unit tests + expanded guard comment; 178 lines added

## Decisions Made
- No code change to the guard logic was needed — Phase 25's `is_bridge` flag already correctly excludes bridge calls in all forms (direct, method, error-union return)
- The Tamga `createMaterial` workaround (`texture: const &Texture`) can be removed: change back to `texture: Texture` in tamga_vk3d.orh and `texture: Texture` in the sidecar; the compiler generates by-value call sites correctly
- Two tests kept (not merged into one) for clarity: the struct method case and direct call case test different code paths in `resolveCallSig`

## Deviations from Plan

### Diagnosis Result

The plan expected a bug to be found and fixed in the core logic. Investigation revealed:
- The bug was real before Phase 25 (which introduced `is_bridge` on FuncSig)
- After Phase 25, the guard already prevents const auto-borrow for all bridge calls
- The Tamga workaround was never removed when Phase 25 fixed the compiler

The unit tests were still added as specified — they confirm correctness and prevent regression.

---

**Total deviations:** 0 code changes; tests written as planned
**Impact on plan:** Tests pass, behavior confirmed correct. The Tamga workaround removal is a follow-up user action (update tamga_vk3d.orh + sidecar).

## Issues Encountered
- None — diagnosis was straightforward once the code path was traced

## Known Stubs
None — no stubs or placeholders.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- `src/mir.zig` const auto-borrow behavior is verified with tests
- Tamga workaround removal: user can change `texture: const &Texture` → `texture: Texture` in `tamga_vk3d.orh` and `texture: *const Texture` → `texture: Texture` in `tamga_vk3d.zig`'s `createMaterial` sidecar method; update `tamga/docs/bugs.md` to mark the bug as fixed

---
*Phase: quick*
*Completed: 2026-03-28*
