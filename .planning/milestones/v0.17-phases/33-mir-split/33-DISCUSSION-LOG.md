# Phase 33: MIR Split - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 33-mir-split
**Areas discussed:** File grouping, Type sharing pattern, MirNode placement
**Mode:** --auto (all areas auto-selected with recommended defaults)

---

## File Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| By struct boundary | Each major struct gets its own file | [auto] |
| By function type | Group annotate vs lower vs types | |
| Minimal split | Types + everything else | |

**User's choice:** [auto] By struct boundary (recommended default)
**Notes:** Consistent with Phase 29/32 pattern. mir.zig has clear struct boundaries that map naturally to files.

---

## Type Sharing Pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated types module | mir_types.zig holds all shared types | [auto] |
| Inline in mir.zig | Keep types in main file, others import from it | |
| Duplicate where needed | Each file defines what it needs | |

**User's choice:** [auto] Dedicated types module (recommended default)
**Notes:** Matches codegen split helper pattern. Types are small and shared across all consumers.

---

## MirNode Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone file | MirNode in its own file with helpers | [auto] |
| With MirLowerer | MirNode stays with its primary producer | |
| With types | MirNode goes in mir_types.zig | |

**User's choice:** [auto] Standalone file (recommended default)
**Notes:** Success criteria explicitly requires "MirNode struct is in its own file with accessor methods."

---

## Claude's Discretion

- Exact file names beyond `mir_*` prefix
- `usingnamespace` vs explicit re-exports in mir.zig
- Helper function placement for cross-struct utilities

## Deferred Ideas

None — discussion stayed within phase scope.
