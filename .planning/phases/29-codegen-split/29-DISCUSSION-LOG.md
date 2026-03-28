# Phase 29: Codegen Split - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 29-codegen-split
**Areas discussed:** File split strategy, Helper extraction, Legacy AST code
**Mode:** --auto (recommended defaults selected)

---

## File Split Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| By construct type | Declarations, expressions, statements in separate files | ✓ |
| By AST/MIR pair | Group AST and MIR variants separately | |
| By line count | Mechanical split at line boundaries | |

**User's choice:** [auto] By construct type (recommended default)
**Notes:** Natural grouping — when adding a new language feature, you typically touch one construct type.

---

## Helper Extraction

| Option | Description | Selected |
|--------|-------------|----------|
| Separate helpers file | codegen_helpers.zig with emit, typeToZig, queries | ✓ |
| Keep as struct methods | Split struct across files with usingnamespace only | |

**User's choice:** [auto] Separate helpers file (recommended default)
**Notes:** Reduces coupling — helper file has no construct-specific logic.

---

## Legacy AST Code

| Option | Description | Selected |
|--------|-------------|----------|
| Keep pairs together | AST and MIR variants in same file by construct type | ✓ |
| Separate AST file | All legacy AST code in one file | |

**User's choice:** [auto] Keep pairs together (recommended default)
**Notes:** AST variants still used, can't be removed. Keeping pairs together makes future migration easier.

## Claude's Discretion

- Exact file names
- Exact function grouping boundaries (based on call-graph analysis)
- usingnamespace vs explicit re-exports

## Deferred Ideas

None.
