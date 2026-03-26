---
phase: quick
plan: 260326-izf
type: execute
wave: 1
depends_on: []
files_modified:
  - src/resolver.zig
  - src/templates/main.orh
  - src/templates/example/example.orh
  - src/templates/example/data_types.orh
  - test/fixtures/tester_main.orh
  - test/fixtures/fail_syntax.orh
  - test/fixtures/fail_threads.orh
  - test/fixtures/fail_ownership.orh
  - test/fixtures/fail_functions.orh
  - test/fixtures/fail_enums.orh
  - test/fixtures/fail_propagation.orh
  - test/fixtures/fail_structs.orh
  - test/fixtures/fail_borrow.orh
  - test/fixtures/fail_scope.orh
  - test/fixtures/fail_match.orh
  - test/fixtures/fail_types.orh
  - test/05_compile.sh
  - test/06_library.sh
  - test/08_codegen.sh
  - test/11_errors.sh
  - docs/02-types.md
  - docs/03-variables.md
  - docs/11-modules.md
autonomous: true
---

<objective>
Remove the #bitsize metadata mechanic from the Orhon compiler. Bare numeric literals
still require explicit type annotations — the error message changes from "requires
explicit type or #bitsize" to "requires explicit type". Inference still works when
unambiguous (function returns, other typed variables, etc).

Purpose: Simplify the language by removing a configuration footgun. Explicit types
are the right approach; type aliases (coming later) will make this ergonomic.

Output: Compiler with no bitsize field, updated error message, all fixtures/templates/docs updated.
</objective>

<tasks>

<task type="auto">
  <name>Task 1: Remove bitsize from resolver, update error message</name>
  <files>src/resolver.zig</files>
  <action>
  1. Remove `bitsize: ?u16 = null` field from TypeResolver struct
  2. Remove the #bitsize metadata extraction for-loop in resolve() (lines 122-137)
  3. Simplify resolveExprInner: `.int_literal` stays as `RT{ .primitive = .numeric_literal }`, `.float_literal` stays as `RT{ .primitive = .float_literal }` (remove the bitsize conditional)
  4. Update error message in var_decl and const_decl from "numeric literal requires explicit type or #bitsize" to "numeric literal requires explicit type"
  5. Remove bitsize-specific unit tests, remove `resolver.bitsize = 32` from remaining tests
  </action>
  <done>No bitsize field, no bitsize logic, error message updated, tests pass</done>
</task>

<task type="auto">
  <name>Task 2: Remove #bitsize from fixtures, templates, test scripts, docs</name>
  <files>all fixture .orh files, templates, test .sh files, docs</files>
  <action>
  Remove `#bitsize = 32` from all .orh fixtures, templates, shell test heredocs, and docs.
  Update docs to remove bitsize references and explain explicit type requirement.
  </action>
  <done>Zero bitsize references anywhere in the project</done>
</task>

</tasks>
