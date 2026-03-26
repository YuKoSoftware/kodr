# Phase 17: Void in Error Unions - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 17-unit-type-support
**Areas discussed:** Naming, Grammar feasibility, Codegen mapping, Validation scope
**Mode:** auto (all defaults selected) — with user input on naming decision

---

## Naming

| Option | Description | Selected |
|--------|-------------|----------|
| `void` | Already exists as keyword, reuse in union position | ✓ |
| `Unit` | New type name from type theory (Rust, Kotlin) | |
| `Void` | Capitalized, used by Swift | |
| `None` | Conflicts with null semantics | |

**User's choice:** `void` — explicitly confirmed by user after discussion about conflict risk
**Notes:** User asked if `void` would conflict since it's already a datatype. Confirmed no conflict — `void` already works in return position, just needs to be accepted in union position too. User agreed this is the right choice.

---

## Grammar Feasibility

| Option | Description | Selected |
|--------|-------------|----------|
| No grammar changes needed | `void` already in `keyword_type`, accepted by `paren_type` | ✓ |
| Add explicit void_union rule | Over-engineered, grammar already handles it | |

**User's choice:** [auto] No grammar changes needed (recommended default)
**Notes:** Codebase scout confirmed grammar, builder, type resolver, and codegen all appear to support `(Error | void)` already

---

## Codegen Mapping

| Option | Description | Selected |
|--------|-------------|----------|
| 1:1 → `anyerror!void` | Zig native, valid Zig | ✓ |

**User's choice:** [auto] 1:1 mapping (recommended default)
**Notes:** `anyerror!void` is valid Zig and exactly what Zig uses for fallible void functions

---

## Claude's Discretion

- Which validation passes need changes vs already handle void
- Test fixture and bridge function design
- Whether this phase is mostly test coverage vs actual code changes

## Deferred Ideas

None — discussion stayed within phase scope
