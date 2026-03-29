# Phase 35: Zig Runner Split - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 35-zig-runner-split
**Areas discussed:** File split boundaries, Helper placement, MultiTarget location, Test distribution
**Mode:** --auto (all decisions auto-selected)

---

## File Split Boundaries

| Option | Description | Selected |
|--------|-------------|----------|
| 4 files: runner, single-build, multi-build, discovery | Matches ROADMAP.md success criteria exactly | ✓ |
| 3 files: runner, build-gen (both), discovery | Fewer files but build-gen would be ~1150 lines | |
| 5+ files: runner, single, multi, discovery, helpers | More granular but helpers file would be tiny | |

**User's choice:** [auto] 4 files — matches ROADMAP.md success criteria
**Notes:** Natural code boundaries align perfectly with the 4-file split. buildZigContent (~560 lines) and buildZigContentMulti (~593 lines) are independently large enough to justify separate files.

---

## Helper Function Placement

| Option | Description | Selected |
|--------|-------------|----------|
| With single-target build gen | Primary consumer, multi-target imports them | ✓ |
| Separate helpers file | Clean separation but tiny file (~80 lines) | |
| Duplicated in both files | No cross-file deps but DRY violation | |

**User's choice:** [auto] With single-target build gen — minimizes file count
**Notes:** emitLinkLibs, emitIncludePath, emitCSourceFiles, generateSharedCImportFiles are used by both build generators but defined alongside buildZigContent.

---

## MultiTarget Struct Location

| Option | Description | Selected |
|--------|-------------|----------|
| With multi-target build gen | Sole consumer of the struct | ✓ |
| With single-target build gen | Near where it's defined currently | |
| In runner core | Accessible to buildAll which passes it | |

**User's choice:** [auto] With multi-target build gen — struct follows its primary consumer
**Notes:** buildAll receives MultiTarget as a parameter but doesn't construct it. The struct definition belongs with buildZigContentMulti.

---

## Test Distribution

| Option | Description | Selected |
|--------|-------------|----------|
| Tests move with their function | Consistent with phases 29/33/34 | ✓ |
| All tests stay in runner core | Simpler but doesn't follow convention | |

**User's choice:** [auto] Tests move with their function — consistent with all prior phases
**Notes:** 10 buildZigContent* tests → single-target, 5 buildZigContentMulti tests → multi-target, 1 findZig test → discovery, formatTestOutput test → runner.

---

## Claude's Discretion

- Exact file names beyond the `zig_runner_*` prefix
- Re-export mechanism (usingnamespace vs explicit)
- Edge-case helper placement

## Deferred Ideas

None — discussion stayed within phase scope
