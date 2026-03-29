# Phase 34: Main Split - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 34-main-split
**Areas discussed:** Function grouping, Embed file placement, Command dispatch granularity
**Mode:** --auto (all decisions auto-selected)

---

## Function Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| By logical domain | Each responsibility area becomes its own file (CLI, pipeline, init, stdlib, interface) | ✓ |
| By call frequency | Group functions by how often they call each other | |
| Minimal split | Only extract pipeline, keep rest in main | |

**User's choice:** [auto] By logical domain (recommended default — matches codegen/lsp/mir split pattern)
**Notes:** Consistent with all prior splits (Phase 29, 32, 33) which split by domain/struct boundary.

---

## Embed File Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Move with consumer | @embedFile constants travel to the module that uses them | ✓ |
| Centralize in constants file | All embeds in one shared file | |
| Keep in main.zig | Leave embeds in main, import from split files | |

**User's choice:** [auto] Move with consumer (recommended — keeps each module self-contained)
**Notes:** Template embeds go with init module, stdlib embeds go with stdlib bundler module.

---

## Command Dispatch Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Group with pipeline | analysis/debug/gendoc runners live alongside runPipeline | ✓ |
| Separate commands.zig | Each command runner in its own module | |
| Keep in main.zig | Small runners stay in the dispatch file | |

**User's choice:** [auto] Group with pipeline (recommended — they're small command runners, not separate domains)
**Notes:** Planner has discretion to separate if coupling analysis shows otherwise.

---

## Claude's Discretion

- Exact file names
- Whether command runners ultimately separate from pipeline
- Function-to-file assignments for shared helpers
- Import/re-export mechanism

## Deferred Ideas

None
