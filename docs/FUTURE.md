# Kodr — Future Ideas

Ideas and language decisions that are not yet committed.

---

## Decided Against

- **Closures** — function pointers cover the use case. Captures create ownership complexity. Pass variables as arguments instead.
- **Traits / interfaces** — `any` + `compt` covers generic type dispatch. Traits add complexity (hierarchies, orphan rules, associated types) without proportional value.
- **Coroutines / async** — threads + move semantics cover parallelism. Coroutines need a runtime, colored functions, and an executor.
- **REPL** — compiled language. `kodr run` is fast enough. A REPL needs an interpreter or incremental compiler.
- **Top-level `println`** — keep in `std::console`. One import, all I/O. No special-case global functions.
- **Collection method chaining** — `.filter().map().take()` allocates intermediate collections. For loops are explicit, zero-alloc, and already work.
- **Untagged unions** — all unions carry a tag. Safety requires knowing which type is active. Use `extern struct` with Zig sidecar for unsafe C interop.
- **Goroutines** — need a runtime, GC, scheduler. OS threads + move semantics are deterministic with no runtime overhead.
- **`Array(T, N)` / `Slice(T)` syntax** — `[N]T` and `[]T` are shorter, universal, and match array literals.
- **`else` on `for`/`while`** — confusing semantics. Use `if(items.len == 0)` instead.
- **Enum associated values** — arbitrary unions + `is` already cover this cleanly.

---

## Standard Library Roadmap

Guiding rule: foundation and building blocks only. No opinionated high-level frameworks.

### Not started
```
std.net           // raw sockets — TCP, UDP
std.encoding      // base64, hex, UTF-8, UTF-16
std.unicode       // full unicode support, normalization
std.fmt           // string formatting
std.process       // spawn processes, pipes, child processes
std.signal        // OS signals — SIGINT, SIGTERM etc
std.reflect       // type introspection
std.crypto        // primitives only — hashing, symmetric, asymmetric encryption
std.compress      // algorithms only — lz4, zstd, deflate
std.regex         // pattern matching
std.xml           // parse and emit XML
std.csv           // parse and emit CSV
std.random        // random number generation
std.hash          // fast general purpose hashing — FNV, xxHash, SipHash
std.io            // raw streams, buffers, readers, writers
std.path          // path join, split, normalize, extension, stem
std.bytes         // raw byte manipulation, endianness, bit operations
std.math.linear   // Vec2(T), Vec3(T), Vec4(T), Mat2(T), Mat3(T), Mat4(T), Quat(T)
```

### Far future
```
std.yaml          // parse and emit YAML
std.audio         // audio device access, playback primitives
std.window        // window creation, input events, platform abstraction only
std.gpu           // GPU access, compute, backend agnostic (Vulkan, OpenGL, WebGPU)
```

### Deliberately excluded
- `std.http` — too opinionated, third party
- `std.db` — too opinionated, third party
- `std.log` — too opinionated, third party
- GUI frameworks — too opinionated, third party

---

## Missing Tooling

### Language Server (LSP)
No editor integration. Blocks adoption. Needed before the language is usable day-to-day.

### Documentation Generator (`kodr doc`)
Generate HTML/Markdown docs from `pub` declarations and doc comments.

### Fuzz Testing
Use Zig's built-in `std.testing.fuzz` to fuzz the lexer and parser. Native speed, no external tools. Do this once the parser is stable.

---

## `#gpu` metadata

Reserved for future GPU/concurrency design. `thread` is implemented; `async` is deferred.
