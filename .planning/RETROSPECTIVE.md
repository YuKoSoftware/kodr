# Retrospective

## Milestone: v0.13 — Tamga Compatibility

**Shipped:** 2026-03-26
**Phases:** 4 | **Plans:** 5

### What Was Built
- Enum explicit values (`pub enum(u32) Scancode { A = 4, B = 5 }`) — full pipeline: grammar, AST, builder, MIR, codegen
- `is` operator with module-qualified types (`ev is module.Type`) — new emitTypePath helpers
- Void in error unions (`Error | void` → `anyerror!void`) — already supported, added test coverage
- Type alias syntax (`const Speed: type = i32` → `const Speed = i32`) — detection in declarations + codegen

### What Worked
- PEG grammar-first approach made parser changes trivial for all 4 features
- Existing `is_compt`/`returns_type` detection pattern in codegen was directly reusable for type aliases
- Phase 17 required zero compiler changes — revealed that `(Error | void)` already worked, just needed tests
- Single-day milestone execution — all 4 phases completed in one session

### What Was Inefficient
- GOAL.md for Phase 18 had stale syntax (`pub type Alias = T`) contradicting the user's earlier decision (`const Alias: type = T`) — caught during discuss-phase but could have been avoided
- Phase 14 (Gate) was a no-op phase with no plans — should have been folded into Phase 13

### Patterns Established
- Type alias detection via `type_annotation == type_named("type")` — reusable pattern for future compile-time type constructs
- Cross-module type path emission via `emitTypePath`/`emitTypeMirPath` helpers
- MIR enum variant value via reusing `MirNode.literal` field (no new fields needed)

### Key Lessons
- Real-world usage (Tamga) is the best feature discovery mechanism — all 4 features came from actual framework development
- When a feature "already works", adding test coverage is still valuable as a phase — Phase 17 proved the compiler was more capable than documented

## Milestone: v0.14 — Build System

**Shipped:** 2026-03-27
**Phases:** 3 | **Plans:** 6

### What Was Built
- Named Zig modules for bridge .zig files via createModule/addImport — eliminates file-path imports and cross-module duplicate errors
- 9 compiler bug fixes: multi-null union, @enumFromInt, zero-field struct, elif codegen, bridge const auto-borrow, size keyword, shared cImport, #csource, pub export fn
- Tamga framework builds end-to-end with zero workarounds
- Flexible allocator system: .new(alloc) pattern, 3 usage modes (default SMP, inline, external), SMP replaces page_allocator

### What Worked
- Phase 20's systematic bug-by-bug approach (9 bugs in 3 plans) was effective — grouping by subsystem (codegen, build system, verification) kept each plan focused
- Phase 19's named module foundation made Phase 20's shared cImport work straightforward
- Runtime tests for allocator modes caught real codegen bugs (scoped type builder, qualified name resolver)
- Tamga as a real-world stress test continued to surface compiler issues that unit tests wouldn't find

### What Was Inefficient
- Phase 21 committed before Phase 20 in git timeline despite logical dependency — worked out fine but ordering was confusing
- Commit eafffc7 (resolver + zig_runner fixes) happened after Phase 20 SUMMARY was written — fixes are real but undocumented
- Phase 19 never received a formal VERIFICATION.md — work was verified by tests but the process gap remained

### Patterns Established
- struct_methods map with qualified 'StructName.method' keys for cross-bridge method resolution
- Shared cImport wrapper modules derived from header stem + _c suffix
- .new(alloc) as the allocator injection pattern — codegen detects collection type nodes vs user struct nodes

### Key Lessons
- Build system changes (named modules, shared cImport) have cascading benefits — Phase 19's work unblocked both Tamga builds and allocator bridges
- The 3-mode allocator design (default/inline/external) is the right granularity — covers all real use cases without overengineering

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Theme |
|-----------|--------|-------|----------|-------|
| v0.10 | 7 | 7 | 1 day | Bug fixes |
| v0.11 | 4 | 4 | 1 day | Language simplification |
| v0.12 | 3 | 2 | 1 day | Quality & polish |
| v0.13 | 4 | 5 | 1 day | Real-world compatibility |
| v0.14 | 3 | 6 | 2 days | Build system & allocators |
