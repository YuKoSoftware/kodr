---
phase: quick
plan: 260328-lsa
type: execute
wave: 1
depends_on: []
files_modified:
  - src/mir.zig
  - src/codegen.zig
autonomous: true
must_haves:
  truths:
    - "Bridge functions with error-union returns and struct value params generate correct by-value Zig signatures"
    - "Non-bridge callers that pass const struct args to bridge functions do not get incorrect *const promotion"
    - "Existing const auto-borrow behavior for non-bridge functions is preserved"
  artifacts:
    - path: "src/mir.zig"
      provides: "Fix for const auto-borrow bridge guard in error-union context + test"
      contains: "is_bridge.*error_union"
    - path: "src/codegen.zig"
      provides: "Optional codegen fix if promotion leaks to signature generation"
  key_links:
    - from: "src/mir.zig"
      to: "src/codegen.zig"
      via: "const_ref_params map"
      pattern: "const_ref_params"
---

<objective>
Fix bridge struct value param const promotion in error-union functions.

When a bridge function returns `(Error | T)` and has a struct value param like
`texture: Texture`, the codegen incorrectly promotes the param to `*const Texture`
instead of keeping it by-value. Non-error-union bridge functions correctly pass
structs by value. Found in Tamga framework `createMaterial` (tamga_vk3d).

The `is_bridge` flag on FuncSig (added Phase 25) guards const auto-borrow but
may not cover all promotion paths, particularly for error-union-returning bridge
struct methods resolved via cross-module struct_methods lookup.

Purpose: Eliminate type mismatch between promoted `*const T` params and bridge
sidecar expectations of by-value `T`.

Output: Corrected const auto-borrow logic, unit tests covering the edge case.
</objective>

<execution_context>
@/home/yunus/.claude/get-shit-done/workflows/execute-plan.md
@/home/yunus/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@src/mir.zig
@src/codegen.zig
@src/declarations.zig
@src/parser.zig

<interfaces>
From src/declarations.zig:
```zig
pub const FuncSig = struct {
    name: []const u8,
    params: []ParamSig,
    param_nodes: []*parser.Node,
    return_type: types.ResolvedType,
    return_type_node: *parser.Node,
    is_compt: bool,
    is_pub: bool,
    is_thread: bool,
    is_bridge: bool = false,
};
```

From src/mir.zig (MirAnnotator):
```zig
const_ref_params: std.StringHashMapUnmanaged(std.AutoHashMapUnmanaged(usize, void))
fn annotateCallCoercions(self: *MirAnnotator, c: parser.CallExpr) !void
fn recordConstRefParam(self: *MirAnnotator, func_name: []const u8, param_idx: usize) !void
pub fn isConstRefParam(self: *const MirAnnotator, func_name: []const u8, param_idx: usize) bool
```

From src/codegen.zig (CodeGen):
```zig
fn isPromotedParam(self: *const CodeGen, func_name: []const u8, param_idx: usize) bool
// Line 688: if (self.isPromotedParam(func_name, i)) → emits "*const {s}"
```

Key code path in mir.zig annotateCallCoercions (line 510):
```zig
if (is_direct_call and arg.* == .identifier and !sig.is_bridge) {
    // const auto-borrow logic
}
```

resolveCallSig instance method path (line 706-731): looks up struct_methods
via qualified key "StructName.method", then falls back to cross-module funcs.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Reproduce, diagnose, and fix the bridge struct value param const promotion bug</name>
  <files>src/mir.zig, src/codegen.zig</files>
  <action>
**Step 1 — Reproduce the bug:**
Create a focused unit test in `src/mir.zig` (near the existing const auto-borrow tests around line 2111) that mimics the Tamga scenario:

- Register a bridge struct method via `struct_methods` (key: "Renderer.createMaterial")
  with `is_bridge = true`, return type `error_union`, and a struct value param `texture: Texture`
- Create a const variable `tex` of type `Texture` (add to `const_vars`)
- Build a field_expr call: `ren.createMaterial(tex)` with the arg resolving to `.named("Texture")`
- Set up `type_map` so the object `ren` resolves to `.named("Renderer")`
- Call `annotateCallCoercions`
- Assert that `const_ref_params` does NOT contain `("createMaterial", N)` for the texture param index
- Also assert that the arg node does NOT have a `value_to_const_ref` coercion

Run the test: `zig build test 2>&1 | grep -A 5 "bridge struct value"` — if it fails, the bug is confirmed.

**Step 2 — Diagnose the root cause:**
Trace the code path in `annotateCallCoercions`:

1. Check if `resolveCallSig` correctly returns the bridge FuncSig for a struct method call
   via the `struct_methods` path (line 716). Verify `sig.is_bridge == true`.

2. Check if `is_direct_call` is correctly `false` for field_expr callee. If true,
   the const auto-borrow block runs and `!sig.is_bridge` should guard it.

3. Look for ANY other path that populates `const_ref_params` with the function name —
   particularly check if a non-bridge function with the same name exists in `decls.funcs`
   (which would have `is_bridge = false`).

4. Check the codegen side: in `generateFuncMir` (line 688), `isPromotedParam` reads
   `const_ref_params`. If the bridge function is re-exported (line 626), its params
   are never generated — so `isPromotedParam` shouldn't matter for the bridge func itself.
   But check if a non-bridge WRAPPER function could be affected.

**Step 3 — Apply the fix:**
Based on diagnosis, likely fixes (apply the one that matches the root cause):

(a) If `resolveCallSig` fails to find the bridge sig for struct methods in certain
    cases (e.g., error-union return type changes resolution path), fix the lookup.

(b) If `const_ref_params` gets populated despite `is_bridge` guard (e.g., through
    a different call site or function name collision), add an additional guard.

(c) If the issue is in codegen's `isPromotedParam` being checked for bridge function
    names that were never meant to be in the map, add a bridge guard in codegen:
    ```zig
    // In generateFuncMir, before the isPromotedParam check:
    if (!m.is_bridge and self.isPromotedParam(func_name, i)) {
    ```
    This is a belt-and-suspenders fix — bridge funcs shouldn't reach this code
    (they return early at line 626), but it protects against edge cases.

(d) If the issue is that a NON-bridge caller function gets its param promoted because
    it passes the param to a bridge method, and then the bridge sidecar rejects the
    `*const T`: the fix is to NOT promote params that are only forwarded to bridge
    function calls. This requires tracking whether the callee is bridge when deciding
    to promote the caller's param.

After fixing, verify the new test passes.

**Important:** Do NOT change behavior for non-bridge functions. The existing const
auto-borrow tests must continue passing. Run `zig build test` to verify all unit
tests pass after the fix.
  </action>
  <verify>
    <automated>cd /home/yunus/Projects/orhon/orhon_compiler && zig build test 2>&1 | tail -20</automated>
  </verify>
  <done>
    - New unit test for bridge struct method with error-union return and struct value param
    - Test confirms bridge params are NOT promoted to *const
    - All existing const auto-borrow tests still pass
    - Root cause identified and fixed in mir.zig and/or codegen.zig
  </done>
</task>

<task type="auto">
  <name>Task 2: Integration test and Tamga workaround removal verification</name>
  <files>src/mir.zig</files>
  <action>
**Step 1 — Add a second unit test for the non-method bridge function case:**
Add a test in `src/mir.zig` that covers a direct call to a bridge function
(not a method) with error-union return and struct value param. This tests the
`!sig.is_bridge` guard at line 510 directly:

- Register a bridge function `processTexture(tex: Texture) (Error | Material)` in
  `decls.funcs` with `is_bridge = true`
- Create const var `tex` of type `Texture`
- Build a direct call: `processTexture(tex)`
- Assert `const_ref_params` does NOT contain `("processTexture", 0)`

**Step 2 — Run full test suite:**
Run `./testall.sh` to verify no regressions across all 11 test stages.

**Step 3 — Document the fix:**
Add a brief comment in `mir.zig` near the `is_bridge` guard explaining that this
covers both direct bridge calls and bridge struct method calls, including those
with error-union return types.
  </action>
  <verify>
    <automated>cd /home/yunus/Projects/orhon/orhon_compiler && ./testall.sh 2>&1 | tail -20</automated>
  </verify>
  <done>
    - Second unit test covers direct bridge function call case
    - All 11 test stages pass in testall.sh
    - Comment documents the is_bridge guard scope
  </done>
</task>

</tasks>

<verification>
1. `zig build test` — all unit tests pass including new const auto-borrow bridge tests
2. `./testall.sh` — all 11 test stages pass
3. New tests specifically verify that bridge functions (both methods and direct calls)
   with error-union return types and struct value params are NOT subject to const
   auto-borrow promotion
</verification>

<success_criteria>
- Bridge struct value params remain by-value in generated Zig when the bridge function
  returns an error union
- No regressions in non-bridge const auto-borrow behavior
- Unit tests cover the specific edge case
- The Tamga `createMaterial` workaround (changing `texture: Texture` to
  `texture: const &Texture`) would no longer be necessary (user can verify in Tamga)
</success_criteria>

<output>
After completion, create `.planning/quick/260328-lsa-fix-bridge-struct-value-param-const-prom/260328-lsa-SUMMARY.md`
</output>
