# Milestones

## v0.13 Tamga Compatibility (Shipped: 2026-03-26)

**Phases completed:** 7 phases, 7 plans, 12 tasks

**Key accomplishments:**

- Parser fuzz test using std.testing.fuzz added to src/peg.zig; standalone harness extended to 5 strategies; COMPILER.md documents complete fuzz infrastructure
- Eliminated intermittent test race via std.testing.tmpDir, removed dead ziglib testbed, confirmed 5/5 clean runs and 123/123 test passes
- Full pipeline wired for `pub enum(u32) Scancode { A = 4, B = 5 }` — PEG grammar, AST, builder, MIR, and codegen all updated in 5 files, ~30 lines changed.
- Grammar, builder, and codegen changes enabling `ev is module.Type` cross-module type checks, emitting `@TypeOf(val) == mod.Type` Zig via new emitTypePath/emitTypeMirPath helpers; all 243 tests pass.
- End-to-end runtime test coverage for `(Error | void)` — codegen correctly emits `anyerror!void`, bare return produces void success, error path produces error; example module updated as living language manual
- 1. [Rule 1 - Bug] Return type mismatch for variables typed with module-level aliases

---

## v0.11 Language Simplification (Shipped: 2026-03-25)

**Phases completed:** 4 phases, 5 plans, 5 tasks

**Key accomplishments:**

- Const auto-borrow: `const` non-primitive values auto-pass as `const &` at call sites — no more silent deep copies
- Ptr syntax simplified: `const p: Ptr(T) = &x` replaces verbose `.cast()` — type annotation drives pointer safety level
- Old `Ptr(T).cast(&x)` and `Ptr(T, &x)` syntax removed — compile error with clear message
- Tamga companion project and all fixtures updated for new semantics
- `.Error` fallback codegen fixed: correct Zig `if/else` pattern instead of `catch`
- 240/240 tests pass across all 11 stages

**Stats:** 35 files changed, 2812 insertions, 256 deletions
**Git range:** 51aceec..ffb8c0e (2026-03-25)

---
