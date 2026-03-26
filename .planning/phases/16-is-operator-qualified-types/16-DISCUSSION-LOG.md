# Phase 16: `is` Operator Qualified Types - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 16-is-operator-qualified-types
**Areas discussed:** Grammar syntax, Builder handling, Codegen mapping, Validation scope
**Mode:** auto (all defaults selected)

---

## Grammar Syntax

| Option | Description | Selected |
|--------|-------------|----------|
| Extend to `IDENTIFIER ('.' IDENTIFIER)*` | Reuses existing dot token, matches dotted paths | ✓ |
| Accept full `type_expr` on RHS | More flexible but over-engineered for this use case | |

**User's choice:** [auto] Extend to `IDENTIFIER ('.' IDENTIFIER)*` (recommended default)
**Notes:** Simplest change that covers the Tamga use case without introducing new grammar concepts

---

## Builder Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Build `field_expr` chain for dotted, `identifier` for simple | Reuses existing AST node type | ✓ |
| New `qualified_type` AST node | Clean but adds unnecessary complexity | |

**User's choice:** [auto] Build `field_expr` chain for dotted, `identifier` for simple (recommended default)
**Notes:** `field_expr` already exists and represents dotted paths throughout the codebase

---

## Codegen Mapping

| Option | Description | Selected |
|--------|-------------|----------|
| 1:1 mapping — `mod.Type` emits `mod.Type` in Zig | Pure translator, consistent with CLAUDE.md | ✓ |
| Map to Zig-specific discriminant patterns | Would require semantic knowledge codegen doesn't have | |

**User's choice:** [auto] 1:1 mapping (recommended default)
**Notes:** Codegen is a pure 1:1 translator per CLAUDE.md architecture

---

## Validation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to Zig | No compiler validation, consistent with Phase 15 | ✓ |
| Add module existence check | Would require import resolution in `is` handling | |

**User's choice:** [auto] Defer to Zig (recommended default)
**Notes:** Consistent with D-07 from Phase 15 and the project's general approach

---

## Claude's Discretion

- Token scanning loop implementation for dotted identifiers
- `field_expr` chain construction order
- Arbitrary union discriminant handling with qualified types
- Test fixture design

## Deferred Ideas

None — discussion stayed within phase scope
