---
status: resolved
trigger: "cimport-parse-failure — Tamga fails to compile with #cimport = { name: '...', include: '...' } syntax"
created: 2026-03-27T00:00:00Z
updated: 2026-03-27T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — "include" is lexed as `.kw_include` (a keyword), but `cimport_entry <- IDENTIFIER ':' _ expr` expects `.identifier`. The fix is to change the grammar rule to `('include' / IDENTIFIER) ':' _ expr`.
test: fix applied, building compiler to verify
expecting: Tamga compiles without parse errors
next_action: apply grammar fix + rebuild + test

## Symptoms

expected: Tamga compiles successfully with the new #cimport = { name: "...", include: "..." } syntax
actual: 3 errors — "unexpected 'include'" at line 6 in tamga_sdl3.orh, tamga_vma.orh, tamga_vk3d.orh
errors: |
  ERROR: unexpected 'include'
  at line 6
  (3 times, once per file with #cimport)
reproduction: cd /home/yunus/Projects/orhon/tamga_framework && /home/yunus/Projects/orhon/orhon_compiler/zig-out/bin/orhon build
started: After phase 24 (v0.15) which changed #cimport syntax to { name: "...", include: "..." }

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-03-27T00:01:00Z
  checked: src/lexer.zig keyword table
  found: "include" is listed as `.kw_include` at line 134; confirmed reserved keyword
  implication: any token with text "include" is lexed as `.kw_include`, not `.identifier`

- timestamp: 2026-03-27T00:02:00Z
  checked: src/orhon.peg cimport_entry rule (line 58-59)
  found: `cimport_entry <- IDENTIFIER ':' _ expr` — only accepts `.identifier` tokens as key
  implication: when parsing `include: "..."`, the lexer produces `.kw_include` which does not match `IDENTIFIER` — parse fails

- timestamp: 2026-03-27T00:03:00Z
  checked: src/peg/token_map.zig TERMINAL_MAP
  found: `IDENTIFIER` maps to `.identifier` token kind (line 107) — keywords are excluded
  implication: the grammar rule must explicitly list `'include'` as an alternative to handle keyword tokens

- timestamp: 2026-03-27T00:04:00Z
  checked: src/peg/builder.zig cimport_entry parsing (line 467)
  found: builder uses fragile `_` rule position trick to find keys; adding cimport_key rule changes children structure — builder needs rewrite to navigate properly
  implication: need both grammar fix (cimport_key rule) AND builder rewrite to navigate metadata_body -> cimport_block -> cimport_entry

- timestamp: 2026-03-27T00:05:00Z
  checked: full capture tree structure via capture.zig/grammar.zig analysis
  found: correct tree is metadata_cap.children[0]=metadata_body_cap, metadata_body_cap.children[0]=cimport_block_cap, cimport_block_cap.children=[_0,entry1,_1,entry2,...], entry.children=[cimport_key_cap, _after_colon, expr_cap]
  implication: builder must navigate 3 levels deep and filter by rule="cimport_entry" to get entries; key at entry.children[0].start_pos, value at entry.children[2]

## Resolution

root_cause: "include" is a reserved keyword in the lexer (`.kw_include`). The `cimport_entry` PEG grammar rule used `IDENTIFIER` for the key, which only matches `.identifier` tokens. Since `include` is tokenized as `.kw_include`, the parser failed with "unexpected 'include'". Additionally, the `buildMetadata` builder navigated the capture tree incorrectly — it used the old tree structure from the original grammar (with `_` rule position trick) instead of properly navigating `metadata_body_cap -> cimport_block_cap -> cimport_entry` by rule name.

fix: |
  1. Added `cimport_key <- 'include' / IDENTIFIER` rule to `src/orhon.peg` so "include" (a keyword) is accepted as a valid key
  2. Changed `cimport_entry <- IDENTIFIER ':' _ expr` to `cimport_entry <- cimport_key ':' _ expr`
  3. Rewrote `buildMetadata` cimport handler in `src/peg/builder.zig` to properly navigate the capture tree:
     - metadata_cap -> metadata_body_cap (children[0]) -> cimport_block_cap (children[0])
     - Filter block children by rule = "cimport_entry"
     - For each entry: key from children[0].start_pos (cimport_key), value from children[2] (expr)

verification: All 260 tests pass. Tamga build no longer produces "unexpected 'include'" errors — remaining errors are environment-level (missing Vulkan SDK headers).

files_changed:
  - src/orhon.peg
  - src/peg/builder.zig
