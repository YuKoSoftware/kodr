# Phase 22: `throw` Statement - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 22-throw-statement
**Areas discussed:** Throw semantics, Type narrowing scope, Chained throw, Error message wording
**Mode:** --auto (all defaults selected)

---

## Throw Semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Named variables only | Type narrowing requires a variable to narrow | ✓ |
| Any expression | `throw divide(10,0)` — no variable to narrow, less useful | |

**User's choice:** Named variables only (auto-selected recommended default)
**Notes:** Expressions can't be narrowed — only named variables benefit from type narrowing after throw.

---

## Type Narrowing Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Rest of function | Throw guarantees error gone everywhere after | ✓ |
| Rest of block | Conservative, re-check needed in outer scope | |

**User's choice:** Rest of function (auto-selected recommended default)
**Notes:** Throw is a hard guarantee — the error case is removed. Block-scoped narrowing would be unnecessarily conservative.

---

## Chained Throw

| Option | Description | Selected |
|--------|-------------|----------|
| Multiple throws allowed | Each narrows one variable independently | ✓ |
| Single throw per function | Only one error union can be thrown | |

**User's choice:** Multiple throws allowed (auto-selected recommended default)
**Notes:** Functions often call multiple error-returning functions. Each needs its own throw.

---

## Error Message Wording

| Option | Description | Selected |
|--------|-------------|----------|
| Claude's discretion | Standard compiler error wording | ✓ |
| User-specified wording | Exact error text decided now | |

**User's choice:** Claude's discretion (auto-selected recommended default)

---

## Claude's Discretion

- Error message wording for compile errors
- Internal MIR representation approach
- Whether propagation checker or new mechanism handles throw validation

## Deferred Ideas

None
