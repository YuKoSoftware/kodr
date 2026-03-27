# Phase 24: `#cimport` Unification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 24-cimport-unification
**Areas discussed:** Deprecation strategy, Block syntax parsing, Auto-derive conventions, Tamga migration scope

---

## Deprecation Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Hard remove | Old directives become parse errors immediately | ✓ |
| Deprecation warning | Old directives still compile but emit warning | |
| You decide | Let Claude pick | |

**User's choice:** Hard remove
**Notes:** Tamga is the only known consumer and user controls both projects — no need for a transition period.

---

## Block Syntax Parsing

| Option | Description | Selected |
|--------|-------------|----------|
| Colon suffix | `include: "..."` | ✓ |
| Equals sign | `include = "..."` (matches existing `#field = value`) | |

**User's choice:** Colon suffix

**Follow-up — Delimiters:**

| Option | Description | Selected |
|--------|-------------|----------|
| Comma-separated | `{ include: "...", source: "..." }` | ✓ |
| Newline-separated | Entries on separate lines without commas | |
| Both allowed | Either delimiter works | |

**User's choice:** Comma-separated only

**Follow-up — Multi-line:**

| Option | Description | Selected |
|--------|-------------|----------|
| Allow multi-line | `{` ... `}` can span lines | ✓ |
| Single-line only | Must fit on one line | |

**User's choice:** Allow multi-line

**Follow-up — Key extensibility:**

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed keys only | Only `include` and `source`, unknown keys are errors | ✓ |
| Extensible | Allow arbitrary keys for future use | |

**User's choice:** Fixed keys only
**Notes:** User asked what future keys might be needed. Claude suggested `flags` and `path` as hypotheticals but noted `include` + `source` covers all Tamga cases and adding a new key later is a trivial one-line change. User agreed fixed is cleaner.

---

## Auto-derive Conventions

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-derive with override | Default `name/name.h`, override when wrong | |
| Always explicit | `include:` required in all cases | ✓ |
| You decide | Let Claude pick | |

**User's choice:** Always explicit — no auto-derive
**Notes:** SDL3 header (`SDL3/SDL.h`) doesn't match the `name/name.h` convention, confirming that auto-derive would be unreliable. User confirmed the bare `#cimport "lib"` form (no block) should be invalid.

**Follow-up — Library name purpose:**
User asked if the quoted name is needed when `include:` already points to the header. Claude explained the name serves as (1) linker name for `linkSystemLibrary` and (2) identity key for deduplication — independent of the header path. User agreed to keep it required.

---

## Tamga Migration Scope

**Migration map presented and confirmed.**

**Follow-up — Cross-module C library sharing:**

| Option | Description | Selected |
|--------|-------------|----------|
| Owner only | One `#cimport` per lib, others `import` the bridge | ✓ |
| Each declares own | Every module that needs C types declares `#cimport` | |

**User's choice:** Owner only — one `#cimport` per library, others import the bridge module.
**Notes:** User asked if this was the right call given the uniqueness constraint. Claude confirmed it matches the existing shared cImport architecture.

**Follow-up — Transitive C type visibility:**

| Option | Description | Selected |
|--------|-------------|----------|
| Transitive | Importing a bridge gives access to its C types | ✓ |
| Opaque | Bridge must wrap and re-export everything explicitly | |

**User's choice:** Transitive
**Notes:** User asked whether downstream modules should see raw C types. Claude noted that opaque wrapping would require `tamga_vk3d` to manually re-export dozens of Vulkan types — defeating the purpose of thin bridges. User agreed transitive is practical.

---

## Claude's Discretion

- Implementation ordering of compiler passes
- Source-only library detection logic
- Test structure and organization

## Deferred Ideas

None — discussion stayed within phase scope
