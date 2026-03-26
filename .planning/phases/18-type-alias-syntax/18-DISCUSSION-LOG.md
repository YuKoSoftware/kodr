# Phase 18: Type Alias Syntax - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 18-type-alias-syntax
**Mode:** Auto (all decisions auto-selected)
**Areas discussed:** Syntax, Scope, RHS types, Codegen strategy, DeclTable registration

---

## Syntax Form

| Option | Description | Selected |
|--------|-------------|----------|
| `const Name: type = T` | Reuses existing const declaration pattern | [auto] |
| `pub type Name = T` | New keyword-level syntax (GOAL.md form) | |

**User's choice:** `const Name: type = T` (decided in prior conversation — feedback memory)
**Notes:** User argued type annotation should be `type` since the alias stores a type. Consistent with `name: Type = value` pattern. GOAL.md is stale.

---

## Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level + structs | Same placement as const_decl | [auto] |
| Top-level only | Restrict to module scope | |
| Everywhere | Including function bodies | |

**User's choice:** Top-level + structs + function bodies (recommended default)
**Notes:** Zig supports local const type aliases, and const_decl already works everywhere.

---

## RHS Type Forms

| Option | Description | Selected |
|--------|-------------|----------|
| All type forms | Primitives, generics, pointers, function types, etc. | [auto] |
| Primitives + named types only | Restrict to simple aliases | |

**User's choice:** All type forms (recommended default)
**Notes:** The grammar `type` rule already handles all forms — no restriction needed.

---

## Codegen Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Detect `: type` annotation, emit `const Name = <rhs>` | Drop annotation, RHS is type | [auto] |
| New AST node kind `type_alias_decl` | Separate from const_decl | |

**User's choice:** Detect `: type` annotation (recommended default)
**Notes:** Mirrors compt pattern — flag/annotation detection, not new node kind.

---

## DeclTable Registration

| Option | Description | Selected |
|--------|-------------|----------|
| Use existing `types` hashmap | Already exists in DeclTable | [auto] |
| Extend `vars` with type flag | Add `is_type_alias` to VarSig | |

**User's choice:** Use existing `types` hashmap (recommended default)
**Notes:** `DeclTable.types` already has comment "type aliases and compt types" — designed for this.

---

## Claude's Discretion

- Detection mechanism (type annotation == `type` keyword) vs new AST flag
- Test fixture design and example module placement
- Whether builder needs changes or const_decl handling is sufficient as-is

## Deferred Ideas

None — auto mode stayed within phase scope.
