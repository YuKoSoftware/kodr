# Requirements: Orhon Compiler

**Defined:** 2026-03-28
**Core Value:** A clean, correct compiler with zero workarounds — every bug fixed, every error propagated, every code path honest.

## v0.16 Requirements

Requirements for v0.16 Bug Fixes milestone. Each maps to roadmap phases.

### Codegen

- [ ] **CGN-01**: `const &BridgeStruct` parameter emits pointer pass (`&arg`) instead of by-value
- [ ] **CGN-02**: Bridge struct value params in error-union functions stay by-value (no silent `*const` promotion)
- [ ] **CGN-03**: Sidecar `export fn` generates `pub export fn` so bridge functions are accessible
- [ ] **CGN-04**: Cross-module `is` operator emits tagged union check instead of `@TypeOf` comparison
- [ ] **CGN-05**: `Async(T)` reports compile error instead of silently mapping to `void`

### Parser

- [ ] **PRS-01**: Negative float/int literals accepted as function call arguments (`-0.5`, `-1`)

### Build System

- [ ] **BLD-01**: Multi-file module with Zig sidecar resolves without "file exists in two modules" error
- [ ] **BLD-02**: `#cimport` bridge file adds include path for module-relative headers
- [ ] **BLD-03**: `#cimport source:` generates `linkSystemLibrary` for owning module
- [ ] **BLD-04**: Cross-compilation `-win_x64` passes valid step name to Zig build
- [ ] **BLD-05**: `orhon build -fast` uses standard cache directories (no leak into `bin/`)

### Documentation

- [ ] **DOC-01**: TODO.md updated — mark 4 fixed bugs as fixed (cast_to_enum, null_multi_union, empty_struct, size keyword)

## Future Requirements

None deferred — all known bugs included in v0.16.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Codegen refactor (split into files) | Architecture work, not a bug fix |
| PEG error recovery improvements | Enhancement, not a bug fix |
| Traits / NLL / closures | New features, separate milestone |
| MIR optimization (SSA, inlining, DCE) | Optimization, not correctness |
| LSP improvements | Enhancement, not a bug fix |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CGN-01 | TBD | Pending |
| CGN-02 | TBD | Pending |
| CGN-03 | TBD | Pending |
| CGN-04 | TBD | Pending |
| CGN-05 | TBD | Pending |
| PRS-01 | TBD | Pending |
| BLD-01 | TBD | Pending |
| BLD-02 | TBD | Pending |
| BLD-03 | TBD | Pending |
| BLD-04 | TBD | Pending |
| BLD-05 | TBD | Pending |
| DOC-01 | TBD | Pending |

**Coverage:**
- v0.16 requirements: 12 total
- Mapped to phases: 0
- Unmapped: 12

---
*Requirements defined: 2026-03-28*
*Last updated: 2026-03-28 after initial definition*
