---
phase: quick
plan: 260329-ozf
type: execute
wave: 1
depends_on: []
files_modified:
  - src/thread_safety.zig
  - test/fixtures/fail_threads.orh
autonomous: true
requirements: [thread-arg-move, thread-const-freeze, thread-mutable-reject]

must_haves:
  truths:
    - "Owned values passed to thread functions are tracked as moved — use-after-move errors fire"
    - "Const borrows (&x) passed to threads freeze the original variable — assignments emit error"
    - "Mutable borrows (var &x) passed to threads emit immediate compile error"
  artifacts:
    - path: "src/thread_safety.zig"
      provides: "Thread arg enforcement: move, freeze, reject mutable borrow"
      contains: "frozen_for_thread"
    - path: "test/fixtures/fail_threads.orh"
      provides: "Negative test cases for all three enforcement scenarios"
  key_links:
    - from: "src/thread_safety.zig"
      to: "src/declarations.zig"
      via: "ctx.decls.funcs lookup for is_thread"
      pattern: "ctx\\.decls\\.funcs\\.get"
---

<objective>
Implement thread safety enforcement for arguments passed to thread function calls.

Purpose: Currently the thread_safety pass tracks Handle lifetimes (unjoined, double-consume) but does NOT inspect the arguments passed to thread function calls. This means owned values silently escape into threads without use-after-move tracking, borrows cross thread boundaries unchecked, and mutable borrows create data races.

Output: Updated thread_safety.zig with three enforcement rules + unit tests + updated fail_threads.orh fixture.
</objective>

<execution_context>
@.claude/skills/
</execution_context>

<context>
@CLAUDE.md
@src/thread_safety.zig
@src/parser.zig (FuncDecl.is_thread, CallExpr, borrow_expr = *Node, TypePtr.kind)
@src/declarations.zig (DeclTable.funcs: StringHashMap(FuncSig), FuncSig.is_thread)
@src/sema.zig (SemanticContext.decls)
@src/constants.zig (K.Ptr.VAR_REF = "var &", K.Ptr.CONST_REF = "const &")
@src/borrow.zig (isMutableBorrowType pattern — checks type_ptr.kind == K.Ptr.VAR_REF)

<interfaces>
<!-- Key types the executor needs -->

From src/parser.zig:
```zig
pub const CallExpr = struct {
    callee: *Node,
    args: []*Node,
    arg_names: [][]const u8,
};

pub const FuncDecl = struct {
    name: []const u8,
    params: []*Node,       // each is .param
    return_type: *Node,
    body: *Node,
    is_compt: bool,
    is_pub: bool,
    is_bridge: bool,
    is_thread: bool,       // <-- key flag
    doc: ?[]const u8 = null,
};

// borrow_expr: *Node — inner node is the borrowed thing
// type_ptr: TypePtr { kind: []const u8, elem: *Node }
// Param: { name, type_annotation: *Node, default_value: ?*Node }
```

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

// DeclTable.funcs: std.StringHashMap(FuncSig)
```

From src/constants.zig:
```zig
pub const Ptr = struct {
    pub const VAR_REF = "var &";
    pub const CONST_REF = "const &";
};
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add frozen_for_thread map + thread call argument enforcement logic</name>
  <files>src/thread_safety.zig</files>
  <behavior>
    - Test: owned identifier arg to thread call → added to moved_to_thread → subsequent use errors
    - Test: const borrow_expr arg (&x) to thread call → x added to frozen_for_thread → assignment to x errors
    - Test: mutable borrow (var &x type_ptr arg) to thread call → immediate compile error
    - Test: non-thread function call → no enforcement applied
    - Test: frozen variable unfreezes after thread join (.value or .wait())
  </behavior>
  <action>
    1. Add `frozen_for_thread: std.StringHashMap([]const u8)` field to ThreadSafetyChecker (var_name -> thread_name). Initialize in `init()`, deinit in `deinit()`. Save/restore in func_decl and test_decl scope push/pop (same pattern as moved_to_thread).

    2. Add helper function `isThreadCall(self, node) ?struct { name, func_sig }`:
       - If node is .call_expr and callee is .identifier, look up `self.ctx.decls.funcs.get(callee_name)`.
       - If found and `sig.is_thread == true`, return the name + sig. Else null.

    3. Add function `checkThreadCallArgs(self, call_node)`:
       - Call `isThreadCall(self, call_node)`. If null, return (not a thread call).
       - Get the thread function name from the callee identifier.
       - Iterate call_expr.args. For each arg:
         a. If arg is `.borrow_expr`:
            - Check if the borrow is mutable by looking at the corresponding param's type_annotation in the func_sig.param_nodes. If param index matches and param.type_annotation is .type_ptr with kind == K.Ptr.VAR_REF → emit error: "cannot pass mutable borrow to thread '{thread_name}' — mutable borrows across threads are unsafe". Use `self.ctx.nodeLoc(arg)` for location.
            - Otherwise (const borrow): extract the inner identifier name from borrow_expr. Add to `frozen_for_thread.put(var_name, thread_name)`.
         b. If arg is `.identifier` → owned value move: `self.moved_to_thread.put(arg.identifier, thread_name)`.

    4. Hook `checkThreadCallArgs` into `checkStatement`:
       - In the `.call_expr` branch (line ~132), after existing handle.wait()/join() logic: call `try self.checkThreadCallArgs(node);`
       - In `.var_decl`/`.const_decl` branch: if `v.value.* == .call_expr`, call `try self.checkThreadCallArgs(v.value);`

    5. Add freeze enforcement in `checkStatement` `.assignment` branch:
       - After existing `checkExprForThreadMoves` call, check if the assignment target (left side) is a `.identifier` that exists in `frozen_for_thread`. If so, emit error: "cannot mutate '{var_name}' while it is borrowed by thread '{thread_name}'". Use `self.ctx.nodeLoc(node)` for location.

    6. Unfreeze on join: In `checkJoinExpr` for `.field_expr` where field is "value" and the identifier is a declared thread — after the existing `self.moved_to_thread.remove(name)` call, also iterate `frozen_for_thread` and remove any entries whose value (thread_name) matches the joined thread name. Similarly in `checkStatement` `.call_expr` branch where .wait()/.join() is detected.

    7. Add unit tests (Zig test blocks at bottom of file):
       - "thread safety - owned arg moved into thread": create a checker, simulate a thread func in decls with is_thread=true, build a call_expr AST node calling it with an identifier arg, run checkStatement, verify the identifier is in moved_to_thread.
       - "thread safety - const borrow arg freezes variable": build call_expr with borrow_expr(&x) arg, run checkStatement, verify x is in frozen_for_thread, then simulate assignment to x and verify error.
       - "thread safety - mutable borrow arg rejected": build call_expr with borrow_expr arg where corresponding param has type_ptr kind=VAR_REF, run checkStatement, verify error reported.
       - "thread safety - frozen var unfreezes after join": freeze x for thread t, simulate .value join on t, verify x removed from frozen_for_thread.

    Important: Import K from constants.zig at the top: `const K = @import("constants.zig");`
  </action>
  <verify>
    <automated>cd /home/yunus/Projects/orhon/orhon_compiler && zig build test 2>&1 | tail -5</automated>
  </verify>
  <done>All four enforcement behaviors work: owned args populate moved_to_thread, const borrows populate frozen_for_thread, mutable borrows emit immediate error, join unfreezes. All existing + new unit tests pass.</done>
</task>

<task type="auto">
  <name>Task 2: Add negative test fixtures for thread arg enforcement</name>
  <files>test/fixtures/fail_threads.orh</files>
  <action>
    Extend `test/fixtures/fail_threads.orh` with three new scenarios (keep existing unjoined-handle test):

    1. **Use-after-move into thread:** A function that passes an owned var to a thread call, then tries to use it after:
    ```
    thread consumer(data: i32) Handle(i32) {
        return Handle(data)
    }

    func use_after_thread_move() void {
        var x: i32 = 42
        const h: Handle(i32) = consumer(x)
        const y: i32 = x    // ERROR: use of 'x' after moved into thread
        const r: i32 = h.value
    }
    ```

    2. **Mutate frozen variable:** A function that passes &x to a thread, then tries to assign to x:
    ```
    thread reader(val: &i32) Handle(void) {
    }

    func mutate_while_borrowed() void {
        var x: i32 = 10
        const h: Handle(void) = reader(&x)
        x = 20               // ERROR: cannot mutate 'x' while borrowed by thread
        h.wait()
    }
    ```

    3. **Mutable borrow to thread:** A function that tries to pass var &x to a thread:
    ```
    thread writer(val: var &i32) Handle(void) {
    }

    func mutable_borrow_to_thread() void {
        var x: i32 = 10
        const h: Handle(void) = writer(var &x)  // ERROR: cannot pass mutable borrow to thread
        h.wait()
    }
    ```

    Note: These are negative test fixtures — they must produce compile errors. The existing test/11_errors.sh runner checks that `orhon build` fails on fail_*.orh files. Verify the fixture file is syntactically valid Orhon (it should fail at the thread_safety pass, not the parser).
  </action>
  <verify>
    <automated>cd /home/yunus/Projects/orhon/orhon_compiler && bash test/11_errors.sh 2>&1 | tail -10</automated>
  </verify>
  <done>fail_threads.orh contains all four negative scenarios (unjoined + 3 new). `test/11_errors.sh` passes, confirming the compiler rejects all cases with appropriate errors.</done>
</task>

</tasks>

<verification>
1. `zig build test` — all unit tests pass including new thread safety tests
2. `bash test/11_errors.sh` — fail_threads.orh rejected with thread safety errors
3. `./testall.sh` — full test suite green (no regressions)
</verification>

<success_criteria>
- Owned values passed as args to thread functions are tracked in moved_to_thread; subsequent use triggers "use after move into thread" error
- Const borrows (&x) passed to threads freeze the original variable; assignments trigger "cannot mutate while borrowed by thread" error
- Mutable borrows (var &x) passed to threads trigger immediate "cannot pass mutable borrow to thread" error
- Freeze is released when the thread is joined via .value or .wait()
- All existing tests continue to pass
</success_criteria>

<output>
After completion, create `.planning/quick/260329-ozf-implement-thread-safety-enforcement-move/260329-ozf-SUMMARY.md`
</output>
