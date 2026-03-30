# Deferred Items — Phase 16

## Cross-module type annotation bug

**Found during:** 16-01 Task 3
**Issue:** `const x: tester.IsTestType = ...` in tester_main.orh generates `const x: tester = ...` in main.zig (loses the field name from the qualified type). Pre-existing bug in typeToZig for cross-module named types.
**Workaround used:** Type inference (`const x = tester.IsTestType(...)`) avoids the bug.
**Fix needed:** `typeToZig` for `type_named` or qualified types should emit the full `module.TypeName` path.
**Scope:** Out of scope for Phase 16 (is operator qualified types).
