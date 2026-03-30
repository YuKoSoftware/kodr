# Phase 4: Codegen Correctness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 04-codegen-correctness
**Areas discussed:** Diagnostic strategy, Fix ordering, Validation scope
**Mode:** --auto (all areas auto-selected, recommended defaults chosen)

---

## Diagnostic Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Generate and inspect tester.zig | Trace 9 failing lines back to codegen paths | ✓ |
| Start from BUG-01/02 fixes | Assume known bugs are the cause | |
| Fuzz-based approach | Generate variants to isolate pattern | |

**User's choice:** [auto] Generate and inspect tester.zig (recommended default)
**Notes:** The error pattern `type 'i32' has no members` is specific — tracing from generated Zig back to codegen is the fastest diagnostic path.

---

## Fix Ordering

| Option | Description | Selected |
|--------|-------------|----------|
| Diagnose tester first | BUG-01/02 may not be the root cause | ✓ |
| Fix BUG-01/02 first | They were identified as related in prior analysis | |

**User's choice:** [auto] Diagnose tester first (recommended default)
**Notes:** The 9 errors may have a common root cause unrelated to BUG-01/02. Diagnosing first avoids fixing the wrong thing.

---

## Validation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Check DeclTable for type existence | Validate at Orhon level before codegen | ✓ |
| Trust Zig to catch it | Keep current behavior, improve error message | |

**User's choice:** [auto] Check DeclTable for type existence (recommended default)
**Notes:** Producing Orhon-level errors is better UX than deferring to confusing Zig errors.

---

## Claude's Discretion

- Exact fix ordering within the phase
- Whether root cause is in codegen field access or MIR type annotation
- Regression test design

## Deferred Ideas

None
