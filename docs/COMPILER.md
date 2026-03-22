# Orhon — Compiler Internals

---

## Compilation Pipeline

Each pass runs only if the previous succeeded. Multiple errors per pass are collected before stopping.

```
Source (.orh)
    ↓
1.  Lexer           — raw text → tokens
    ↓
2.  Parser          — tokens → AST
    ↓
3.  Module Resolution
    — group files by module name
    — build dependency graph, detect circular imports
    — check incremental cache — skip unchanged modules
    ↓
4.  Declaration Pass
    — collect all type names, function signatures, struct definitions
    — does not resolve bodies yet
    ↓
5.  Compt & Type Resolution (interleaved)
    — resolve compt functions and type check simultaneously
    — resolve all `any` to concrete types
    ↓
6.  Ownership & Move Analysis
    ↓
7.  Borrow Checking
    ↓
8.  Thread Safety Analysis
    ↓
9.  Error Propagation Analysis
    ↓
10. MIR Generation
    ↓
11. Zig Code Generation
    ↓
12. Zig Compiler — produce final binary
```

### Incremental compilation
Checked at step 3. Unchanged modules with unchanged dependencies skip passes 4-12, reusing cached `.zig` files. Cache stored in `.orh-cache/`.

---

## Backend

Zig 0.15.2 is the single backend. Generated Zig code is readable and debuggable. `compt` maps to Zig's comptime. Cross-compilation, linking, and optimization are all handled by Zig.

### Zig discovery
1. Same directory as orhon binary (portable)
2. Global PATH (system installed)

---

## Project Structure

One file per pipeline pass. Tests are Zig `test` blocks in each file.

```
src/
    main.zig                // entry point, CLI, orchestrator
    lexer.zig               // pass 1
    parser.zig              // pass 2  + AST types
    module.zig              // pass 3
    declarations.zig        // pass 4
    resolver.zig            // pass 5
    ownership.zig           // pass 6
    borrow.zig              // pass 7
    thread_safety.zig       // pass 8
    propagation.zig         // pass 9
    mir.zig                 // pass 10 + MIR types
    codegen.zig             // pass 11
    zig_runner.zig          // pass 12
    types.zig               // shared — type system
    errors.zig              // shared — error formatting
    builtins.zig            // shared — builtin types
    constants.zig           // shared — constants
    cache.zig               // shared — incremental cache
    formatter.zig           // orhon fmt
```
