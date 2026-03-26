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

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Theme |
|-----------|--------|-------|----------|-------|
| v0.10 | 7 | 7 | 1 day | Bug fixes |
| v0.11 | 4 | 4 | 1 day | Language simplification |
| v0.12 | 3 | 2 | 1 day | Quality & polish |
| v0.13 | 4 | 5 | 1 day | Real-world compatibility |
