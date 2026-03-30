# Phase 4: Codegen Correctness - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix the codegen bugs that prevent the tester module from compiling, unblocking 100 runtime tests (stages 09 + 10). Also fix cross-module struct ref-passing (BUG-01) and qualified generic type validation (BUG-02). The gate is: tester module compiles, all 100 tests run and pass.

</domain>

<decisions>
## Implementation Decisions

### Diagnostic strategy
- **D-01:** Generate tester.zig first, inspect the 9 failing lines (791, 802, 813, 826, 840, 853, 882, 912, 1217), trace each back to the codegen path that produced it
- **D-02:** The error pattern `type 'i32' has no members` means codegen is emitting `.field` access on a primitive — likely a field access or method call on a variable that codegen thinks is a struct but is actually `i32`/`u8`
- **D-03:** Diagnose tester failures first before assuming BUG-01/02 are the cause — the root issue may be different or partially overlapping

### Cross-module ref-passing (BUG-01)
- **D-04:** Fix is in codegen call argument generation — when calling an imported module's struct method with `const &T` parameters, codegen must emit `&arg` instead of `arg`
- **D-05:** Codegen needs access to the imported module's DeclTable or MIR argument mode annotations to know which parameters are `const &`

### Qualified generic validation (BUG-02)
- **D-06:** Fix is in resolver — when processing `module.Type(params)` where `is_qualified` is true, check the referenced module's DeclTable for the type's existence
- **D-07:** Produce a clear Orhon-level error instead of deferring to Zig compile time

### Claude's Discretion
- Exact diagnostic approach and fix ordering within the phase
- Whether to fix codegen field access classification or MIR type annotation — whichever is the actual root cause
- Test additions — what regression tests to add for each fix

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Bug documentation
- `docs/TODO.md` — BUG-01 (cross-module ref-passing), BUG-02 (qualified generics), BUG-08 (tester codegen)
- `.planning/codebase/CONCERNS.md` — Known bugs section with file locations and trigger conditions

### Codegen implementation
- `src/codegen.zig` — Main codegen file; call argument generation (~lines 3430-3460), field access (~lines 1786-1801)
- `src/mir.zig` — TypeClass enum, NodeInfo, MirAnnotator — type classification that codegen relies on

### Resolver
- `src/resolver.zig` — Lines 840-845 where qualified names bypass existence checks

### Test fixtures
- `test/fixtures/tester.orh` — The tester module that fails to compile
- `test/fixtures/tester_main.orh` — Test runner harness
- `test/09_language.sh` — Test stage that validates language features
- `test/10_runtime.sh` — Test stage that runs compiled tester binary

### Prior fix context
- `.planning/phases/01-compiler-bug-fixes/` — Phase 1 fixed BUG-01 and BUG-02 at the Orhon level but tester codegen still fails — residual issues remain in generated Zig

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Error Pattern
- 9 errors in generated tester.zig all follow `type 'i32' has no members` or `type 'u8' has no members`
- Lines: 791, 802, 813, 826, 840, 853, 882, 912, 1217
- This means codegen emits `.something` field access on a value that Zig resolves to a primitive type

### Relevant Codegen Paths
- `CodeGen.generateFieldAccess()` — handles `node.field` expressions, uses TypeClass to decide emission
- `CodeGen.generatePtrExpr()` — handles Ptr/RawPtr/VolatilePtr, tested and working (confirmed in earlier analysis)
- `CodeGen.typeToZig()` — translates Orhon types to Zig type strings
- MIR `classifyType()` — determines TypeClass for a node, which codegen uses for emission decisions

### Established Patterns
- MIR annotation table (`NodeMap`) is the bridge between semantic analysis and codegen
- Codegen never re-discovers types — it reads TypeClass from MIR
- If MIR misclassifies a node's type, codegen will emit wrong code

### Integration Points
- Fix must not break example module compilation (test stage 09 validates both example and tester)
- Fix must preserve all existing passing tests (stages 01-08, 11)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — this is a correctness fix. The goal is clear: make the tester module compile and pass.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-codegen-correctness*
*Context gathered: 2026-03-25*
