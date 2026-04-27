# Orhon — Versioning Policy

## Version scheme

Orhon uses semantic versioning: `MAJOR.MINOR.PATCH` (e.g., `0.53.36`).

| Component | Meaning |
|-----------|---------|
| `MAJOR`   | Reserved for 1.0 and beyond. Signals stable language + tooling guarantees. |
| `MINOR`   | New language features, new CLI commands, new stdlib additions. May include breaking changes before 1.0. |
| `PATCH`   | Bug fixes and additive-only changes. No breaking changes. |

## Pre-1.0 policy

Orhon is currently in the `0.x` series. The following rules apply:

- **Patch bumps (`0.53.x`)** — safe to upgrade. Bug fixes, error message improvements, performance. No syntax or semantic changes.
- **Minor bumps (`0.x.0`)** — may include breaking changes to syntax, error codes, CLI flags, or codegen output. Release notes will call out every breaking change explicitly.
- **No stability guarantee** across minor versions until 1.0. The language is still being designed.

## What counts as a breaking change

- Syntax that previously compiled now produces an error
- A keyword or operator is added, removed, or reinterpreted
- An error code (`Exxxx`) is renumbered
- A CLI flag is renamed or removed
- Generated Zig output changes in a way that would break existing Zig interop code
- `orhon.project` manifest key semantics change

The following are **not** breaking changes:

- New language features (new syntax that didn't parse before)
- New error codes added to the catalog
- New CLI flags added
- Improved error messages or source locations
- Bug fixes that make previously-accepted invalid programs fail

## 1.0 milestone

1.0 will be tagged when:

1. The core language spec (`docs/01-basics.md` through `docs/15-testing.md`) is stable
2. The stdlib covers the standard use cases (collections, I/O, concurrency)
3. The compiler passes the full test suite on all supported platforms
4. A documented upgrade path exists for any remaining pre-1.0 breakage

After 1.0, minor bumps (`1.x.0`) will be additive only. Breaking changes require a major bump.

## Zig dependency

The compiler targets a specific minimum Zig version (recorded in `build.zig.zon` as `minimum_zig_version`). Patch releases will not raise the minimum Zig version. Minor releases may.
