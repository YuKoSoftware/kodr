# Docgen Wiring — Design Spec

## Summary

Wire `///` doc comments and `#description` metadata through the AST builder so
`orhon gendoc` produces markdown documentation with actual content. Add `-std`
flag to generate stdlib reference docs.

## Two Modes

- `orhon gendoc` — documents the user's project modules → `docs/api/`
- `orhon gendoc -std` — documents all stdlib modules → `docs/std/`

## Doc Sources

| Source | Becomes |
|--------|---------|
| `#description = "..."` in anchor file | Module-level summary paragraph |
| `///` before pub func, struct, enum, const, var, field, variant | Item-level documentation |

Only `pub` items are documented.

## Doc Comment Processing

`///` lines are:
1. Stripped of the `///` prefix
2. Trimmed of leading/trailing whitespace per line
3. Joined with newlines
4. Blank `///` lines become paragraph breaks (empty line in markdown)

Example input:
```orhon
/// Adds two numbers together.
/// Returns the sum.
///
/// Works with any i32 values.
func add(a: i32, b: i32) i32
```

Output in generated markdown:
```
Adds two numbers together.
Returns the sum.

Works with any i32 values.
```

## Output Structure

```
docs/api/
├── index.md           # table: module name → description link
├── example.md
└── mymodule.md

docs/std/
├── index.md
├── collections.md
├── str.md
└── ...
```

Each module `.md` has: module name heading, `#description` summary, then sections
for Functions, Types (structs/enums/bitfields with fields+methods), Constants.

## Changes

### 1. Builder — attach doc_block to declarations

Files: `src/peg/builder_decls.zig`, `src/peg/builder.zig`

Currently `doc_block` captures are skipped everywhere. Instead:

- When iterating children of a capture that contains `doc_block` followed by a
  declaration, extract the doc text from the `DOC_COMMENT` tokens within the
  `doc_block` capture range.
- Strip `///` prefix from each token's text, trim whitespace, join with `\n`.
- Set `.doc` on the resulting declaration node.

Applies to: `func_decl`, `struct_decl`, `enum_decl`, `bitfield_decl`,
`const_decl`, `var_decl`, `compt_decl`, `field_decl`, `enum_variant`,
`module_decl`, `blueprint_decl`, `blueprint_method`.

### 2. Builder — wire #description to module_decl.doc

File: `src/peg/builder_decls.zig`

In `buildModuleDecl` or `buildProgram`, check if a `#description` metadata node
exists. If so, use its string value as `module_decl.doc`. If a `doc_block` also
precedes the module declaration, `#description` takes precedence (it's the
canonical module summary).

### 3. Command — fix output path

File: `src/commands.zig`

Change `runGendoc` output from `docs/api/{source_dir_name}` to `docs/api/`.

### 4. CLI — add -std flag

File: `src/cli.zig`

Add `gen_std: bool = false` to `CliArgs`. Parse `-std` when command is `gendoc`.

### 5. Command — add -std mode

File: `src/commands.zig`

When `-std` flag is set:
- Call `ensureStdFiles()` to extract embedded std to `.orh-cache/std/`
- Scan and parse `.orh-cache/std/` as the source directory
- Output to `docs/std/`

## What stays the same

- `docgen.zig` — already reads `.doc` fields and generates correct markdown
- Only `pub` items documented
- Index table with module links
- Per-module markdown structure (Functions, Types, Constants sections)

## Flag convention

Single `-` prefix for flags: `-std`, not `--std`.
