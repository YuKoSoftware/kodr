# Test Coverage Review Plan

## Status: In Progress (chunks 1-4 done)

## Overview

- **Current test count**: 298 (511 unit test blocks + 11 shell integration scripts)
- **Files with unit tests**: 63 of 97 `.zig` files
- **Files without unit tests**: 34 `.zig` files
- **Integration tests**: `test/01_unit.sh` through `test/11_errors.sh` (1617 lines total)
- **Test fixtures**: 30+ `.orh` files in `test/fixtures/`
- **Snapshot tests**: 4 codegen snapshots in `test/snapshots/`

## What to Review

For each chunk, the agent should:
1. Read the source files and their existing tests
2. Identify untested public functions and code paths
3. Check for missing edge cases and negative tests
4. Verify test-spec alignment (tests match language spec in `docs/`)
5. Report findings — do NOT write tests, only list gaps

## Chunks

### Chunk 1 — Lexer & Token Map ✅

**Source**: `src/lexer.zig`, `src/peg/token_map.zig`
**Existing tests**: Both have test blocks

**Review focus**:
- All token kinds have at least one lexing test
- Edge cases: empty input, max-length identifiers, nested string escapes
- Numeric literal formats: hex, binary, octal, float with exponent
- Error tokens: unterminated strings, invalid escapes

**Added**: 12 tests — invalid prefix literals, unterminated strings (newline + EOF), EOF in escape, `mut` as identifier, column tracking, number before `..` and `.x`, `@`/`#`/`%=` tokens

---

### Chunk 2 — PEG Engine & Grammar ✅

**Source**: `src/peg.zig`, `src/peg/engine.zig`, `src/peg/grammar.zig`, `src/peg/capture.zig`
**Existing tests**: All have test blocks

**Review focus**:
- Engine: memoization correctness, backtracking, left recursion handling
- Grammar: every grammar rule exercised, ambiguous rule detection
- Capture: tree construction, nested captures, empty captures

**Added**: 13 tests — positive lookahead (match, fail, non-consumption), token_text matching, repeat1, unknown rule, matchAll partial, memoization (success + failure), grammar `&`/`!` prefix nodes, empty grammar, token_text node

**Deferred gaps** (covered indirectly by integration tests):
- capture.zig `evalSequence` backtracking — partial children discarded on failure
- capture.zig `evalChoice` backtracking — same issue
- capture.zig `captureProgram` rejection of partial match
- engine.zig `getError` with empty token stream
- engine.zig zero-length match guard in `evalRepeat`

---

### Chunk 3 — AST Builder ✅

**Source**: `src/peg/builder.zig`, `src/peg/builder_decls.zig`, `src/peg/builder_exprs.zig`, `src/peg/builder_stmts.zig`, `src/peg/builder_types.zig`
**Existing tests**: Only `builder.zig` has tests; 4 satellites have none

**Review focus**:
- Every `NodeKind` has a builder path that's tested
- Missing builder satellites coverage (decls, exprs, stmts, types)
- Malformed capture trees produce clean errors not crashes

**Added**: 7 tests — string interpolation, postfix index, `is` type check, match guard, union type, enum decl

**Deferred gaps** (covered by integration tests):
- `buildExprOrAssignment` compound assignment operators
- `buildElifChain` deep nesting
- `buildDestructDecl` name-splitting
- `buildFor` index variable pop-last convention
- `collectCallArgs` named vs positional arguments
- Malformed capture tree error paths

---

### Chunk 4 — Parser & Module Resolution ✅

**Source**: `src/parser.zig`, `src/module.zig`, `src/module_parse.zig`, `src/scope.zig`
**Existing tests**: `module.zig` and `scope.zig` have tests; `parser.zig` and `module_parse.zig` do not

**Review focus**:
- AST node creation and field access
- Module resolution: circular imports, missing modules, multi-file modules
- File offset resolution (resolveFileLoc)
- Scope push/pop, variable shadowing

**Added**: 13 tests — Operator.parse (all 27 + unknown), Operator.toZig round-trip, isComparison, MetadataField.parse, parseBuildType, formatExpectedSet (1 and 2 items), readModuleName (comment, no module), extractVersion (wrong count)

**Deferred gaps**:
- Circular import integration test fixture (no `fail_circular.orh`)
- `module_parse.zig` parse error formatting branches (4 distinct message formats)
- `formatExpectedSet` with 3+ items (Oxford comma)
- Unknown import scope / unknown `#build` type negative tests

---

### Chunk 5 — Declarations & Type Resolution

**Source**: `src/declarations.zig`, `src/interface.zig`, `src/sema.zig`, `src/resolver.zig`, `src/resolver_exprs.zig`, `src/resolver_validation.zig`
**Existing tests**: `declarations.zig` and `resolver.zig` have tests; 4 files have none

**Review focus**:
- All declaration kinds collected (func, struct, enum, const, var, blueprint)
- Generic type resolution, type aliases, union types
- Cross-module imports resolved correctly
- Validation: duplicate names, type mismatches, invalid constructs

---

### Chunk 6 — Ownership & Borrow Checking

**Source**: `src/ownership.zig`, `src/ownership_checks.zig`, `src/borrow.zig`, `src/borrow_checks.zig`, `src/propagation.zig`
**Existing tests**: `ownership.zig`, `borrow.zig`, `propagation.zig` have tests; `*_checks.zig` files do not

**Review focus**:
- Move semantics: use-after-move, double move, move in loop
- Borrow rules: mut& exclusion, const& coexistence, borrow lifetime
- Error propagation: throw narrowing, error union validation
- Cross-reference with `test/fixtures/fail_ownership.orh` and `fail_borrow.orh`

---

### Chunk 7 — MIR Annotation & Lowering

**Source**: `src/mir/mir.zig`, `src/mir/mir_types.zig`, `src/mir/mir_node.zig`, `src/mir/mir_annotator.zig`, `src/mir/mir_annotator_nodes.zig`, `src/mir/mir_lowerer.zig`, `src/mir/mir_registry.zig`
**Existing tests**: `mir_types.zig`, `mir_annotator.zig`, `mir_registry.zig` have tests; 4 files have none

**Review focus**:
- Every NodeKind annotated by MIR
- TypeClass coverage: all variants exercised
- NodeMap population completeness
- Union registry: flattening, dedup, tag generation

---

### Chunk 8 — Code Generation

**Source**: `src/codegen/codegen.zig`, `src/codegen/codegen_decls.zig`, `src/codegen/codegen_exprs.zig`, `src/codegen/codegen_stmts.zig`, `src/codegen/codegen_match.zig`
**Existing tests**: Only `codegen.zig` has tests; 4 satellites have none
**Snapshot tests**: `test/snapshots/` (4 scenarios)

**Review focus**:
- Generated Zig compiles for all language constructs
- Match codegen: enum match, string match, range match, guard match, union match
- Snapshot test coverage vs actual language features
- Missing snapshots for newer features (blueprints, unions, generics)

---

### Chunk 9 — Pipeline & CLI

**Source**: `src/pipeline.zig`, `src/pipeline_passes.zig`, `src/pipeline_build.zig`, `src/cli.zig`, `src/main.zig`, `src/init.zig`, `src/commands.zig`
**Existing tests**: `pipeline_build.zig` and `cli.zig` have tests; 5 files have none
**Shell tests**: `test/03_cli.sh`, `test/04_init.sh`, `test/05_compile.sh`

**Review focus**:
- CLI flag combinations tested
- Pipeline pass ordering and error gating
- Incremental compilation: cache hit/miss paths
- Init scaffolding: all files created, correct content

---

### Chunk 10 — Zig Runner & Build

**Source**: `src/zig_runner/zig_runner.zig`, `src/zig_runner/zig_runner_build.zig`, `src/zig_runner/zig_runner_discovery.zig`, `src/zig_runner/zig_runner_multi.zig`
**Existing tests**: `zig_runner.zig`, `zig_runner_discovery.zig`, `zig_runner_multi.zig` have tests; `zig_runner_build.zig` does not
**Shell tests**: `test/06_library.sh`, `test/07_multimodule.sh`

**Review focus**:
- Build script generation for all target types (exe, lib, staticlib, dynlib)
- Multi-module linking order
- Zig discovery: PATH fallback, adjacent binary
- Cross-compilation targets

---

### Chunk 11 — Zig Module Interop & Cache

**Source**: `src/zig_module.zig`, `src/cache.zig`, `src/std_bundle.zig`
**Existing tests**: `zig_module.zig` and `cache.zig` have tests; `std_bundle.zig` does not

**Review focus**:
- Zig-to-Orhon type mapping completeness
- `.zon` dependency file parsing
- Cache invalidation: timestamp comparison, dependency graph changes
- Stdlib bundle extraction and versioning

---

### Chunk 12 — Tools (Formatter, Docgen, Fuzz)

**Source**: `src/formatter.zig`, `src/docgen.zig`, `src/syntaxgen.zig`, `src/zig_docgen.zig`, `src/fuzz.zig`
**Existing tests**: `formatter.zig`, `syntaxgen.zig`, `zig_docgen.zig` have tests; `docgen.zig` and `fuzz.zig` do not

**Review focus**:
- Formatter idempotency (format twice = same result)
- Docgen: all declaration kinds produce output
- Fuzz: coverage of parser error paths

---

### Chunk 13 — LSP Server

**Source**: `src/lsp/lsp.zig`, `src/lsp/lsp_types.zig`, `src/lsp/lsp_json.zig`, `src/lsp/lsp_analysis.zig`, `src/lsp/lsp_nav.zig`, `src/lsp/lsp_edit.zig`, `src/lsp/lsp_view.zig`, `src/lsp/lsp_semantic.zig`, `src/lsp/lsp_utils.zig`
**Existing tests**: 7 of 9 files have tests; `lsp_types.zig` and `lsp_nav.zig` do not

**Review focus**:
- LSP method dispatch coverage
- Hover, completion, goto-definition, rename
- Diagnostic publishing on parse/type errors
- Malformed JSON-RPC handling

---

### Chunk 14 — Integration Tests & Fixtures

**Source**: `test/03_cli.sh` through `test/11_errors.sh`, `test/fixtures/*.orh`, `test/snapshots/`
**No Zig source** — pure test infrastructure review

**Review focus**:
- Shell test coverage vs compiler features
- Missing negative test fixtures (compare `fail_*.orh` list against error categories)
- Snapshot staleness: do expected outputs match current codegen?
- Runtime test (`test/10_runtime.sh`) coverage of tester.orh features
- Language test (`test/09_language.sh`) coverage of example module features

---

### Chunk 15 — Stdlib Unit Tests

**Source**: All `src/std/*.zig` files (29 files)
**Existing tests**: 26 of 29 files have tests; `console.zig`, `ptr.zig`, `simd.zig` do not

**Review focus**:
- API surface coverage: every pub function tested
- Edge cases: empty inputs, OOM paths, boundary values
- Parser modules (regex, yaml, toml, xml, csv, ini): malformed input handling
- Network modules (http, net): error path coverage
- Thread safety in concurrent modules

---

## Files Without Any Unit Tests (34 total)

These need the most attention:

**Core compiler** (likely tested indirectly via integration):
- `parser.zig`, `module_parse.zig`, `sema.zig`
- `resolver_exprs.zig`, `resolver_validation.zig`
- `ownership_checks.zig`, `borrow_checks.zig`
- `mir.zig`, `mir_node.zig`, `mir_annotator_nodes.zig`, `mir_lowerer.zig`
- `codegen_decls.zig`, `codegen_exprs.zig`, `codegen_stmts.zig`, `codegen_match.zig`
- `pipeline.zig`, `pipeline_passes.zig`

**Tools & infra** (may need direct tests):
- `main.zig`, `init.zig`, `commands.zig`, `constants.zig`
- `interface.zig`, `docgen.zig`, `fuzz.zig`
- `std_bundle.zig`, `zig_runner_build.zig`
- `lsp_types.zig`, `lsp_nav.zig`

**Stdlib** (should have tests):
- `console.zig`, `ptr.zig`, `simd.zig`, `thread.zig`

**Satellites** (tested through hub files):
- `builder_decls.zig`, `builder_exprs.zig`, `builder_stmts.zig`, `builder_types.zig`
