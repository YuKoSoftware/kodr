# Phase 21: Flexible Allocators - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 21-flexible-allocators
**Areas discussed:** Syntax for the 3 modes, Default allocator setup, Custom allocator bridge, Codegen translation

---

## Syntax for the 3 modes

### Allocator as generic param vs .new() arg

| Option | Description | Selected |
|--------|-------------|----------|
| Generic parameter: List(i32, alloc) | Allocator as second generic arg | |
| Constructor arg: List(i32).new(alloc) | Allocator passed to .new() | ✓ |

**User's choice:** Constructor arg via .new(alloc)
**Notes:** User initially proposed generic param syntax `List(i32, my_allocator())`. After analysis showing it would require value expressions in generic arg positions (touching parser, resolver, MIR, codegen) and that Zig allocators are runtime struct fields not comptime type params, user chose `.new(alloc)` as "more clean, honest, and easier to implement."

### Default mode (no allocator arg)

| Option | Description | Selected |
|--------|-------------|----------|
| Global SMP singleton | One SMP allocator shared by all default collections | ✓ |
| Per-collection SMP | Each collection creates its own SMP internally | |

**User's choice:** Global SMP singleton

### Three-mode syntax confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| Confirmed syntax | Mode 1: List(i32).new(), Mode 2: List(i32).new(arena.allocator()), Mode 3: var a = smp.allocator(); List(i32).new(a) | ✓ |

**User's choice:** Confirmed all three modes as described

---

## Default allocator setup

### SMP singleton location

| Option | Description | Selected |
|--------|-------------|----------|
| In collections.zig sidecar | collections.zig declares module-level SMP singleton | ✓ |
| In allocator.zig sidecar | allocator.zig owns the singleton, collections imports it | |
| Generated per-module | Each generated .zig file gets its own SMP | |

**User's choice:** In collections.zig sidecar

### SMP cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-cleanup | OS reclaims at exit, no user-facing .deinit() | ✓ |
| User must call deinit | User responsible for cleanup function | |

**User's choice:** Auto-cleanup

---

## Custom allocator bridge

### Interface enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| Zig handles it | No Orhon-side enforcement, Zig gives type errors | ✓ |
| Orhon enforces interface | Compiler checks allocator type | |

**User's choice:** Let Zig handle type errors

### Custom allocator authoring path

| Option | Description | Selected |
|--------|-------------|----------|
| Zig sidecar expected | Custom allocators written in Zig via bridge | ✓ |
| Pure Orhon option too | Allow Orhon-native allocator structs | |

**User's choice:** Zig sidecar expected

---

## Codegen translation

### .new(alloc) emission strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Struct literal with field | .new(a) → .{ .alloc = a } | ✓ |
| Constructor function in sidecar | Add newWithAllocator() to collections.zig | |

**User's choice:** Struct literal with alloc field

### String interpolation allocator

| Option | Description | Selected |
|--------|-------------|----------|
| Use global SMP | Switch interpolation temp buffers to SMP | ✓ |
| Keep page_allocator for internals | Keep page_allocator for compiler-generated code | |

**User's choice:** Use global SMP for consistency

---

## Claude's Discretion

- SMP singleton initialization strategy (lazy vs eager)
- collections.zig internal refactoring details
- MIR annotation changes (if needed)

## Deferred Ideas

None — discussion stayed within phase scope
